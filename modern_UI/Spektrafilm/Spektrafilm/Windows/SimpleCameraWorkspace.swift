// The approved camera chrome controls the existing Session, Metal canvas and
// Exporter. WebKit never develops or exports image pixels.
import AppKit
import SwiftUI
import WebKit
import ImageIO
import UniformTypeIdentifiers

struct SimplePhotoSettings: Codable, Equatable {
    var film: String?
    var paper: String?
    // Keep original stage routing in copy/undo even though simple mode hides it.
    var scanFilm: Bool
    var digitalIntermediate: Bool
    var grain: Bool
    var halation: Bool
    var glare: Bool
    var border: Bool
    var date: Bool
    var dateValue: String
    var dateOrder: String
    var dateData: Bool?
    var exposureEV: Double
    var ev: Double = 0
    var grainStrength: Double

    init(sidecar: Sidecar, captureDate: String) {
        let p = sidecar.params
        film = sidecar.noFilm ? nil : p.filmStock; paper = p.printStock
        scanFilm = p.scanFilm; digitalIntermediate = p.digitalIntermediate
        grain = p.grainActive; halation = p.halationActive; glare = p.glareActive
        grainStrength = p.effects.grain; border = p.filmEdge.active; date = p.dateBack.active
        exposureEV = sidecar.adjustments.exposure
        dateData = p.dateBack.face == .data
        dateValue = captureDate; dateOrder = p.dateBack.order == .us ? "mdy" : p.dateBack.order == .dayFirst ? "dmy" : "ymd"
        if captureDate.isEmpty, let custom = p.dateBack.customText {
            if let iso = p.dateBack.customDateISO, PhotoCalendarDay(iso) != nil { dateValue = iso }
            else {
                let parts = custom.split(separator: " ").map(String.init)
                if parts.count == 3 {
                    let y = parts[p.dateBack.order == .japan ? 0 : 2].replacingOccurrences(of: "'", with: "")
                    let m = parts[p.dateBack.order == .us ? 0 : 1]
                    let d = parts[p.dateBack.order == .japan ? 2 : p.dateBack.order == .us ? 1 : 0]
                    if let year = Int(y), let month = Int(m), let day = Int(d),
                       let value = PhotoCalendarDay(year: year < 80 ? 2000+year : year < 100 ? 1900+year : year, month: month, day: day) {
                        dateValue = value.iso
                    }
                }
            }
        }
    }
    var dateText: String? {
        guard let d = PhotoCalendarDay(dateValue) else { return nil }
        return DateBackSettings.format(year: d.year, month: d.month, day: d.day,
            order: dateOrder == "mdy" ? .us : dateOrder == "dmy" ? .dayFirst : .japan)
    }
}

struct SimpleBatchOutput: Codable, Equatable {
    var format = "jpeg", quality = 95.0, color = "Display P3", size = "original"
    var longEdge = 3000, folderMode = "beside", folderPath = "", subfolder = ExportRecipe.defaultSubfolder
    func recipe(validateFolder: Bool = true) throws -> ExportRecipe {
        let formats: [String: ExportFormat] = ["jpeg": .jpeg, "png": .png, "tiff": .tiff, "di": .di]
        guard let format = formats[format] else { throw SimpleCameraError.message("不支持的输出格式。") }
        guard quality.isFinite, (1...100).contains(quality), OutputSize.bounds.contains(longEdge) else {
            throw SimpleCameraError.message("请检查输出质量和尺寸。")
        }
        let folder: ExportFolder = folderMode == "custom" ? .fixed(path: (folderPath as NSString).expandingTildeInPath) : .besideOriginal
        let spaces: [String: ExportColorSpace] = ["Display P3": .displayP3, "sRGB": .sRGB,
            "Adobe RGB (1998)": .builtIn(CGColorSpace.adobeRGB1998 as String),
            "ProPhoto RGB": .builtIn(CGColorSpace.rommrgb as String),
            "Rec. 2020": .builtIn(CGColorSpace.itur_2020 as String)]
        return try ExportRecipe(name: "简单模式 · 本批输出", format: format, colorSpace: spaces[color] ?? .displayP3,
                            folder: folder, subfolder: subfolder, existing: .addSuffix,
                            quality: quality / 100, outputSize: format != .di && size == "long-edge" ? .longEdge(longEdge) : .original).validated(validateFolder: validateFolder)
    }
}
private enum SimpleCameraError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
private struct SimplePhotoUpdate: Decodable {
    var id: String, settings: SimplePhotoSettings, rotation: Int, status: String
    var usedAsSource: Bool
}
private struct SimpleSnapshot: Decodable {
    var preferences: SimplePhotoSettings?
    var active: String?, photos: [SimplePhotoUpdate], output: SimpleBatchOutput, compare: Bool, zoom: String
    var screen: String?
    var outputScope: String?
}
private struct SimplePhotoEntry {
    var url: URL, settings: SimplePhotoSettings, captureDate: String
    var rotation: Int, status: String
    var usedAsSource = false
    var thumbnail = ""
}
private struct SimpleRemovedPhoto {
    var entry: SimplePhotoEntry, frame: Frame, index: Int, selection: URL?
}
@MainActor private final class SimplePhotoMenuAction: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func invoke() { action() }
}

@MainActor
final class SimpleCameraController: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate, CanvasHost {
    static weak var active: SimpleCameraController?
    var professionalTransition: (() -> Void)?
    var morphReady: Bool { ready }
    let session: Session
    private(set) var webView: SimpleCameraWebView?
    weak var container: SimpleCameraContainer?
    private var entries: [String: SimplePhotoEntry] = [:]
    private var order: [String] = []
    private var output = SimpleBatchOutput()
        private var professionalEditedURLs: Set<URL> = []
    private var importDefaults: SimplePhotoSettings?
    private var ready = false, importing = false
    private var displayedLanguage: Language?
    private var lastNotice = "", lastZoom = "fit", lastCompare = false
    private var importPanel: NSOpenPanel?
    private var formatPicker: NSPopUpButton?
    private var modalPanel: NSOpenPanel?
    private var returnFromProfessional = false
    private var reportedSelection: URL?
    private weak var workspace: WorkspaceStore?
    private var recoveredState = SimpleRecoveryState()
    private var restoreScreenOnReady = false
    private var removedPhotos: [String: SimpleRemovedPhoto] = [:]
    private var removalOrder: [String] = []

