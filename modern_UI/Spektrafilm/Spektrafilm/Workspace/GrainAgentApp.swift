import AppKit
import SwiftUI

@MainActor final class GrainAgentAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    let store = WorkspaceStore.shared
    var window: NSWindow!
    private var changingFullscreen = false
    private var resizeGesture: ProfessionalResizeGesture?
    private var typingGuard: Any?
    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var terminating = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        Diagnostics.shared.start()
        store.restorePreviousWorkspace()
        window = GrainAgentWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 1000), styleMask: [.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView], backing: .buffered, defer: false)
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.title = "GrainAgent"
        window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.isOpaque = false; window.backgroundColor = .clear
        window.collectionBehavior.insert(.fullScreenPrimary)
        let hosting = NSHostingView(rootView: GrainAgentWorkspace(store: store))
        hosting.sizingOptions = []
        let surface = WorkspaceMorphSurface(frame:window.contentView!.bounds)
        surface.install(hosting)
        window.contentView = surface
        store.attachWindow(window)
        menu()
        NotificationCenter.default.addObserver(self, selector: #selector(languageChanged), name: Localization.didChange, object: nil)
        typingGuard = TypingKeyGuard.install()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if store.fullscreen {
            Task { @MainActor [weak self] in
                await Task.yield()
                guard let self, !self.window.styleMask.contains(.fullScreen) else { return }
                self.window.toggleFullScreen(nil)
            }
        }
    }
    @objc private func languageChanged() {
        menu()
        settingsWindow?.title = G("GrainAgent 设置")
        aboutWindow?.title = G("关于 GrainAgent")
        store.recoverySimpleController?.updateLanguage()
    }
    private func menu() {
        let main = NSMenu()
        let app = NSMenu(title: "GrainAgent")
        app.addItem(withTitle: G("关于 GrainAgent"), action: #selector(about), keyEquivalent: "")
        app.addItem(withTitle: G("设置…"), action: #selector(settings), keyEquivalent: ",")
        app.addItem(.separator())
        app.addItem(withTitle: G("退出 GrainAgent"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem(); appItem.submenu = app; main.addItem(appItem)
        let file = NSMenu(title: G("文件"))
        file.addItem(withTitle: G("装入照片…"), action: #selector(importPhotos), keyEquivalent: "o")
        file.addItem(withTitle: G("输出设置"), action: #selector(outputSettings), keyEquivalent: "e")
        file.addItem(withTitle: G("选择输出文件夹…"), action: #selector(chooseFolder), keyEquivalent: "")
        file.addItem(.separator())
        for (title, action) in [(G("重新检查未找到的照片"), #selector(retryMissing)),
                                (G("找回未找到的照片…"), #selector(locateMissing)),
                                (G("从批次移除未找到的照片"), #selector(forgetMissing))] {
            file.addItem(withTitle: title, action: action, keyEquivalent: "").target = self
        }
        file.addItem(.separator())
        file.addItem(withTitle: G("关闭窗口"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let fileItem = NSMenuItem(title: G("文件"), action: nil, keyEquivalent: ""); fileItem.submenu = file; main.addItem(fileItem)
        let edit = NSMenu(title: G("编辑"))
        edit.addItem(withTitle: G("撤销"), action: #selector(undo), keyEquivalent: "z")
        let redoItem = edit.addItem(withTitle: G("重做"), action: #selector(redo), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command,.shift]
        let copy = edit.addItem(withTitle: G("复制照片参数"), action: #selector(copySettings), keyEquivalent: "c")
        copy.keyEquivalentModifierMask = [.command,.shift]
        let paste = edit.addItem(withTitle: G("粘贴照片参数"), action: #selector(pasteSettings), keyEquivalent: "v")
        paste.keyEquivalentModifierMask = [.command,.shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: G("剪切"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: G("复制"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: G("粘贴"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: G("全选"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem(title: G("编辑"), action: nil, keyEquivalent: ""); editItem.submenu = edit; main.addItem(editItem)
        let view = NSMenu(title: L("View", zh: "显示"))
        view.addItem(withTitle: G("跟随系统"), action: #selector(systemAppearance), keyEquivalent: "")
        view.addItem(withTitle: G("浅色"), action: #selector(lightAppearance), keyEquivalent: "")
        view.addItem(withTitle: G("深色"), action: #selector(darkAppearance), keyEquivalent: "")
        view.addItem(.separator())
        let motion = view.addItem(withTitle:G("界面动画"),action:#selector(toggleModeMotion(_:)),keyEquivalent:"")
        motion.target = self
        motion.state = UserDefaults.standard.bool(forKey:"grainagent.modeMorph.preview") ? .on : .off
        view.addItem(withTitle: G("显示主窗口"), action: #selector(showMainWindow), keyEquivalent: "1")
        view.addItem(withTitle: G("恢复默认窗口大小"), action: #selector(resetWindow), keyEquivalent: "0")
        let viewItem = NSMenuItem(title: L("View", zh: "显示"), action: nil, keyEquivalent: ""); viewItem.submenu = view; main.addItem(viewItem)
        for item in [app, file, edit, view].flatMap(\.items) where [#selector(about),#selector(settings),#selector(outputSettings),#selector(redo),#selector(copySettings),#selector(pasteSettings),#selector(importPhotos),#selector(chooseFolder),#selector(undo),#selector(systemAppearance),#selector(lightAppearance),#selector(darkAppearance),#selector(showMainWindow),#selector(resetWindow)].contains(item.action) { item.target = self }
        installNativeCommands(main:main,edit:edit,view:view)
        NSApp.mainMenu = main
    }
    @objc private func toggleModeMotion(_ item: NSMenuItem) {
        let value = !UserDefaults.standard.bool(forKey:"grainagent.modeMorph.preview")
        UserDefaults.standard.set(value,forKey:"grainagent.modeMorph.preview")
        item.state = value ? .on : .off
        SimpleCameraController.active?.professionalInteractionMotion(value)
    }
    @objc private func about() {
        if aboutWindow == nil {
            let w = NSWindow(contentRect:NSRect(x:0,y:0,width:520,height:600), styleMask:[.titled,.closable], backing:.buffered,defer:false)
            w.title = G("关于 GrainAgent"); w.contentView = NSHostingView(rootView:AboutWindow())
            w.isReleasedWhenClosed = false; w.center(); aboutWindow = w
        }
        aboutWindow?.makeKeyAndOrderFront(nil)
    }
    @objc private func outputSettings() { if store.professional { showMainWindow(); store.showOutput() } else { _ = SimpleCameraController.command("settings") } }
    @objc private func redo() { if store.professional { store.redo() } }
    @objc private func copySettings() { if store.professional { store.copy() } }
    @objc private func pasteSettings() { if store.professional { store.paste() } }
    @objc private func settings() {
        guard !store.running else { return }
        if settingsWindow == nil {
            let view = NSHostingView(rootView:ProfessionalSettings(store:store))
            let w = NSWindow(contentRect:NSRect(x:0,y:0,width:720,height:640), styleMask:[.titled,.closable,.resizable], backing:.buffered,defer:false)
            w.title = G("GrainAgent 设置"); w.contentView = view; w.isReleasedWhenClosed = false; w.center(); settingsWindow = w
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    @objc private func importPhotos() { showMainWindow(); if store.professional { store.choosePhotos() } else { _ = SimpleCameraController.command("import") } }
    @objc private func chooseFolder() { if store.professional { showMainWindow(); store.chooseFolder() } }
    @objc private func undo() { if store.professional { store.undo() } else { _ = SimpleCameraController.command("undo") } }
    @objc private func systemAppearance() { store.appearance = .system }
    @objc private func lightAppearance() { store.appearance = .light }
    @objc private func darkAppearance() { store.appearance = .dark }
    @objc private func resetWindow() { store.resetWindowToDefault() }
    @objc private func retryMissing() { store.retryMissingPhotos() }
    @objc private func locateMissing() { store.locateMissingPhotos() }
    @objc private func forgetMissing() { store.forgetMissingPhotos() }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if [#selector(retryMissing), #selector(locateMissing), #selector(forgetMissing)].contains(menuItem.action) {
            return !store.running && !store.missingRecoveryPhotos.isEmpty
        }
        return true
    }
    @objc private func showMainWindow() {
        guard let window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }
    func windowWillClose(_ notification: Notification) {
        ProNumberControl.endEditing()
        Task {
            do {
                if !store.professional { try await store.recoverySimpleController?.flushPendingChanges() }
                try store.saveWorkspaceNow()
            } catch { store.notice = G("工作恢复记录保存失败：") + error.localizedDescription }
        }
    }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        store.importFiles(filenames.map { URL(fileURLWithPath:$0) }); showMainWindow(); sender.reply(toOpenOrPrint:.success)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        ProNumberControl.endEditing()
        guard !terminating else { return .terminateLater }
        terminating = true
        Task {
            do {
                if !store.professional { try await store.recoverySimpleController?.flushPendingChanges() }
                await store.finishForTermination()
                try store.saveWorkspaceNow()
                sender.reply(toApplicationShouldTerminate: true)
            } catch {
                let alert = NSAlert()
                alert.messageText = G("工作恢复记录未能保存")
                alert.informativeText = error.localizedDescription + G("\n取消退出可保留当前工作窗口；继续退出将使用最近一次成功保存的记录。")
                alert.addButton(withTitle: G("取消退出")); alert.addButton(withTitle: G("仍然退出"))
                let leave = alert.runModal() == .alertSecondButtonReturn
                terminating = false
                sender.reply(toApplicationShouldTerminate: leave)
            }
        }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) {
        store.session.flushSave()
        if let typingGuard { NSEvent.removeMonitor(typingGuard) }
        Diagnostics.shared.finish()
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        guard store.professional, !WorkspaceMorphCoordinator.active, let window else { return }
        resizeGesture = ProfessionalResizeGesture(bounds: store.professionalWindowBounds,
            initial: window.contentRect(forFrameRect: window.frame).size)
        store.resizingWindow = true
    }
    func windowDidEndLiveResize(_ notification: Notification) {
        resizeGesture = nil
        store.resizingWindow = false
        store.rememberWindowFrame()
        guard store.professional, !WorkspaceMorphCoordinator.active, !changingFullscreen else { return }
        store.restoreWindow(keepCurrent: true)
    }
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard !store.restoringWindow, !WorkspaceMorphCoordinator.active, store.professional, !changingFullscreen, !sender.styleMask.contains(.fullScreen) else { return frameSize }
        let proposed = sender.contentRect(forFrameRect: NSRect(origin: .zero, size: frameSize)).size
        let size: CGSize
        if resizeGesture != nil { size = resizeGesture!.constrain(proposed) }
        else { size = store.professionalWindowBounds.constrain(proposed) }
        return sender.frameRect(forContentRect: NSRect(origin: .zero, size: size)).size
    }
    func windowWillEnterFullScreen(_ notification: Notification) {
        changingFullscreen = true; store.beginFullscreenTransition(entering: true)
    }
    func windowDidEnterFullScreen(_ notification: Notification) {
        changingFullscreen = false; store.endFullscreenTransition(entered: true)
    }
    func windowWillExitFullScreen(_ notification: Notification) {
        changingFullscreen = true; store.beginFullscreenTransition(entering: false)
    }
    func windowDidExitFullScreen(_ notification: Notification) {
        changingFullscreen = false
        store.endFullscreenTransition(entered: false)
    }
    func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        changingFullscreen = false; store.endFullscreenTransition(entered: false)
    }
    func windowDidFailToExitFullScreen(_ window: NSWindow) {
        changingFullscreen = false; store.endFullscreenTransition(entered: true)
    }
    func windowDidMove(_ notification: Notification) {
        if !changingFullscreen { store.rememberWindowFrame() }
    }
    func windowDidResize(_ notification: Notification) {
        if !changingFullscreen, !window.inLiveResize { store.rememberWindowFrame() }
    }
    func windowDidChangeScreen(_ notification: Notification) {
        guard !store.restoringWindow, !WorkspaceMorphCoordinator.active, store.professional, !changingFullscreen,
              !window.inLiveResize, !window.styleMask.contains(.fullScreen) else { return }
        store.restoreWindow(keepCurrent: true)
    }
}

struct ProfessionalSettings: View {
    @Bindable var store:WorkspaceStore
    var body: some View { SettingsWindow(session:store.session).environment(\.locale, Locale(identifier: Localization.shared.resolved.localeIdentifier)).disabled(store.running) }
}
