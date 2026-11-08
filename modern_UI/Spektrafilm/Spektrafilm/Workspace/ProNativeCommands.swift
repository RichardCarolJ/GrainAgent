import AppKit
import SwiftUI

/// Keep the original editor shortcuts, including validation while exporting.
@MainActor private final class ProfessionalCommand: NSObject, NSMenuItemValidation {
    let enabled: () -> Bool
    let action: () -> Void
    init(enabled: @escaping () -> Bool, action: @escaping () -> Void) { self.enabled = enabled; self.action = action }
    @objc func invoke() { guard enabled() else { return }; ProNumberControl.endEditing(); action() }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { enabled() }
}

extension GrainAgentAppDelegate {
    func installNativeCommands(main:NSMenu, edit:NSMenu, view:NSMenu) {
        let s = store.session
        let available = { !self.store.running && s.selection != nil }
        let pro = { available() && self.store.professional }
        let zoom = { available() && !s.zoomLocked && !self.store.proof }
        func add(_ menu:NSMenu, _ title:String, _ key:String = "", _ modifiers:NSEvent.ModifierFlags = .command,
                 enabled:@escaping () -> Bool, action:@escaping () -> Void) {
            let target = ProfessionalCommand(enabled:enabled,action:action)
            let item = NSMenuItem(title:title,action:#selector(ProfessionalCommand.invoke),keyEquivalent:key)
            item.keyEquivalentModifierMask = modifiers; item.target = target; item.representedObject = target
            menu.addItem(item)
        }
        func section(_ title:String)->NSMenu {
            let menu = NSMenu(title:title), item = NSMenuItem(title:title,action:nil,keyEquivalent:"")
            item.submenu = menu; main.addItem(item); return menu
        }
        // TypingKeyGuard lets Command-A continue to select text in a field.
        if let selectAll = edit.items.first(where: { $0.keyEquivalent == "a" }) { edit.removeItem(selectAll) }
        add(edit,G("全选照片"),"a",enabled:{ pro() && s.canSelectAllFrames }) { s.selectAllFrames() }
        add(edit,G("同步所选参数"),enabled:{ pro() && s.canSyncSettings }) { self.store.sync() }
        view.addItem(.separator())
        add(view,G("放大"),"+",enabled:zoom) { s.zoomStep(1) }
        add(view,G("缩小"),"-",enabled:zoom) { s.zoomStep(-1) }
        add(view,G("适应窗口"),",",[],enabled:zoom) { if !SimpleCameraController.command("fit") { s.zoomToFit() } }
        add(view,"100%",".",[],enabled:zoom) { if !SimpleCameraController.command("actual") { s.zoomTo(fraction:1) } }
        view.addItem(.separator())
        add(view,G("显示／隐藏两侧面板"),"b",enabled:{ self.store.professional }) {
            withAnimation(.easeOut(duration:0.18)) {
                let visible = !(self.store.leftVisible || self.store.rightVisible)
                self.store.leftVisible = visible; self.store.rightVisible = visible
            }
        }
        add(view,G("显示／隐藏照片栏"),"f",[.command,.shift],enabled:{ self.store.professional }) {
            withAnimation(.easeOut(duration:0.18)) { s.filmstripCollapsed.toggle() }
        }
        add(view,G("启用／旁路成片调整"),"b",[.command,.shift],enabled:pro) { var a = s.adjustments; a.enabled.toggle(); s.adjustments = a }
        add(view,G("原图／成片对照"),"y",[],enabled:{ available() && s.canCompare }) {
            if !SimpleCameraController.command("compare") {
                self.store.proof = false; s.toggledOriginal(false); s.commitCrop(); s.comparing.toggle()
            }
        }
        add(view,G("重新连接照片处理服务"),"r",[.command,.option],enabled:available) { s.restartService() }
        let frame = section(G("照片"))
        add(frame,G("上一张"),String(UnicodeScalar(NSLeftArrowFunctionKey)!),[],enabled:pro) { self.store.step(-1) }
        add(frame,G("下一张"),String(UnicodeScalar(NSRightArrowFunctionKey)!),[],enabled:pro) { self.store.step(1) }
        add(frame,G("新建半格拼接"),"j",enabled:{ pro() && s.canMakePair }) { s.newPair(); self.store.leftVisible = true }
        frame.addItem(.separator())
        add(frame,G("重置胶片、相纸、输入与放大机"),enabled:pro) { s.resetParams() }
        add(frame,G("重置成片调整"),enabled:pro) { s.resetAdjustments() }
        add(frame,G("在访达显示照片参数"),enabled:available) {
            guard let url = s.selection else { return }; s.flushSave()
            let sidecar = Sidecar.url(for:url)
            if FileManager.default.fileExists(atPath:sidecar.path) { NSWorkspace.shared.activateFileViewerSelecting([sidecar]) }
            else { NSWorkspace.shared.open(Sidecar.storeDirectory) }
        }
        let crop = section(G("裁剪"))
        add(crop,G("向左旋转"),"[",[.command,.option],enabled:available) { if !SimpleCameraController.command("rotate-left") { s.geometry = s.geometry.turned(by:-1) } }
        add(crop,G("向右旋转"),"]",[.command,.option],enabled:available) { if !SimpleCameraController.command("rotate") { s.geometry = s.geometry.turned(by:1) } }
        add(crop,G("水平翻转"),enabled:pro) { var g = s.geometry; g.flipH.toggle(); s.geometry = g }
        add(crop,G("垂直翻转"),enabled:pro) { var g = s.geometry; g.flipV.toggle(); s.geometry = g }
        add(crop,G("重置裁剪与方向"),enabled:pro) { if let url = s.selection { self.store.reset(url,cropOnly:true) } }
        let tool = section(G("工具"))
        add(tool,G("选择"),"v",[],enabled:pro) { self.store.proof = false; s.tool = .select }
        add(tool,G("抓手"),"h",[],enabled:pro) { self.store.proof = false; s.tool = .hand }
        add(tool,G("裁剪"),"c",[],enabled:pro) {
            self.store.proof = false; s.comparing = false; s.toggledOriginal(false)
            if s.pair != nil { s.togglePairPlacing() } else { s.tool = .crop; self.store.rightVisible = true; UserDefaults.standard.set(true,forKey:Session.uiKey+"section.crop") }
        }
    }
}