    init(session: Session, workspace: WorkspaceStore? = nil) {
        self.session = session; self.workspace = workspace; super.init()
        if let workspace {
            workspace.recoverySimpleController = self
            recoveredState = workspace.recoveryDocument?.simple ?? SimpleRecoveryState()
            importDefaults = recoveredState.preferences
            restoreScreenOnReady = workspace.recoveryDocument != nil
            professionalAdoptOutput(workspace.recipe)
        }
    }
    func attach(to container: SimpleCameraContainer) {
        Self.active = self; self.container = container
        session.tool = .hand; session.comparing = false; lastZoom = ""; lastCompare = false
        if webView == nil {
            let config = WKWebViewConfiguration()
            let messages = SimpleCameraMessages(self)
            config.userContentController.add(messages, name: "camera")
            config.userContentController.add(messages, name: "chooseExportFolder")
            let languageData = (try? JSONSerialization.data(withJSONObject: ["language": Localization.shared.resolved.localeIdentifier, "messages": InterfaceCopy.entries])) ?? Data("{}".utf8)
            let languageJSON = String(decoding: languageData, as: UTF8.self)
            config.userContentController.addUserScript(WKUserScript(source: "window.grainagentLanguage = \(languageJSON);", injectionTime: .atDocumentStart, forMainFrameOnly: true))
            let view = SimpleCameraWebView(frame: .zero, configuration: config)
            view.importPhotos = { [weak self] in self?.importURLs($0) }
            view.uiDelegate = self; view.navigationDelegate = self
            webView = view
            if let page = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Resources/SimpleCamera") {
                view.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
            }
        }
        container.resetWindow = { [weak self] in self?.workspace?.resetWindowToDefault() }
        if let webView { container.install(webView: webView, host: self) }
        if ready {
            if returnFromProfessional { reconcileFromSession(); returnFromProfessional = false }
            sendLibrary(showIndex: false)
        }
    }
    func updateLanguage() {
        let language = Localization.shared.resolved
        guard ready, language != displayedLanguage else { return }
        displayedLanguage = language
        container?.updateLanguage()
        send("language", ["language": language.localeIdentifier])
    }
    func detach() { container?.setInterfaceModalOpen(false); session.flushSave(); if Self.active === self { Self.active = nil }; container = nil }
    func refresh() {
        updateLanguage()
        guard Self.active === self, ready, !session.batchExporting, !importing else { return }
        if session.frames.map({ $0.id.absoluteString }) != order { reconcileFromSession(); sendLibrary(showIndex: true) }
        if let url = session.selection, url != reportedSelection, entries[url.absoluteString] != nil {
            reportedSelection = url
            send("selection", ["id": url.absoluteString])
        }
        let error = session.refusal?.message ?? session.lastError ?? ""
        if !error.isEmpty, error != lastNotice { lastNotice = error; notice(error) }
    }
    @discardableResult static func command(_ action: String) -> Bool {
        guard let controller = active else { return false }
        guard !controller.session.batchExporting else { return true }
        controller.send("command", ["action": action])
        return true
    }
    // Read back the layout for the mounted destination, rather than relying
    // on a delayed ResizeObserver message from the last time the camera ran.
    func prepareMorphLayout() async -> Bool {
        guard ready, let webView, let container,
              let result = try? await webView.evaluateJavaScript("window.grainagentPrepareMorph?.()") as? [String: Any],
              let width = result["width"] as? Double, let height = result["height"] as? Double,
              abs(width-webView.bounds.width) < 1, abs(height-webView.bounds.height) < 1,
              let body = result["layout"] as? [String: Any] else { return false }
        applyLayout(body)
        container.layoutSubtreeIfNeeded()
        return true
    }
    private func applyLayout(_ body: [String: Any]) {
        container?.setInterfaceModalOpen(body["modalOpen"] as? Bool ?? false)
        let rect = CGRect(x: body["x"] as? Double ?? 0, y: body["y"] as? Double ?? 0,
                          width: body["width"] as? Double ?? 0, height: body["height"] as? Double ?? 0)
        container?.placeCanvas(rect, visible: (body["visible"] as? Bool ?? false) && !session.batchExporting, reveal: body["reveal"] as? Double ?? 1)
        if let header = Self.rect(body["header"]) {
            let controls = (body["headerControls"] as? [Any] ?? []).compactMap(Self.rect)
            container?.placeWindowDragRegion(header, excluding: controls)
        }
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any] else { return }
        if message.name == "chooseExportFolder" { if !session.batchExporting { chooseFolder(body) }; return }
        guard let action = body["action"] as? String else { return }
        if action == "layout" {
            applyLayout(body)
            return
        }
        if action == "stop" { workspace?.stopOutput(); return }
        if action == "reveal" { if let files = workspace?.written, !files.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(files) }; return }
        guard !session.batchExporting else { return }
        switch action {
        case "photo-context":
            guard !importing, let id = body["id"] as? String, let view = webView else { return }
            do { try syncMessage(body) } catch { notice(error.localizedDescription); return }
            guard let menu = photoMenu(id: id) else { return }
            let point = CGPoint(x: body["x"] as? Double ?? 0, y: body["y"] as? Double ?? 0)
            menu.popUp(positioning: nil, at: point, in: view)
        case "remove-photo", "restore-photo":
            do {
                try syncMessage(body)
                if action == "remove-photo" { removePhoto(body) } else { restorePhoto(body) }
            } catch {
                send("photo-action-failed", [:]); notice(error.localizedDescription)
            }
        case "ready":
            ready = true; updateLanguage(); reconcileFromSession(); sendLibrary(showIndex: !restoreScreenOnReady && order.count > 1)
            if let workspace, !workspace.recoveryMessage.isEmpty { notice(workspace.recoveryMessage) }
        case "import": openImport()
        case "viewport":
            do { try syncMessage(body) } catch { notice(error.localizedDescription); return }
            if body["zoom"] as? String == "actual" { session.zoomTo(fraction: 1) }
            else { session.zoomToFit() }
        case "sync", "professional", "export":
            guard let raw = body["snapshot"], let data = try? JSONSerialization.data(withJSONObject: raw),
                  let snapshot = try? JSONDecoder().decode(SimpleSnapshot.self, from: data) else {
                notice("无法读取当前照片参数，请重新打开简单模式。"); return
            }
            do { try sync(snapshot) } catch { notice(error.localizedDescription); return }
            if action == "professional" {
                session.flushSave(); returnFromProfessional = true
                if let professionalTransition { professionalTransition() }
                else { UserDefaults.standard.set(true, forKey: "grainagent.workspace.professional") }
            } else if action == "export" { startExport(ids: body["targets"] as? [String] ?? []) }
        default: break
        }
    }
    private func syncMessage(_ body: [String: Any]) throws {
        guard let raw = body["snapshot"] else { throw SimpleCameraError.message(G("无法读取当前照片参数。")) }
        let data = try JSONSerialization.data(withJSONObject: raw)
        try sync(JSONDecoder().decode(SimpleSnapshot.self, from: data))
    }
    /// Both the thumbnail index and the Metal preview share these commands.
    /// Opening a menu does not select its target or mark it as a sample.
    private func photoMenu(id: String) -> NSMenu? {
        guard !session.batchExporting, !importing, let entry = entries[id] else { return nil }
        let menu = NSMenu(); menu.autoenablesItems = false
        func item(_ title: String, icon: String, enabled: Bool = true, _ action: @escaping () -> Void) {
            let target = SimplePhotoMenuAction(action)
            let item = NSMenuItem(title: title, action: #selector(SimplePhotoMenuAction.invoke), keyEquivalent: "")
            item.target = target; item.representedObject = target; item.isEnabled = enabled
            item.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
            menu.addItem(item)
        }
        func command(_ action: String) { self.send("photo-command", ["id": id, "action": action]) }
        let canCopy = entry.settings.film != nil && order.contains { other in
            guard other != id, let target = entries[other] else { return false }
            return !target.usedAsSource && (target.status == "new" || target.status == "copied")
        }
        item(G("预览此照片"), icon: "photo") { command("preview") }
        item(G("以此照片套用其他…"), icon: "square.on.square", enabled: canCopy) { command("copy-start") }
        menu.addItem(.separator())
        item(G("向左旋转 90°"), icon: "rotate.left") { command("rotate-left") }
        item(G("向右旋转 90°"), icon: "rotate.right") { command("rotate") }
        item(G("恢复此照片的简单模式调整"), icon: "arrow.counterclockwise") { command("reset-simple") }
        menu.addItem(.separator())
        item(G("输出此照片…"), icon: "square.and.arrow.up") { command("output-current") }
        item(G("在访达中显示"), icon: "folder") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
        menu.addItem(.separator())
        item(G("从批次移除此照片"), icon: "minus.circle") { command("remove-photo") }
        return menu
    }
    private func removePhoto(_ body: [String: Any]) {
        guard let id = body["id"] as? String, let token = body["token"] as? String,
              let entry = entries[id], let index = session.frames.firstIndex(where: { $0.id == entry.url }) else {
            send("photo-action-failed", [:]); return
        }
        session.flushSave()
        removedPhotos[token] = SimpleRemovedPhoto(entry: entry, frame: session.frames[index], index: index, selection: session.selection)
        removalOrder.append(token)
        if removalOrder.count > 60 { removedPhotos.removeValue(forKey: removalOrder.removeFirst()) }
        session.remove(entry.url)
        if session.selection == nil, !session.frames.isEmpty { session.click(session.frames[min(index,session.frames.count-1)].id) }
        send("photo-removed", ["id": id, "token": token])
        reconcileFromSession(); sendLibrary(showIndex: false)
        workspace?.scheduleRecoverySave()
        notice("已从批次移除，原文件保留 · 可撤销")
    }
    private func restorePhoto(_ body: [String: Any]) {
        guard let token = body["token"] as? String, let removed = removedPhotos[token] else {
            send("photo-action-failed", [:]); return
        }
        if !session.frames.contains(where: { $0.id == removed.entry.url }) {
            session.insertFrame(removed.frame, at: min(removed.index, session.frames.count))
        }
        entries[removed.entry.url.absoluteString] = removed.entry
        if let home = removed.selection, session.frames.contains(where: { $0.id == home }) { session.click(home) }
        removedPhotos.removeValue(forKey: token); removalOrder.removeAll { $0 == token }
        send("photo-restored", ["token": token])
        reconcileFromSession(); sendLibrary(showIndex: false)
        workspace?.scheduleRecoverySave(); notice("已撤销移除，照片与调整已恢复")
    }
    private func send(_ event: String, _ payload: [String: Any]) {
        guard ready || event == "library", let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        webView?.evaluateJavaScript("window.dispatchEvent(new CustomEvent('grainagent:\(event)',{detail:\(json)}))", completionHandler: nil)
    }
    private static func rect(_ value: Any?) -> CGRect? {
        guard let object = value as? [String: Any], let x = object["x"] as? Double,
              let y = object["y"] as? Double, let width = object["width"] as? Double,
              let height = object["height"] as? Double,
              [x, y, width, height].allSatisfy(\.isFinite), width >= 0, height >= 0 else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }
    private func object<T: Encodable>(_ value: T) -> Any { (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(value))) ?? [:] }
    private func notice(_ text: String) { send("notice", ["message": G(text)]) }

    private func reconcileFromSession() {
        session.flushSave()
        order = session.frames.map { $0.id.absoluteString }
        for frame in session.frames {
            let id = frame.id.absoluteString, previous = entries[id]
            let sidecar = session.selection == frame.id ? session.sidecar : Sidecar.load(for: frame.id) ?? Sidecar()
            let date = previous?.captureDate ?? Self.captureDate(frame.id)
            let settings = SimplePhotoSettings(sidecar: sidecar, captureDate: date)
            let rotation = sidecar.geometry.quarterTurns * 90
            let editedElsewhere = previous.map { $0.settings != settings || $0.rotation != rotation } ?? false
            entries[id] = SimplePhotoEntry(url: frame.id, settings: settings, captureDate: date,
                                           rotation: rotation,
                                           status: (editedElsewhere || professionalEditedURLs.contains(frame.id)) ? "edited" : previous?.status ?? recoveredState.photos[id]?.status ?? (sidecar.state == .unprocessed ? "new" : "edited"),
                                           usedAsSource: previous?.usedAsSource ?? recoveredState.photos[id]?.usedAsSource ?? false,
                                           thumbnail: previous?.thumbnail ?? "")
        }
        entries = entries.filter { order.contains($0.key) }
    }
    private static func captureDate(_ url: URL) -> String {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let day = ShootingData(exif: exif).captureDay else { return "" }
        return String(format: "%04d-%02d-%02d", day.year, day.month, day.day)
    }
    private func sendLibrary(showIndex: Bool) {
        professionalInteractionMotion(UserDefaults.standard.bool(forKey:"grainagent.modeMorph.preview"))
        reportedSelection = session.selection
        let rows: [[String: Any]] = order.compactMap { id in
            guard let e = entries[id] else { return nil }
            var settings = object(e.settings) as? [String: Any] ?? [:]
            // Explicit nulls are state: an omitted film would be filled with
            // the web model's default stock and turn simulation back on.
            settings["film"] = e.settings.film.map { $0 as Any } ?? NSNull()
            settings["paper"] = e.settings.paper.map { $0 as Any } ?? NSNull()
            return ["id": id, "name": e.url.lastPathComponent, "settings": settings, "rotation": e.rotation,
                    "captureDate": e.captureDate, "status": e.status, "usedAsSource": e.usedAsSource, "src": e.thumbnail]
        }
        let paperMatches = Dictionary(uniqueKeysWithValues: session.catalog.films.map { film in
            let paper = film.targetPrint.flatMap { session.catalog.stock($0) }
            return (film.id, ["paper": paper?.id ?? "", "name": paper?.name ?? "", "positive": film.isPositive] as [String: Any])
        })
        var payload: [String: Any] = ["photos": rows, "active": session.selection?.absoluteString ?? order.first ?? "", "output": object(output), "showIndex": showIndex,
                                     "paperMatches": paperMatches]
        if restoreScreenOnReady {
            payload["recovery"] = object(recoveredState)
            restoreScreenOnReady = false
        }
        send("library", payload)
        loadThumbnails()
    }
    private func loadThumbnails() {
        let ids = order.filter { entries[$0]?.thumbnail.isEmpty == true }
        Task { @MainActor [weak self] in
            guard let self else { return }
            for id in ids {
                guard let url = entries[id]?.url else { continue }
                guard let image = await ThumbnailCache.shared.thumbnail(for: url, maxPixel: 360) else { continue }
                let rep = NSBitmapImageRep(cgImage: image)
                guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { continue }
                let src = "data:image/jpeg;base64," + data.base64EncodedString()
                entries[id]?.thumbnail = src
                send("thumbnail", ["id": id, "src": src])
            }
        }
    }
    func importURLs(_ urls: [URL]) {
        guard !session.batchExporting, !importing else { return }
        let added = Library.frames(from: urls).map(\.id).filter { entries[$0.absoluteString] == nil }
        guard !added.isEmpty else { notice("没有新的受支持照片；已装入的照片会保留。"); return }
        importing = true; session.flushSave()
        if let defaults = importDefaults {
            do {
                for url in added where Sidecar.load(for: url) == nil {
                    var edit = Sidecar(), settings = defaults
                    settings.dateValue = Self.captureDate(url)
                    let previous = SimplePhotoSettings(sidecar: edit, captureDate: settings.dateValue)
                    edit.params = parameters(edit.params, settings: settings, previous: previous, captureDate: settings.dateValue)
                    edit.adjustments.exposure = min(3, max(-3, settings.exposureEV))
                    edit.noFilm = settings.film == nil
                    if settings.border { edit.heldCrop = edit.geometry }
                    try edit.save(for: url)
                }
            } catch { importing = false; notice("无法保存装入照片的初始参数：" + error.localizedDescription); return }
        }
        let current = session.selection
        session.open(urls: order.compactMap { entries[$0]?.url } + added)
        reconcileFromSession()
        if let current { session.select(current) } else if let first = added.first { session.select(first) }
        session.requestPrint()
        importing = false; sendLibrary(showIndex: true)
        notice("已装入 \(added.count) 张，共 \(order.count) 张。")
    }
    private func activateWindow() {
        NSApp.activate(ignoringOtherApps: true)
        webView?.window?.makeKeyAndOrderFront(nil)
    }
    func openImport() {
        guard !session.batchExporting, importPanel == nil, modalPanel == nil else { return }
        activateWindow()
        let panel = NSOpenPanel(); importPanel = panel
        panel.title = G("装入照片"); panel.prompt = G("装入")
        panel.message = G("JPEG 优先；可切换为全部支持格式。可多选照片或选择文件夹。")
        panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 250, height: 28))
        picker.addItems(withTitles: [G("JPEG 优先"), G("全部支持的输入格式")])
        picker.target = self; picker.action = #selector(changeImportFilter)
        formatPicker = picker; panel.accessoryView = picker; changeImportFilter()
        let response = panel.runModal(); let urls = panel.urls
        importPanel = nil; formatPicker = nil
        if response == .OK { importURLs(urls) }
    }
    @objc private func changeImportFilter() {
        importPanel?.allowedContentTypes = formatPicker?.indexOfSelectedItem == 0 ? [.jpeg]
            : ImageDecoder.openable.sorted().compactMap { UTType(filenameExtension: $0) }
    }
    private func chooseFolder(_ body: [String: Any]) {
        guard let id = body["id"] as? Int, modalPanel == nil, importPanel == nil else { return }
        activateWindow()
        let panel = NSOpenPanel(); modalPanel = panel
        panel.title = G("选择输出文件夹"); panel.prompt = G("选择此文件夹")
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if let path = body["path"] as? String, !path.isEmpty { panel.directoryURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath) }
        let response = panel.runModal(); modalPanel = nil
        send("folder-picked", ["id": id, "canceled": response != .OK, "path": response == .OK ? panel.url?.path ?? "" : ""])
    }
    // A fallback for WebKit file inputs: use the same system panel, never a DOM path or browser JPEG decoder.
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void) {
        completionHandler(nil); openImport()
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        decisionHandler(action.request.url?.isFileURL == true ? .allow : .cancel)
    }

    private func sync(_ snapshot: SimpleSnapshot) throws {
        if order.isEmpty { importDefaults = snapshot.preferences }
        // Apply edits to the previous current frame before changing selection.
        for update in snapshot.photos {
            guard var entry = entries[update.id] else { continue }
            guard update.settings.exposureEV.isFinite, update.settings.grainStrength.isFinite else { continue }
            let changed = entry.settings != update.settings || entry.rotation != update.rotation
            if changed {
                let before = entry.settings
                entry.settings = update.settings; entry.rotation = update.rotation
                try write(entry, previous: before)
                let resolved = session.selection == entry.url ? session.params : (Sidecar.load(for: entry.url)?.params ?? .default)
                entry.settings.paper = resolved.printStock
                entry.settings.scanFilm = resolved.scanFilm
                entry.settings.digitalIntermediate = resolved.digitalIntermediate
                send("resolved", ["id": update.id, "paper": resolved.printStock,
                                  "scanFilm": resolved.scanFilm, "digitalIntermediate": resolved.digitalIntermediate])
            }
            entry.status = update.status
            entry.usedAsSource = update.usedAsSource
            entries[update.id] = entry
        }
        output = snapshot.output
        if let workspace { workspace.recipe = try professionalOutputRecipe(validateFolder: false) }
        recoveredState.screen = snapshot.screen == "index" ? "index" : "preview"
        recoveredState.outputScope = snapshot.outputScope == "current" ? "current" : "all"
        recoveredState.zoom = snapshot.zoom == "actual" ? "actual" : "fit"
        if let id = snapshot.active, let entry = entries[id], session.selection != entry.url {
            // A simple-mode selection is a user's single-photo selection,
            // unlike the export worker's internal select(). Keep the picked
            // set consistent when that user returns to professional mode.
            session.click(entry.url); session.requestPrint(); reportedSelection = entry.url; lastZoom = ""; lastCompare = false
        }
        if snapshot.zoom != lastZoom { lastZoom = snapshot.zoom; if lastZoom == "actual" { session.zoomTo(fraction: 1) } else { session.zoomToFit() } }
        if snapshot.compare != lastCompare { lastCompare = snapshot.compare; session.toggledOriginal(snapshot.compare) }
        workspace?.scheduleRecoverySave()
    }
    func recoveryState() -> SimpleRecoveryState {
        var state = recoveredState
        state.preferences = importDefaults
        state.photos = Dictionary(uniqueKeysWithValues: order.compactMap { id in
            entries[id].map { (id, SimplePhotoProtection(status: $0.status, usedAsSource: $0.usedAsSource)) }
        })
        return state
    }
    func restoreRecoveryState(_ state: SimpleRecoveryState) {
        recoveredState = state; restoreScreenOnReady = true
        reconcileFromSession()
        if ready { sendLibrary(showIndex: false) }
    }
    /// Quit may arrive inside the web UI's debounce or while a text field is
    /// still focused. Read its live model, then await native parameter writes.
    func flushPendingChanges() async throws {
        guard ready, let webView, !session.batchExporting else { return }
        let raw = try await webView.evaluateJavaScript("window.grainagentCheckpoint()")
        guard let raw else { return }
        let data = try JSONSerialization.data(withJSONObject: raw)
        try sync(JSONDecoder().decode(SimpleSnapshot.self, from: data))
        session.flushSave()
    }
    private func parameters(_ source: FilmParams, settings s: SimplePhotoSettings, previous: SimplePhotoSettings, captureDate: String) -> FilmParams {
        var p = source
        if let film = s.film, session.catalog.stock(film)?.isFilm == true, film != p.filmStock {
            p.filmStock = film
            if let target = session.catalog.stock(film)?.targetPrint, session.catalog.stock(target) != nil,
               !session.catalog.isDeclaredPairing(film: film, paper: p.printStock) { p.printStock = target }
            if !session.catalog.canPrint(film: film, on: p.printStock) {
                p.printStock = session.catalog.stock(film)?.targetPrint ?? FilmParams.default.printStock
            }
            if session.catalog.stock(film)?.isPositive == true { p.scanFilm = true }
        }
        if s.paper != previous.paper, let paper = s.paper, session.catalog.stock(p.filmStock)?.isPositive != true,
           session.catalog.canPrint(film: p.filmStock, on: paper) {
            p.printStock = paper; p.scanFilm = false; p.digitalIntermediate = false
        }
        if s.scanFilm != previous.scanFilm { p.scanFilm = s.scanFilm }
        if s.digitalIntermediate != previous.digitalIntermediate { p.digitalIntermediate = s.digitalIntermediate }
        p.grainActive = s.grain; p.halationActive = s.halation; p.glareActive = s.glare
        if s.grainStrength != previous.grainStrength { p.effects.grain = s.grainStrength.clamped(to: EffectStrengths.grainRange) }; p.filmEdge.active = s.border
        p.dateBack.active = s.date
        if s.dateValue != previous.dateValue || s.dateOrder != previous.dateOrder || (s.date && s.date != previous.date) {
            p.dateBack.customText = captureDate.isEmpty ? s.dateText : nil
            p.dateBack.customDateISO = captureDate.isEmpty ? PhotoCalendarDay(s.dateValue)?.iso : nil
            p.dateBack.order = s.dateOrder == "dmy" ? .dayFirst : s.dateOrder == "mdy" ? .us : .japan
            if p.dateBack.face == .data { p.dateBack.face = .lcd }
        }
        return p
    }
    private func write(_ entry: SimplePhotoEntry, previous: SimplePhotoSettings) throws {
        let live = session.selection == entry.url
        var sidecar = live ? session.sidecar : Sidecar.load(for: entry.url) ?? Sidecar()
        let p = parameters(sidecar.params, settings: entry.settings, previous: previous, captureDate: entry.captureDate)
        let turns = ((entry.rotation / 90) % 4 + 4) % 4
        var adjustments = sidecar.adjustments
        adjustments.exposure = min(3, max(-3, entry.settings.exposureEV))
        if entry.settings.exposureEV != previous.exposureEV { adjustments.enabled = true }
        if live {
            session.params = p
            session.adjustments = adjustments
            if turns != session.geometry.quarterTurns { session.geometry = session.geometry.turned(by: turns - session.geometry.quarterTurns) }
            session.noFilm = entry.settings.film == nil
        } else {
            // The same held-crop transition as Session.filmEdgeWillChange. The
            // original Session resolves the gate against real decode dimensions on open.
            if !sidecar.params.filmEdge.effective && p.filmEdge.effective { sidecar.heldCrop = sidecar.geometry }
            if sidecar.params.filmEdge.effective && !p.filmEdge.effective {
                sidecar.geometry = sidecar.heldCrop ?? Session.unheld(sidecar.geometry); sidecar.heldCrop = nil
            }
            sidecar.params = p; sidecar.adjustments = adjustments
            sidecar.geometry = sidecar.geometry.turned(by: turns - sidecar.geometry.quarterTurns)
            sidecar.noFilm = entry.settings.film == nil
            sidecar.state = .stale
            try sidecar.save(for: entry.url)
            session.renderer.store.setPrint(nil, for: entry.url)
            session.refreshState(for: entry.url)
        }
    }

    private func startExport(ids: [String]) {
        guard let workspace, !workspace.running, !ids.isEmpty else { return }
        let targets = ids.compactMap { entries[$0] }
        guard targets.count == ids.count else { notice("照片列表已改变，请重新选择输出范围。"); return }
        guard !targets.contains(where: { $0.settings.date && $0.settings.dateData != true && $0.settings.dateText == nil }) else { notice("请先补齐开启日期戳的照片日期。"); return }
        do { workspace.recipe = try professionalOutputRecipe() } catch { notice(error.localizedDescription); return }
        // sync() has committed each photo to the common Session/sidecar store.
        // The shared worker reads each frame's own parameters and freezes one recipe.
        workspace.runOutput(urls: targets.map(\.url)) { [weak self] running, message, count in
            guard let self else { return }
            if running { container?.placeCanvas(.zero, visible: false) }
            reportedSelection = session.selection
            send("progress", ["running": running, "message": message, "written": count])
        }
    }

    // Only the original canvas's pan/zoom/original-view interactions are exposed
    // here; professional crop and masking tools remain in the professional view.
    var renderer: Renderer { session.renderer }
    var tool: CanvasTool { .hand }
    var pickerActive: Bool { false }
    var geometry: Geometry { session.geometry }
    var cropPivot: CGPoint { session.cropPivot }
    var sourceImageSize: CGSize { session.sourceImageSize }
    var maskHandles: [MaskHandle] { [] }
    func viewportChanged() { session.viewportChanged() }
    func picked(normalised: CGPoint) {}
    func geometryChanged(_ geometry: Geometry) {}
    func commitCrop() {}
    func cancelCrop() {}
    func straightenPreview(_ line: StraightenLine?) {}
    func maskHandleDragged(_ handle: MaskHandle, to normalised: CGPoint) {}
    func toggledOriginal(_ on: Bool) { if !session.batchExporting { session.toggledOriginal(on) } }
    func contextMenu() -> NSMenu? { session.selection.flatMap { photoMenu(id: $0.absoluteString) } }
    func hovered(normalised: CGPoint?) { session.hovered(normalised: normalised) }
    func stepFrame(_ delta: Int) { Self.command(delta < 0 ? "photo-prev" : "photo-next") }
}

