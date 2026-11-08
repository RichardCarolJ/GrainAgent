import AppKit
import Observation

struct SimplePhotoProtection: Codable {
    var status: String
    var usedAsSource: Bool
}
struct SimpleRecoveryState: Codable {
    var photos: [String: SimplePhotoProtection] = [:]
    var preferences: SimplePhotoSettings?
    var screen = "preview"
    var outputScope = "all"
    var zoom = "fit"
}
struct RecoveryPhoto: Codable {
    var url: URL
    var bookmark: Data?
    var identity: Sidecar.Source
    var sidecar: Sidecar
    var pair: HalfFramePair?
}
struct RecoveryInterface: Codable {
    var professional = true
    var fullScreen: Bool? = nil
    var leftVisible = true, rightVisible = true, navigatorVisible = true
    var advancedOutput = false, clipboardVisible = false, filmstripCollapsed = false
    var scope = "全部照片", search = ""
    var revealAfterExport = false
    var windowFrames: [String: CGRect] = [:]
    var viewport: RecoveryViewport?
}
struct RecoveryViewport: Codable {
    var fit: Bool
    var zoom: Double
    var centre: CGPoint
    init(_ value: ViewportState) {
        fit = value.isFit; zoom = value.zoomFraction
        centre = CGPoint(x: (value.viewport.width / 2 - value.offset.x) / max(1, value.image.width * value.scale),
                         y: (value.viewport.height / 2 - value.offset.y) / max(1, value.image.height * value.scale))
    }
}
struct WorkspaceCheckpoint: Codable {
    var savedAt = Date()
    var photos: [RecoveryPhoto] = []
    var current: URL?
    var picked: [URL] = []
    var professionallyEdited: Set<URL> = []
    var recipe: ExportRecipe
    var simple = SimpleRecoveryState()
    var interface = RecoveryInterface()
    var exportWasRunning = false
}

extension WorkspaceStore {
    /// Called before the first view is installed: its empty defaults must not
    /// race the disk checkpoint, nor overwrite the saved mode through AppStorage.
    func restorePreviousWorkspace() {
        guard !recoveryStarted else { return }
        recoveryStarted = true
        let loaded = recoveryFile.load()
        if let checkpoint = loaded.value {
            recoveryDocument = checkpoint
            recipe = checkpoint.recipe
            let ui = checkpoint.interface
            professional = ui.professional
            fullscreen = ui.fullScreen ?? false
            UserDefaults.standard.set(professional, forKey: "grainagent.workspace.professional")
            leftVisible = ui.leftVisible; rightVisible = ui.rightVisible
            navigatorVisible = ui.navigatorVisible; advancedOutput = ui.advancedOutput
            clipboardVisible = ui.clipboardVisible; session.filmstripCollapsed = ui.filmstripCollapsed
            scope = ui.scope; search = ui.search; revealAfterExport = ui.revealAfterExport
            savedFrames = Dictionary(uniqueKeysWithValues: ui.windowFrames.compactMap { key, value in
                guard ["simple", "professional"].contains(key), value.width.isFinite, value.height.isFinite,
                      value.minX.isFinite, value.minY.isFinite, value.width > 0, value.height > 0 else { return nil }
                return (key == "professional", value)
            })
            professionallyEdited = checkpoint.professionallyEdited
            restoreRecoveryPhotos()
            if session.selection == checkpoint.current { pendingRecoveryViewport = ui.viewport }
            if checkpoint.exportWasRunning { notice += " · 上次输出已中断，请确认后重新输出" }
            if loaded.usedBackup { notice += " · 已从备用工作记录恢复" }
        } else if let problem = loaded.problem { recoveryProblem = problem; notice = problem }
        if !UserDefaults.standard.bool(forKey: "grainagent.outputFolderDefault.v2") {
            if recipe.subfolder == "_prints" { recipe.subfolder = ExportRecipe.defaultSubfolder }
            UserDefaults.standard.set(true, forKey: "grainagent.outputFolderDefault.v2")
        }
        restoringRecovery = false
        observeWorkspaceRecovery()
    }

