import AppKit
import UniformTypeIdentifiers

@MainActor final class GrainImport: NSObject {
    let panel = NSOpenPanel()
    let formats = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 28))
    static func open(_ session: Session) {
        guard !session.batchExporting else { return }
        let urls = chooseFilesOrFolder()
        if !urls.isEmpty { session.open(urls: urls) }
    }
    static func chooseFilesOrFolder() -> [URL] {
        let picker = GrainImport()
        picker.panel.canChooseFiles = true; picker.panel.canChooseDirectories = true
        picker.panel.allowsMultipleSelection = true
        picker.panel.message = G("装入照片；需要 RAW、TIFF 等格式时切换为全部格式。")
        picker.formats.addItems(withTitles: [G("JPEG 优先"), G("全部支持的输入格式")])
        picker.formats.target = picker; picker.formats.action = #selector(picker.changed)
        picker.panel.accessoryView = picker.formats; picker.changed()
        return picker.panel.runModal() == .OK ? picker.panel.urls : []
    }
    @objc private func changed() {
        panel.allowedContentTypes = formats.indexOfSelectedItem == 0 ? [.jpeg, .folder] :
            [.folder] + ImageDecoder.openable.compactMap { UTType(filenameExtension: $0) }
    }
}
