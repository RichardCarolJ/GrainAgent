#!/usr/bin/env swift
// Export the approved artwork into the legacy macOS icon canvas. macOS 15
// displays ICNS pixels as supplied; it does not add the newer system mask.
// The asset catalog and ICNS must therefore use the same padded, rounded art.
import AppKit
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let source = root.appendingPathComponent("modern_UI/Spektrafilm/Spektrafilm")
let catalog = source.appendingPathComponent("Assets.xcassets/GrainAgent.appiconset")
let icon = source.appendingPathComponent("Resources/GrainAgent.icns")
let master = root.appendingPathComponent("BuildSupport/IconSource/GrainAgent.png")
let variants: [(String, Int)] = [
    ("icon_16x16.png",16), ("icon_16x16@2x.png",32),
    ("icon_32x32.png",32), ("icon_32x32@2x.png",64),
    ("icon_128x128.png",128), ("icon_128x128@2x.png",256),
    ("icon_256x256.png",256), ("icon_256x256@2x.png",512),
    ("icon_512x512.png",512), ("icon_512x512@2x.png",1024)
]
func require(_ condition: Bool, _ message: String) {
    if !condition { fputs("Icon check: \(message)\n", stderr); exit(1) }
}
func readImage(_ url: URL) -> CGImage {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        fatalError("Cannot read \(url.path)")
    }
    return image
}
func context(_ size: Int) -> CGContext {
    CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
              bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue)!
}
func validate(_ image: CGImage, size: Int, label: String) {
    require(image.width == size && image.height == size, "Wrong size: \(label)")
    let ctx = context(size)
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    let bytes = ctx.data!.assumingMemoryBound(to: UInt8.self)
    func alpha(_ x: Int, _ y: Int) -> UInt8 { bytes[(y * size + x) * 4 + 3] }
    for i in 0..<size {
        require(alpha(i,0) == 0 && alpha(i,size-1) == 0
                && alpha(0,i) == 0 && alpha(size-1,i) == 0,
                "Missing transparent outer margin: \(label)")
    }
    let mid = size / 2
    let occupied = (0..<size).filter { alpha($0,mid) >= 128 }
    let fraction = Double(occupied.count) / Double(size)
    require((0.74...0.85).contains(fraction), "Wrong optical size: \(label)")
    let corner = Int(Double(size) * 0.11)
    require(alpha(corner,corner) < 10 && alpha(mid,mid) == 255,
            "Missing rounded mask or opaque centre: \(label)")
}

if !CommandLine.arguments.contains("--check") {
    let artwork = readImage(master)
    require(artwork.width == 1024 && artwork.height == 1024, "Master must be 1024 px")
    // An 824 px body on a 1024 px canvas gives the legacy Dock its optical
    // margin. Export from the unmasked master only, never from a prior export.
    let full = context(1024)
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let outline = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
    full.addPath(outline)
    full.clip()
    full.interpolationQuality = .high
    full.draw(artwork, in: body)
    let rendered = full.makeImage()!
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let iconset = temp.appendingPathComponent("GrainAgent.iconset")
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temp) }
    for (name,size) in variants {
        let ctx = context(size)
        ctx.interpolationQuality = .high
        ctx.draw(rendered, in: CGRect(x: 0, y: 0, width: size, height: size))
        let output = ctx.makeImage()!
        validate(output, size: size, label: name)
        let url = catalog.appendingPathComponent(name)
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, output, nil)
        require(CGImageDestinationFinalize(dest), "Cannot write \(name)")
        try FileManager.default.copyItem(at: url, to: iconset.appendingPathComponent(name))
    }
    let tool = Process()
    tool.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    tool.arguments = ["-c", "icns", iconset.path, "-o", icon.path]
    try tool.run(); tool.waitUntilExit()
    require(tool.terminationStatus == 0, "iconutil failed")
}
for (name,size) in variants {
    validate(readImage(catalog.appendingPathComponent(name)), size: size, label: name)
}
guard let packed = CGImageSourceCreateWithURL(icon as CFURL, nil) else { fatalError("Cannot read ICNS") }
var packedSizes = Set<Int>()
for i in 0..<CGImageSourceGetCount(packed) {
    let image = CGImageSourceCreateImageAtIndex(packed, i, nil)!
    packedSizes.insert(image.width)
    validate(image, size: image.width, label: "ICNS \(image.width)")
}
require(Set(variants.map(\.1)).isSubset(of: packedSizes), "Missing ICNS resolutions")
print("Icon verified: 10 catalog variants, ICNS 16–1024 px, transparent margins and rounded silhouette.")