    private func resolvedURL(_ photo: RecoveryPhoto) -> URL? {
        func accepts(_ url: URL) -> Bool {
            guard FileManager.default.isReadableFile(atPath: url.path) else { return false }
            // Pair documents are owned by the app and replaced atomically when
            // edited, so their inode legitimately changes without a relocation.
            if HalfFramePair.isPair(url), HalfFramePair.load(url) != nil { return true }
            let identity = Sidecar.identity(of: url, includingDigest: false)
            return photo.identity.inode == nil || photo.identity.matches(identity)
        }
        if accepts(photo.url) { return photo.url }
        if let data = photo.bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting],
                                 relativeTo: nil, bookmarkDataIsStale: &stale), accepts(url) { return url }
        }
        return nil
    }

    private func restoreRecoveryPhotos() {
        guard var document = recoveryDocument else { return }
        var available: [URL] = [], missing: [RecoveryPhoto] = []
        for index in document.photos.indices {
            let photo = document.photos[index]
            guard let url = resolvedURL(photo) else { missing.append(photo); continue }
            do {
                // Existing sidecars may have newer edits from another front door.
                // The checkpoint repairs a missing sidecar, never rolls one back.
                if Sidecar.load(for: url) == nil { try photo.sidecar.save(for: url) }
                if let pair = photo.pair, HalfFramePair.load(url) == nil { try pair.save(to: url) }
            } catch { recoveryProblem = "无法恢复照片参数：\(error.localizedDescription)"; missing.append(photo); continue }
            if url != photo.url { remapRecoveryURL(photo.url, to: url, in: &document) }
            if !available.contains(url) { available.append(url) }
        }
        recoveryDocument = document
        missingRecoveryPhotos = missing
        professionallyEdited = document.professionallyEdited
        let current = document.current.flatMap { available.contains($0) ? $0 : nil } ?? available.first
        session.restoreWorkspace(available.map { Frame(id: $0) }, current: current, picked: Set(document.picked))
        if !professional, current != nil { session.requestPrint() }
        notice = recoveryMessage
    }

    var recoveryMessage: String {
        let restored = session.frames.count
        if !missingRecoveryPhotos.isEmpty {
            return "已恢复 \(restored) 张 · \(missingRecoveryPhotos.count) 张暂未找到，可在“文件 → 找回未找到的照片”重新定位"
        }
        return restored > 0 ? "已恢复上次工作 · \(restored) 张照片" : ""
    }

    private func remapRecoveryURL(_ old: URL, to url: URL, in document: inout WorkspaceCheckpoint) {
        for index in document.photos.indices where document.photos[index].url == old {
            document.photos[index].url = url
            document.photos[index].identity = Sidecar.identity(of: url)
            document.photos[index].bookmark = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        if document.current == old { document.current = url }
        document.picked = document.picked.map { $0 == old ? url : $0 }
        if document.professionallyEdited.remove(old) != nil { document.professionallyEdited.insert(url) }
        if let protection = document.simple.photos.removeValue(forKey: old.absoluteString) { document.simple.photos[url.absoluteString] = protection }
    }

    /// Observation covers native edits, membership, selection and output changes;
    /// the web bridge explicitly schedules after its 65 ms snapshot has arrived.
    func observeWorkspaceRecovery() {
        withObservationTracking {
            _ = session.frames; _ = session.selection; _ = session.picked; _ = session.sidecar
            _ = session.batchExporting; _ = professionallyEdited; _ = recipe; _ = professional
            _ = leftVisible; _ = rightVisible; _ = navigatorVisible; _ = advancedOutput
            _ = clipboardVisible; _ = session.filmstripCollapsed; _ = scope; _ = search; _ = revealAfterExport
            _ = session.viewportSnapshot; _ = session.nativeSourceSize
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.applyRecoveryViewportIfReady()
                self.scheduleRecoverySave()
                self.observeWorkspaceRecovery()
            }
        }
    }
    func applyRecoveryViewportIfReady() {
        guard let value = pendingRecoveryViewport, session.nativeSourceSize != nil,
              session.viewportSnapshot.viewport.width > 1, session.viewportSnapshot.image.width > 1 else { return }
        pendingRecoveryViewport = nil
        if value.fit { session.zoomToFit() }
        else if value.zoom.isFinite, value.centre.x.isFinite, value.centre.y.isFinite {
            session.zoomTo(fraction: value.zoom.clamped(to: 0.05...8))
            session.centreView(onNormalised: value.centre)
        }
    }
    func scheduleRecoverySave() {
        guard recoveryStarted, !restoringRecovery, recoveryProblem == nil else { return }
        recoveryTask?.cancel()
        recoveryTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, let self else { return }
            do { try self.saveWorkspaceNow() }
            catch { self.notice = "工作恢复记录保存失败：" + error.localizedDescription }
        }
    }
    func rememberWindowFrame() {
        guard let window, !transitioningFullscreen, !window.styleMask.contains(.fullScreen), !WorkspaceMorphCoordinator.active, !restoringWindow else { return }
        savedFrames[professional] = window.frame
        scheduleRecoverySave()
    }
    func saveWorkspaceNow() throws {
        recoveryTask?.cancel()
        guard recoveryStarted, !restoringRecovery else { return }
        session.flushSave()
        rememberWindowFrame()
        recoveryTask?.cancel()
        if !professional, let simple = recoverySimpleController {
            let updated = try simple.professionalOutputRecipe(validateFolder: false)
            if recipe != updated { recipe = updated }
        }
        let previous = recoveryDocument
        let existing = Dictionary(uniqueKeysWithValues: (previous?.photos ?? []).map { ($0.url, $0) })
        let photos = session.frames.map { frame -> RecoveryPhoto in
            let edit = frame.id == session.selection ? session.sidecar : Sidecar.load(for: frame.id) ?? Sidecar()
            if var cached = existing[frame.id] { cached.sidecar = edit; cached.pair = HalfFramePair.load(frame.id); return cached }
            return RecoveryPhoto(url: frame.id,
                bookmark: try? frame.id.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil),
                identity: Sidecar.identity(of: frame.id), sidecar: edit, pair: HalfFramePair.load(frame.id))
        }
        // Retain missing originals in their slots, including when all photos
        // live on an offline disk. An empty visible library is not an empty job.
        let missing = Set(missingRecoveryPhotos.map(\.url))
        var iterator = photos.makeIterator(), merged: [RecoveryPhoto] = []
        for old in previous?.photos ?? [] {
            if missing.contains(old.url) { merged.append(old) }
            else if let next = iterator.next() { merged.append(next) }
        }
        while let next = iterator.next() { merged.append(next) }
        let ui = RecoveryInterface(professional: professional, fullScreen: fullscreen, leftVisible: leftVisible, rightVisible: rightVisible,
            navigatorVisible: navigatorVisible, advancedOutput: advancedOutput, clipboardVisible: clipboardVisible,
            filmstripCollapsed: session.filmstripCollapsed, scope: scope, search: search, revealAfterExport: revealAfterExport,
            windowFrames: Dictionary(uniqueKeysWithValues: savedFrames.map { ($0.key ? "professional" : "simple", $0.value) }),
            viewport: pendingRecoveryViewport ?? (session.nativeSourceSize == nil ? previous?.interface.viewport : RecoveryViewport(session.viewportSnapshot)))
        var document = WorkspaceCheckpoint(photos: merged,
            current: running ? previous?.current ?? session.selection : session.selection,
            picked: running ? previous?.picked ?? Array(session.picked) : Array(session.picked),
            professionallyEdited: professionallyEdited, recipe: recipe,
            simple: recoverySimpleController?.recoveryState() ?? previous?.simple ?? SimpleRecoveryState(), interface: ui,
            exportWasRunning: running)
        // Missing photos keep their protection state until explicitly removed.
        for url in missing { if let value = previous?.simple.photos[url.absoluteString] { document.simple.photos[url.absoluteString] = value } }
        try recoveryFile.save(document)
        recoveryDocument = document
    }
    func retryMissingPhotos() {
        guard !running, !missingRecoveryPhotos.isEmpty else { return }
        do { try saveWorkspaceNow() } catch { notice = error.localizedDescription; return }
        restoringRecovery = true; restoreRecoveryPhotos(); restoringRecovery = false
        recoverySimpleController?.restoreRecoveryState(recoveryDocument?.simple ?? SimpleRecoveryState())
        scheduleRecoverySave()
    }
    func locateMissingPhotos() {
        guard !running, !missingRecoveryPhotos.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.title = G("找回未找到的照片"); panel.prompt = G("找回照片")
        panel.message = G("选择原照片现在所在的文件夹或文件。未找到的记录会继续保留。")
        panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        do { try saveWorkspaceNow() } catch { notice = error.localizedDescription; return }
        guard var document = recoveryDocument else { return }
        let candidates = Library.frames(from: panel.urls).map(\.id)
        var used = Set(session.frames.map(\.id))
        for photo in missingRecoveryPhotos {
            let match = candidates.first { url in
                guard !used.contains(url) else { return false }
                let source = Sidecar.identity(of: url)
                return photo.identity.matches(source) || (url.lastPathComponent == photo.url.lastPathComponent
                    && source.size == photo.identity.size && source.headDigest != nil && source.headDigest == photo.identity.headDigest)
            }
            guard let match else { continue }
            do { try photo.sidecar.save(for: match) }
            catch { notice = "无法恢复照片参数：" + error.localizedDescription; return }
            remapRecoveryURL(photo.url, to: match, in: &document); used.insert(match)
        }
        recoveryDocument = document
        restoringRecovery = true; restoreRecoveryPhotos(); restoringRecovery = false
        recoverySimpleController?.restoreRecoveryState(document.simple)
        scheduleRecoverySave()
    }
    func forgetMissingPhotos() {
        guard !running else { return }
        let urls = Set(missingRecoveryPhotos.map(\.url))
        recoveryDocument?.photos.removeAll { urls.contains($0.url) }
        missingRecoveryPhotos = []
        notice = "已从本批次移除未找到的照片，原照片及调色参数保留"
        scheduleRecoverySave()
    }
}