@MainActor
private final class SimpleCameraMessages: NSObject, WKScriptMessageHandler {
    weak var owner: SimpleCameraController?
    init(_ owner: SimpleCameraController) { self.owner = owner }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        owner?.userContentController(userContentController, didReceive: message)
    }
}

@MainActor
final class SimpleCameraContainer: NSView {
    override var isFlipped: Bool { true }
    private var webView: WKWebView?
    private var canvas: CanvasNSView?
    private let canvasClip = SimpleCanvasRevealClip()
    private let windowDragRegion = SimpleWindowDragRegion()
    private var windowObservers: [any NSObjectProtocol] = []
    var resetWindow: (() -> Void)?
    private var interfaceModalOpen = false
    private lazy var defaultRatioButton: NSButton = {
        let button = NSButton(title: "4:3", target: self, action: #selector(restoreDefaultRatio))
        let metal = SimpleRatioButtonCell(textCell: "4:3")
        metal.target = self
        metal.action = #selector(restoreDefaultRatio)
        button.cell = metal
        button.controlSize = .mini
        button.font = .systemFont(ofSize: 9, weight: .medium)
        button.appearance = NSAppearance(named: .aqua)
        button.toolTip = G("恢复默认比例和窗口大小（840 × 630），保留照片和编辑参数")
        button.isHidden = true
        button.setAccessibilityLabel(G("恢复默认窗口比例"))
        return button
    }()
    func updateLanguage() {
        defaultRatioButton.toolTip = G("恢复默认比例和窗口大小（840 × 630），保留照片和编辑参数")
        defaultRatioButton.setAccessibilityLabel(G("恢复默认窗口比例"))
    }
    func install(webView: WKWebView, host: CanvasHost) {
        self.webView = webView; addSubview(webView)
        let view = CanvasNSView.configured(host: host)
        view.isHidden = true; self.canvas = view; addSubview(canvasClip); canvasClip.addSubview(view)
        windowDragRegion.isHidden = true
        addSubview(windowDragRegion)
        addSubview(defaultRatioButton)
        needsLayout = true
    }
    override func layout() {
        super.layout()
        webView?.frame = bounds
        positionDefaultRatioButton()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopObservingWindow()
        guard let window else { return }
        for name in [NSWindow.didResizeNotification, NSWindow.didExitFullScreenNotification,
                     NSWindow.didEnterFullScreenNotification] {
            windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.positionDefaultRatioButton()
                }
            })
        }
        positionDefaultRatioButton()
    }
    func stopObservingWindow() {
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers.removeAll()
    }
    private func positionDefaultRatioButton() {
        guard let window else { return }
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .compactMap { window.standardWindowButton($0) }
            .filter { $0.window === window && !$0.isHiddenOrHasHiddenAncestor }
        let row = buttons.map { $0.convert($0.bounds, to: self) }.reduce(CGRect.null) { $0.union($1) }
        // Follow the actual system buttons, rather than duplicating a theme's
        // assumed traffic-light coordinates. Fullscreen may hide its titlebar.
        let x = row.isNull ? 14 : max(6, row.midX - 22)
        let y = row.isNull ? 33 : max(30, row.maxY + 6)
        defaultRatioButton.frame = CGRect(x: x, y: min(46, y), width: 44, height: 18)
    }
    @objc private func restoreDefaultRatio() { resetWindow?() }
    func setInterfaceModalOpen(_ open: Bool) {
        interfaceModalOpen = open
        // Web overlays cannot cover titlebar siblings; hide native controls
        // for the same modal lifetime, then restore them on dismissal.
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { window?.standardWindowButton(type)?.isHidden = open }
        defaultRatioButton.isHidden = open
        windowDragRegion.isHidden = open || windowDragRegion.frame.isEmpty
    }
    func placeWindowDragRegion(_ rect: CGRect, excluding controls: [CGRect]) {
        let clipped = rect.intersection(bounds)
        guard !clipped.isNull, !clipped.isEmpty else { windowDragRegion.isHidden = true; return }
        windowDragRegion.frame = clipped
        windowDragRegion.exclusions = controls.map { $0.offsetBy(dx: -clipped.minX, dy: -clipped.minY) }
        windowDragRegion.isHidden = interfaceModalOpen
    }
    func placeCanvas(_ rect: CGRect, visible: Bool, reveal: Double = 1) {
        guard rect.minX.isFinite, rect.minY.isFinite, rect.width.isFinite, rect.height.isFinite, reveal.isFinite else { return }
        let clipped = rect.intersection(bounds)
        guard !clipped.isNull, !clipped.isEmpty, let canvas else { canvasClip.isHidden = true; return }
        let fraction = min(1, max(0, reveal))
        let show = visible && fraction > 0
        let fullFrame = CGRect(origin: .zero, size: clipped.size)
        let needsDraw = show && (canvas.isHidden || canvas.frame != fullFrame)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        canvasClip.frame = CGRect(x: clipped.minX, y: clipped.minY, width: clipped.width, height: clipped.height * fraction)
        if canvas.frame != fullFrame { canvas.frame = fullFrame }
        canvasClip.isHidden = !show
        canvas.isHidden = !show
        CATransaction.commit()
        if needsDraw { canvas.scheduleDraw() }
    }
}

