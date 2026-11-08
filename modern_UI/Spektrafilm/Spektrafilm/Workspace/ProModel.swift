import AppKit
import SwiftUI
import Observation
import UniformTypeIdentifiers

enum ProAppearance: String, CaseIterable, Identifiable {
    case system = "跟随系统", light = "浅色", dark = "深色"
    var id: String { rawValue }
    var scheme: ColorScheme? { self == .system ? nil : self == .dark ? .dark : .light }
    var appKit: NSAppearance? { self == .system ? nil : NSAppearance(named: self == .dark ? .darkAqua : .aqua) }
    var symbol: String { self == .system ? "circle.lefthalf.filled" : self == .dark ? "moon" : "sun.max" }
}

struct ProfessionalSavedFrame {
    var sidecar: Sidecar
    var pair: HalfFramePair?
}
struct ProfessionalHistory {
    var settings: [URL: ProfessionalSavedFrame]
    var membership: [(Int, Frame)]? = nil
    var selection: URL?
    var picked: Set<URL>
    var removal = false
}
struct ProfessionalExportItem: Identifiable {
    var id: URL
    var state = "等待"
}

@MainActor @Observable
final class WorkspaceStore {
    static let shared = WorkspaceStore()
    let session = Session()
    let recipes = ExportRecipeStore()
    var recipe: ExportRecipe {
        didSet { if let data = try? JSONEncoder().encode(recipe) { UserDefaults.standard.set(data, forKey: "grainagent.pro.batchRecipe") } }
    }
    var appearance: ProAppearance = ProAppearance(rawValue: UserDefaults.standard.string(forKey: "proPreview.appearance") ?? "") ?? .system {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "proPreview.appearance"); applyAppearance() }
    }
    var professional = UserDefaults.standard.bool(forKey:"grainagent.workspace.professional")
    var search = ""
    var notice = ""
    var leftVisible = true
    var rightVisible = true
    var advancedOutput = false
    var clipboardVisible = false
    var navigatorVisible = true
    var proof = false
    var queueVisible = false
    var scope = "全部照片"
    var revealAfterExport = false
    var outputFocusRequest = UUID()
    var proofRevision = 0
    var resizingWindow = false
    var professionallyEdited: Set<URL> = []
    var completed = 0
    var queue: [ProfessionalExportItem] = []
    var written: [URL] = []
    var undoStack: [ProfessionalHistory] = []
    var redoStack: [ProfessionalHistory] = []
    weak var window: NSWindow?
    @ObservationIgnored private var exportTask: Task<Void, Never>?
    @ObservationIgnored private var exportStopRequested = false
    @ObservationIgnored var windowPresentation: ((CGRect) -> Void)?
    var restoringWindow = false
    var transitioningFullscreen = false
    var fullscreen = false
    @ObservationIgnored private var suppressHistory = false
    @ObservationIgnored private var lastEditAt = Date.distantPast
    @ObservationIgnored private var lastEditURL: URL?
    @ObservationIgnored var savedFrames: [Bool: NSRect] = [:]
    @ObservationIgnored let recoveryFile = RecoveryFile<WorkspaceCheckpoint>(url:
        Sidecar.defaultStoreDirectory.deletingLastPathComponent().appending(path: "Workspace/current.json"))
    @ObservationIgnored var recoveryDocument: WorkspaceCheckpoint?
    @ObservationIgnored var recoveryTask: Task<Void, Never>?
    @ObservationIgnored var recoveryStarted = false
    @ObservationIgnored var restoringRecovery = true
    @ObservationIgnored var pendingRecoveryViewport: RecoveryViewport?
    @ObservationIgnored weak var recoverySimpleController: SimpleCameraController?
    var missingRecoveryPhotos: [RecoveryPhoto] = []
    var recoveryProblem: String?
    var resetAfterFullscreen = false
    @ObservationIgnored private var installedWindow = false
    init() {
        recipe = UserDefaults.standard.data(forKey: "grainagent.pro.batchRecipe").flatMap { try? JSONDecoder().decode(ExportRecipe.self, from: $0) } ?? recipes.selected ?? ExportRecipe.defaults[0]
        session.professionalWillEdit = { [weak self] in self?.nativeWillEdit() }
        session.professionalMenu = { [weak self] in
            guard let self, self.professional else { return nil }
            return self.canvasMenu()
        }
    }
    var catalog: StockCatalog { session.catalog }
    func saveRecipe() {
        ProNumberControl.endEditing()
        if !recipes.recipes.contains(where: { $0.id == recipe.id }) {
            let name = recipe.name
            recipes.duplicate(recipe)
            if let saved = recipes.selected { recipe = saved; recipe.name = name }
        }
        recipes.selectedID = recipe.id; recipes.selected = recipe
        notice = recipes.problem ?? "输出配方已保存"
    }
    var film: Stock? { catalog.stock(session.params.filmStock) }
    var guide: FilmGuide? { FilmGuide.entries[session.params.filmStock] }
    var currentIndex: Int? { session.frames.firstIndex { $0.id == session.selection } }
    var running: Bool { session.batchExporting }
    var status: String {
        if let error = session.lastError { return error }
        if let refusal = session.refusal?.message { return refusal }
        if !notice.isEmpty { return notice }
        if session.working { return "正在处理照片…" }
        return session.frames.isEmpty ? "装入照片以开始" : "就绪"
    }
    var targets: [URL] {
        switch scope {
        case "当前照片": return session.selection.map { [$0] } ?? []
        case "所选照片": return session.selectedFrames
        default: return session.frames.map(\.id)
        }
    }
    var folderLabel: String {
        let base: String
        switch recipe.folder { case .besideOriginal: base = G("原照片旁"); case .fixed(let path): base = URL(fileURLWithPath: path).lastPathComponent }
        return base + (recipe.subfolder.isEmpty ? "" : " / " + recipe.subfolder)
    }
    var nameContext: NamingRule.Context {
        guard let url = session.selection else { return .sampleForProfessional }
        return .init(originalName: url.deletingPathExtension().lastPathComponent, filmStock: session.params.filmStock,
                     printStock: session.params.printStock, pixelSize: session.printPixelSize, counter: 1, date: Date())
    }
    func chooseFilm(_ film: Stock) { guard !running else { return }; notice = ""; session.noFilm = false; session.selectFilmStock(film.id) }
    func matchPaper() {
        guard !running else { return }; notice = ""
        if session.filmIsPositive { var p = session.params; p.scanFilm = true; p.digitalIntermediate = false; session.params = p }
        else if let target = film?.targetPrint { session.selectPrintStock(target) }
    }
    var route: String {
        get { session.params.scanFilm ? "scan" : session.digitalIntermediateActive ? "di" : "print" }
        set {
            guard !running else { return }
            switch newValue {
            case "di": session.selectDigitalIntermediate()
            case "scan": var p = session.params; p.scanFilm = true; p.digitalIntermediate = false; session.params = p
            default: session.selectPrintStock(session.params.printStock)
            }
        }
    }
    func param<T>(_ key: WritableKeyPath<FilmParams,T>) -> Binding<T> {
        Binding(get: { self.session.params[keyPath: key] }, set: { guard !self.running else { return }; var p = self.session.params; p[keyPath:key] = $0; self.session.params = p })
    }
    func adjustment<T>(_ key: WritableKeyPath<Adjustments,T>) -> Binding<T> {
        Binding(get: { self.session.layerAdjustments[keyPath:key] }, set: { guard !self.running else { return }; var a = self.session.layerAdjustments; a[keyPath:key] = $0; self.session.layerAdjustments = a })
    }
    func choosePhotos() {
        guard !running else { return }
        let urls = Library.chooseFilesOrFolder()
        if !urls.isEmpty { importFiles(urls) }
    }
    func importFiles(_ urls: [URL]) {
        guard !running else { return }
        ProNumberControl.endEditing(); session.flushSave(); notice = ""
        if session.frames.isEmpty {
            session.open(urls: urls)
        } else {
            let newFrames = Library.frames(from: urls)
            for frame in newFrames where !session.frames.contains(where: { $0.id == frame.id }) {
                session.insertFrame(frame, at: session.frames.count)
                session.refreshState(for: frame.id)
            }
        }
        if session.selection == nil, let first = session.frames.first { session.click(first.id) }
        lastEditAt = .distantPast
    }
    func select(_ url: URL, extend: Bool = false) {
        guard !running else { return }; ProNumberControl.endEditing(); notice = ""; lastEditAt = .distantPast
        session.click(url, command: extend)
    }
    func step(_ direction: Int) { guard !running else { return }; ProNumberControl.endEditing(); notice = ""; session.selectRelative(direction); lastEditAt = .distantPast }
    func snapshot(_ urls: [URL]) -> ProfessionalHistory {
        ProfessionalHistory(settings: Dictionary(uniqueKeysWithValues: urls.map { url in
            (url, ProfessionalSavedFrame(sidecar: url == session.selection ? session.sidecar : Sidecar.load(for: url) ?? Sidecar(),
                                         pair: url == session.selection ? session.pair : HalfFramePair.load(url)))
        }), selection: session.selection, picked: session.picked)
    }
    private func nativeWillEdit() {
        guard professional, !suppressHistory, !running, let url = session.selection else { return }
        notice = ""; redoStack.removeAll()
        professionallyEdited.insert(url)
        let now = Date()
        if lastEditURL != url || now.timeIntervalSince(lastEditAt) > 0.5 {
            undoStack.append(snapshot([url])); if undoStack.count > 60 { undoStack.removeFirst() }
        }
        lastEditURL = url; lastEditAt = now
    }
    private func perform(_ urls: [URL], _ action: () -> Void) {
        guard !running else { return }; ProNumberControl.endEditing(); notice = ""; lastEditAt = .distantPast
        let before = snapshot(urls)
        suppressHistory = true; action(); suppressHistory = false
        session.flushSave()
        if before.settings.contains(where: { url,saved in saved.sidecar != (url == session.selection ? session.sidecar : Sidecar.load(for: url) ?? Sidecar()) || saved.pair != HalfFramePair.load(url) }) {
            undoStack.append(before); redoStack.removeAll()
        }
    }
    func resetSection(_ description: String, _ action: () -> Void) {
        guard let url = session.selection, !running else { return }
        let before = snapshot([url])
        perform([url], action)
        let changed = before.settings[url]?.sidecar != session.sidecar || before.settings[url]?.pair != session.pair
        notice = changed ? G("已完成：\(description) · 可撤销") : G("已是默认值")
    }
    func undo() { moveHistory(redo: false) }
    func redo() { moveHistory(redo: true) }
    private func moveHistory(redo: Bool) {
        guard !running else { return }; ProNumberControl.endEditing(); session.flushSave()
        guard let change = redo ? redoStack.popLast() : undoStack.popLast() else { return }
        var inverse = snapshot(Array(change.settings.keys))
        inverse.membership = change.membership; inverse.removal = !change.removal
        suppressHistory = true
        defer { suppressHistory = false; lastEditAt = .distantPast }
        do {
            if let members = change.membership {
                if change.removal { for (_,f) in members { session.remove(f.id) } }
                else { for (index,f) in members.sorted(by: { $0.0 < $1.0 }) where !session.frames.contains(where: { $0.id == f.id }) { session.insertFrame(f, at: min(index,session.frames.count)) } }
            }
            for (url,saved) in change.settings { try session.professionalRestore(saved.sidecar, pair: saved.pair, for: url) }
            session.professionalRestoreSelection(change.picked, active: change.selection)
            if redo { undoStack.append(inverse) } else { redoStack.append(inverse) }
            notice = redo ? "已重做" : "已撤销"
        } catch {
            notice = "恢复失败：\(error.localizedDescription)"
            if redo { redoStack.append(change) } else { undoStack.append(change) }
        }
    }
    func copy(_ url: URL? = nil) {
        guard !running, let url = url ?? session.selection else { return }; ProNumberControl.endEditing()
        session.professionalCopy(from: url); notice = "已复制 \(url.lastPathComponent) 的参数"
    }
    func paste(_ urls: [URL]? = nil) {
        guard let clip = session.clipboard else { return }
        let dest = urls ?? session.pasteTargets
        perform(dest) { session.professionalPaste(clip, to: dest) }
    }
    func sync(_ source: URL? = nil, to destinations: [URL]? = nil) {
        guard let url = source ?? session.selection else { return }
        let dest = (destinations ?? session.selectedFrames).filter { $0 != url }
        let clip = SettingsClip(groups: session.clipboardGroups, settings: url == session.selection ? session.sidecar : Sidecar.load(for: url) ?? Sidecar(), sourceName: url.lastPathComponent)
        perform(dest) { session.professionalPaste(clip, to: dest) }
    }
    func remove(_ urls: [URL]) {
        guard !running, !urls.isEmpty else { return }; ProNumberControl.endEditing(); session.flushSave()
        let set = Set(urls)
        var entry = snapshot(urls)
        entry.membership = session.frames.enumerated().filter { set.contains($0.element.id) }.map { ($0.offset,$0.element) }
        entry.removal = false; undoStack.append(entry); redoStack.removeAll()
        let index = currentIndex ?? 0
        for url in urls { session.remove(url) }
        if session.selection == nil, !session.frames.isEmpty { session.click(session.frames[min(index,session.frames.count-1)].id) }
        notice = "已从批次移除 \(urls.count) 张，磁盘原图保留，可撤销"
    }
    func reset(_ url: URL, cropOnly: Bool = false) {
        perform([url]) {
            var saved = url == session.selection ? session.sidecar : Sidecar.load(for: url) ?? Sidecar()
            if cropOnly { saved.geometry = .default } else { saved = Sidecar() }
            do { try session.professionalRestore(saved, pair: nil, for: url) } catch { notice = error.localizedDescription }
        }
    }
    func contextTargets(_ url: URL) -> [URL] { session.isPicked(url) ? session.selectedFrames : [url] }
    func showOutput(_ url: URL? = nil) {
        guard !running else { return }
        ProNumberControl.endEditing()
        if let url {
            if session.isPicked(url), session.selectedFrames.count > 1 { scope = "所选照片" }
            else { session.click(url); scope = "当前照片" }
        }
        advancedOutput = true; outputFocusRequest = UUID()
    }
    func chooseFolder() {
        guard !running else { return }; ProNumberControl.endEditing()
        let panel = NSOpenPanel(); panel.title = G("选择本批照片的输出文件夹"); panel.prompt = G("选择此文件夹")
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true; panel.allowsMultipleSelection = false
        if case .fixed(let path) = recipe.folder { panel.directoryURL = URL(fileURLWithPath:path) }
        let apply: (NSApplication.ModalResponse) -> Void = { response in if response == .OK, let url = panel.url { self.recipe.folder = .fixed(path: url.path) } }
        if let window { panel.beginSheetModal(for: window, completionHandler: apply) } else { apply(panel.runModal()) }
    }
    func runOutput() { runOutput(urls: targets) }
    /// Both workspaces share one serial queue, frozen recipe and export path.
    func runOutput(urls: [URL], progress: ((Bool, String, Int) -> Void)? = nil) {
        ProNumberControl.endEditing()
        guard !running, !urls.isEmpty else { return }
        let recipe: ExportRecipe
        do { recipe = try self.recipe.validated() }
        catch { notice = error.localizedDescription; progress?(false, G(notice), 0); return }
        // Freeze both the queue and recipe before the first suspension. The
        // native exporter reads the current Session, so lock ALL edit routes.
        let home = session.selection
        try? saveWorkspaceNow()
        session.flushSave(); session.batchExporting = true; proof = false; exportStopRequested = false
        completed = 0; written = []; queue = urls.map { .init(id:$0) }; notice = "正在输出 \(urls.count) 张照片"
        progress?(true, G(notice), 0)
        exportTask = Task {
            defer {
                session.exportProgress = nil
                session.flushSave()
                if let home, session.selection != home { session.select(home); session.requestPrint() }
                session.batchExporting = false; exportTask = nil
                let details = queue.filter { $0.state.hasPrefix("失败") || $0.state.hasPrefix("跳过") }.map { $0.id.lastPathComponent + ": " + G($0.state) }
                progress?(false, ([G(notice)] + details).joined(separator: "\n"), written.count)
                scheduleRecoverySave()
            }
            var problems: [String] = []
            for (index,url) in urls.enumerated() {
                if exportStopRequested { break }
                queue[index].state = "处理中"; session.exportProgress = Double(index)/Double(urls.count)
                progress?(true, G("正在输出 \(index+1) / \(urls.count) · \(url.lastPathComponent)"), written.count)
                if session.selection != url { session.select(url) }
                session.lastError = nil
                guard let sid = await session.ensureDeveloped() else {
                    let why = session.refusal?.message ?? session.lastError ?? "无法显影"
                    queue[index].state = "失败：" + why; problems.append(url.lastPathComponent+"："+why); completed += 1; continue
                }
                guard session.selection == url else { queue[index].state = "跳过：照片已切换"; problems.append(url.lastPathComponent); completed += 1; continue }
                do {
                    try await session.professionalPrepareExport(sessionID: sid)
                    var context = nameContext
                    context.counter = index + 1
                    let result = try await Exporter.export(session: session, recipe: recipe, context: context, sessionID: sid)
                    switch result {
                    case .wrote(let files, _, let fallback):
                        written += files; queue[index].state = fallback ? "已输出 · 色域回退 Display P3" : "已输出"
                        if fallback { problems.append("\(url.lastPathComponent)：所选色彩描述文件不可用，回退 Display P3") }
                    case .skipped: queue[index].state = "已跳过：文件存在"
                    }
                } catch is CancellationError { break }
                catch { let why = EngineMessage.userFacing(error, language: Localization.shared.resolved); queue[index].state = "失败："+why; problems.append(url.lastPathComponent+"："+why) }
                completed += 1
            }
            for i in queue.indices where queue[i].state == "等待" || queue[i].state == "处理中" { queue[i].state = "已取消" }
            notice = G("\(G(exportStopRequested ? "已停止" : "输出完成")) · 写入 \(written.count) 个文件") + (problems.isEmpty ? "" : G(" · \(problems.count) 项提示，见输出记录"))
            if !problems.isEmpty { queueVisible = true; advancedOutput = true }
            if !written.isEmpty {
                if revealAfterExport { NSWorkspace.shared.activateFileViewerSelecting(written) }
                if let app = recipe.openWith {
                    NSWorkspace.shared.open(written, withApplicationAt: URL(fileURLWithPath: app.path), configuration: NSWorkspace.OpenConfiguration()) { _,error in
                        if let error { Task { @MainActor in self.notice = "文件已输出，但打开应用失败：\(error.localizedDescription)" } }
                    }
                }
            }
        }
    }
    func finishForTermination() async { exportStopRequested = true; await exportTask?.value; session.flushSave() }
    func stopOutput() { exportStopRequested = true; notice = "正在停止，等待当前处理安全结束…" }
    func canvasMenu() -> NSMenu? {
        guard let url = session.selection else { return nil }
        if session.pair != nil { return session.pairContextMenu() }
        let menu = NSMenu()
        func item(_ title: String, enabled: Bool = true, _ action: @escaping () -> Void) {
            let target = ProfessionalMenuAction(action)
            let item = NSMenuItem(title: G(title), action: #selector(ProfessionalMenuAction.invoke), keyEquivalent: "")
            item.target = target; item.representedObject = target; item.isEnabled = enabled; menu.addItem(item)
        }
        menu.autoenablesItems = false
        item("适应窗口", enabled: !session.zoomLocked) { self.session.zoomToFit() }
        item("100%", enabled: !session.zoomLocked) { self.session.zoomTo(fraction: 1) }
        menu.addItem(.separator())
        item("复制参数",enabled: !running && session.canCopySettings) { self.copy() }
        item("粘贴参数",enabled: !running && session.canPasteSettings) { self.paste() }
        item("同步所选",enabled: !running && session.canSyncSettings) { self.sync() }
        menu.addItem(.separator())
        item("重置裁剪与方向",enabled: !running) { self.reset(url,cropOnly:true) }
        item("输出设置",enabled: !running) { self.showOutput(url) }
        return menu
    }
    func applyAppearance() { NSApp.appearance = professional ? appearance.appKit : NSAppearance(named: .darkAqua); window?.appearance = NSApp.appearance }
    func attachWindow(_ window: NSWindow) {
        self.window = window
        guard !installedWindow else { return }; installedWindow = true
        window.title = "GrainAgent"; window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true; window.isMovableByWindowBackground = false
        applyAppearance(); restoreWindow()
    }
    func switchMode(_ pro: Bool, resize: Bool = true) {
        guard professional != pro else { return }
        if let window, !transitioningFullscreen, !window.styleMask.contains(.fullScreen) { savedFrames[professional] = window.frame }
        professional = pro; applyAppearance(); if resize { restoreWindow() }
    }
    func resetWindowToDefault() {
        ProNumberControl.endEditing()
        guard let window, !transitioningFullscreen, !WorkspaceMorphCoordinator.active else { return }
        if window.styleMask.contains(.fullScreen) { resetAfterFullscreen = true; window.toggleFullScreen(nil) }
        else { restoreWindow(defaultOnly: true) }
    }
    var professionalWindowBounds: ProfessionalWindowBounds {
        let screen = window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
            ?? CGRect(origin: .zero, size: ProfessionalWindowBounds.preferred)
        return ProfessionalWindowBounds(available: window?.contentRect(forFrameRect: screen).size ?? screen.size)
    }
    func restoreWindow(defaultOnly: Bool = false, keepCurrent: Bool = false) {
        guard let window else { return }
        // AppKit otherwise caps a full-screen window at the ordinary mode's
        // maximum and fills the rest of the Space with black margins.
        if transitioningFullscreen || window.styleMask.contains(.fullScreen) {
            releaseFullscreenSizeLimits()
            return
        }
        window.contentMinSize = professional ? professionalWindowBounds.minimum : CGSize(width: 720, height: 540)
        window.contentMaxSize = professional ? professionalWindowBounds.maximum : CGSize(width: 1200, height: 900)
        let frame = modeWindowFrame(defaultOnly:defaultOnly,keepCurrent:keepCurrent)
        guard abs(frame.width-window.frame.width) > 0.5 || abs(frame.height-window.frame.height) > 0.5
            || abs(frame.minX-window.frame.minX) > 0.5 || abs(frame.minY-window.frame.minY) > 0.5 else { return }
        if defaultOnly { animateWindow(to: frame) }
        else { window.setFrame(frame, display:true, animate:!keepCurrent && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) }
    }
    func beginFullscreenTransition(entering: Bool) {
        if entering { rememberWindowFrame() }
        restoringWindow = false
        transitioningFullscreen = true; resizingWindow = true
        releaseFullscreenSizeLimits()
    }
    func endFullscreenTransition(entered: Bool) {
        fullscreen = entered; transitioningFullscreen = false; resizingWindow = false
        let reset = resetAfterFullscreen; resetAfterFullscreen = false
        restoreWindow(defaultOnly: !entered && reset)
        scheduleRecoverySave()
    }
    private func releaseFullscreenSizeLimits() {
        window?.contentMinSize = CGSize(width: 1, height: 1)
        window?.contentMaxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    }
    private func animateWindow(to target: CGRect) {
        guard let window else { return }
        // An explicit app animation preference also governs this explicit
        // reset action. The system reduce-motion setting must not silently
        // bypass the motion the user enabled in GrainAgent's View menu.
        if !UserDefaults.standard.bool(forKey: "grainagent.modeMorph.preview") {
            window.setFrame(target, display: true); rememberWindowFrame(); return
        }
        if let windowPresentation { windowPresentation(target); return }
        // Only used before the workspace presentation hook has mounted.
        window.setFrame(target, display:true, animate:true)
        rememberWindowFrame()
    }

    func modeWindowFrame(defaultOnly: Bool = false, keepCurrent: Bool = false) -> CGRect {
        guard let window else { return .zero }
        if window.styleMask.contains(.fullScreen) { return window.frame }
        let screen = window.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        var frame = keepCurrent ? window.frame : defaultOnly ? nil : savedFrames[professional]
        if frame == nil {
            var size = professional ? professionalWindowBounds.defaultSize : CGSize(width: 840, height: 630)
            let available = window.contentRect(forFrameRect: screen.insetBy(dx: 12, dy: 12)).size
            let scale = min(1, available.width / size.width, available.height / size.height)
            size = CGSize(width: floor(size.width * scale / 5) * 5, height: floor(size.height * scale / 5) * 5)
            if professional { size = professionalWindowBounds.constrain(size) }
            var rect = window.frameRect(forContentRect: CGRect(origin: .zero, size: size))
            rect.origin = CGPoint(x: screen.midX-rect.width/2, y: screen.midY-rect.height/2)
            frame = rect
        }
        if var frame {
            if professional {
                let content = professionalWindowBounds.constrain(window.contentRect(forFrameRect: frame).size)
                frame.size = window.frameRect(forContentRect: CGRect(origin: .zero, size: content)).size
            } else {
                let size = window.contentRect(forFrameRect: frame).size
                let available = window.contentRect(forFrameRect: screen).size
                let scale = min(1, available.width / size.width, available.height / size.height,
                                1200 / size.width, 900 / size.height)
                frame.size = window.frameRect(forContentRect: CGRect(origin: .zero,
                    size: CGSize(width: size.width * scale, height: size.height * scale))).size
            }
            frame.origin.x = min(max(frame.minX, screen.minX), screen.maxX-frame.width)
            frame.origin.y = min(max(frame.minY, screen.minY), screen.maxY-frame.height)
            return frame
        }
        return window.frame
    }
}

extension NamingRule.Context { static var sampleForProfessional: Self { NamingRule.sampleContext } }
@MainActor final class ProfessionalMenuAction: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func invoke() { action() }
}
