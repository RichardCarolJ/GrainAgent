import SwiftUI
import AppKit
struct ProPhotoContextMenu: View {
    @Bindable var store: WorkspaceStore
    let url:URL
    var body: some View {
        Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { Label(G("在访达中显示"),systemImage:"folder") }
        Divider()
        Button(G("复制此照片参数")) { store.copy(url) }.disabled(store.session.clipboardGroups.isEmpty)
        Button(G("粘贴参数到\(store.contextTargets(url).count)张")) { store.paste(store.contextTargets(url)) }.disabled(store.session.clipboard == nil)
        Button(G("同步此照片参数到其他所选照片")) { store.sync(url,to:store.contextTargets(url)) }.disabled(store.contextTargets(url).count < 2 || store.session.clipboardGroups.isEmpty)
        Menu(G("复制／同步参数范围")) {
            ForEach(ClipboardGroup.offered) { group in Toggle(group.title,isOn:Binding(get:{ store.session.clipboardGroups.contains(group) },set:{ if $0 { store.session.clipboardGroups.insert(group) } else { store.session.clipboardGroups.remove(group) } })) }
        }
        Divider()
        Button(G("新建半格拼接")) {
            if !store.session.isPicked(url) { store.session.click(url) }
            store.session.newPair(); store.leftVisible = true
        }.disabled(!store.session.canMakePair)
        if HalfFramePair.isPair(url) { Button(G("删除半格拼接文件")) { store.session.deletePair(url) } }
        Divider()
        Button(G("重置此照片裁剪与方向")) { store.reset(url,cropOnly:true) }
        Button(G("恢复此照片默认参数")) { store.reset(url) }
        Divider()
        Button(G(store.contextTargets(url).count > 1 ? "输出所选照片…" : "输出此照片…")) { store.showOutput(url) }
        Button(G("从批次移除\(store.contextTargets(url).count)张照片")) { store.remove(store.contextTargets(url)) }
    }
}