/// Small machined-metal key; AppKit retains native hit testing, keyboard and AX actions.
@MainActor
private final class SimpleRatioButtonCell: NSButtonCell {
    override func drawBezel(withFrame frame: NSRect, in controlView: NSView) {
        let pressed = isHighlighted
        let body = frame.insetBy(dx: 0.75, dy: 1.25).offsetBy(dx: 0, dy: pressed ? 0.5 : -0.5)
        let shape = NSBezierPath(roundedRect: body, xRadius: 3, yRadius: 3)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(pressed ? 0.12 : 0.42)
        shadow.shadowBlurRadius = pressed ? 0 : 1
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
        NSColor(white: 0.62, alpha: 1).setFill(); shape.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        if let image = CameraHardware.images["brushed-metal-v2"] {
            image.draw(in: body, from: NSRect(x: 0, y: 0, width: body.width * 3, height: body.height * 3),
                       operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        NSGradient(starting: NSColor.white.withAlphaComponent(pressed ? 0.03 : 0.34),
                   ending: NSColor.black.withAlphaComponent(pressed ? 0.24 : 0.15))?.draw(in: body, angle: 90)
        NSGraphicsContext.restoreGraphicsState()
        NSColor(white: 0.32, alpha: 0.9).setStroke(); shape.lineWidth = 0.7; shape.stroke()
        let lip = NSBezierPath()
        lip.move(to: NSPoint(x: body.minX + 3, y: body.minY + 1))
        lip.line(to: NSPoint(x: body.maxX - 3, y: body.minY + 1))
        NSColor.white.withAlphaComponent(pressed ? 0.18 : 0.7).setStroke()
        lip.lineWidth = 0.6; lip.stroke()
    }

    override func drawTitle(_ title: NSAttributedString, withFrame frame: NSRect, in controlView: NSView) -> NSRect {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
                                                        .foregroundColor: NSColor(white: 0.2, alpha: 1)]
        let text = NSAttributedString(string: "4:3", attributes: attributes)
        let size = text.size()
        let origin = NSPoint(x: controlView.bounds.midX - size.width / 2,
                             y: controlView.bounds.midY - size.height / 2 + (isHighlighted ? 0.5 : -0.5))
        let glint = NSMutableAttributedString(attributedString: text)
        glint.addAttribute(.foregroundColor, value: NSColor.white.withAlphaComponent(0.72), range: NSRange(location: 0, length: glint.length))
        glint.draw(at: NSPoint(x: origin.x, y: origin.y + 0.7))
        text.draw(at: origin)
        return frame
    }
}
/// The metal cap is a real AppKit window drag surface. It passes interactive
/// controls through to WebKit and keeps standard traffic-light hit targets intact.
@MainActor
private final class SimpleWindowDragRegion: NSView {
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    var exclusions: [CGRect] = []
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, let parent = superview else { return nil }
        let local = convert(point, from: parent)
        guard bounds.contains(local), !exclusions.contains(where: { $0.contains(local) }) else { return nil }
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            if let button = window?.standardWindowButton(type),
               button.bounds.contains(button.convert(local, from: self)) { return nil }
        }
        return self
    }
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        if event.clickCount == 2 {
            switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
            case "Minimize": window.performMiniaturize(nil)
            case "None": break
            default: window.performZoom(nil)
            }
        } else {
            window.performDrag(with: event)
        }
    }
}
@MainActor
final class SimpleCameraWebView: WKWebView {
    var importPhotos: (([URL]) -> Void)?
    private func files(_ sender: NSDraggingInfo) -> [URL] {
        (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { files(sender).isEmpty ? super.draggingEntered(sender) : .copy }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { files(sender).isEmpty ? super.draggingUpdated(sender) : .copy }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { !files(sender).isEmpty || super.prepareForDragOperation(sender) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = files(sender); guard !urls.isEmpty else { return super.performDragOperation(sender) }
        importPhotos?(urls); return true
    }
}
struct SimpleCameraWorkspace: NSViewRepresentable {
    let controller: SimpleCameraController
    func makeNSView(context: Context) -> SimpleCameraContainer {
        let view = SimpleCameraContainer(); controller.attach(to: view); return view
    }
    func updateNSView(_ nsView: SimpleCameraContainer, context: Context) {
        _ = Localization.shared.resolved
        _ = controller.session.selection; _ = controller.session.frames
        _ = controller.session.busy; _ = controller.session.lastError
        controller.refresh()
    }
    static func dismantleNSView(_ nsView: SimpleCameraContainer, coordinator: ()) {
        nsView.stopObservingWindow()
        SimpleCameraController.active?.detach()
    }
}
/// Clips the original live canvas while the camera's screen page slides over it.
/// Its inner canvas does not resize with the moving edge.
@MainActor private final class SimpleCanvasRevealClip: NSView {
    override var isFlipped: Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        isHidden = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, let superview, bounds.contains(convert(point, from: superview)) else { return nil }
        return super.hitTest(point)
    }
}

extension SimpleCameraController {
    func professionalInteractionMotion(_ enabled: Bool) { send("motion",["preview":enabled]) }
    func professionalProtect(_ urls: Set<URL>) { professionalEditedURLs.formUnion(urls) }
    func professionalAdoptOutput(_ recipe: ExportRecipe) {
        output.format = recipe.format == .jpeg ? "jpeg" : recipe.format == .png ? "png" : recipe.format == .tiff ? "tiff" : "di"
        output.quality = recipe.quality * 100
        output.color = recipe.colorSpace == .builtIn(CGColorSpace.rommrgb as String) ? "ProPhoto RGB" : ColorSpaceCatalog.name(for: recipe.colorSpace) ?? "Display P3"
        output.size = recipe.outputSize.isOriginal ? "original" : "long-edge"
        output.longEdge = recipe.outputSize.edge ?? 3000
        output.subfolder = recipe.subfolder
        switch recipe.folder { case .besideOriginal: output.folderMode = "beside"; output.folderPath = ""
        case .fixed(let path): output.folderMode = "custom"; output.folderPath = path }
        if ready { reconcileFromSession(); sendLibrary(showIndex:false) }
    }
    func professionalOutputRecipe(validateFolder: Bool = true) throws -> ExportRecipe {
        let simple = try output.recipe(validateFolder: validateFolder)
        guard var merged = workspace?.recipe else { return simple }
        merged.format = simple.format; merged.quality = simple.quality
        if output.color != ColorSpaceCatalog.name(for: merged.colorSpace),
           !(output.color == "ProPhoto RGB" && merged.colorSpace == .builtIn(CGColorSpace.rommrgb as String)) {
            merged.colorSpace = simple.colorSpace
        }
        merged.outputSize = simple.outputSize; merged.folder = simple.folder; merged.subfolder = simple.subfolder
        return merged
    }
}
