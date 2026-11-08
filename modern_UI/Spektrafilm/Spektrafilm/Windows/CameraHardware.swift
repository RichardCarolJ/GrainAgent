import AppKit

/// Native texture used by the simple workspace's window-ratio control.
@MainActor enum CameraHardware {
    static let images: [String: NSImage] = {
        guard let url = Bundle.main.url(forResource: "brushed-metal-v2", withExtension: "png", subdirectory: "Resources/Materials"),
              let image = NSImage(contentsOf: url) else { return [:] }
        return ["brushed-metal-v2": image]
    }()
}
