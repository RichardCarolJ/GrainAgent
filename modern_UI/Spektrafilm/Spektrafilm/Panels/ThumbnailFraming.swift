import CoreGraphics

/// Shared crop/rotation geometry for navigation and masked thumbnails.
enum ThumbnailFraming {
    static func frame(_ image: CGImage, by geometry: Geometry) -> CGImage? {
        guard !geometry.isIdentity else { return image }
        let source = CGSize(width: image.width, height: image.height)
        let out = geometry.outputSize(for: source)
        let w = Int(out.width), h = Int(out.height)
        let space = image.colorSpace ?? ImageDecoder.displayP3
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
                ?? CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                             bytesPerRow: 0, space: ImageDecoder.displayP3,
                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return image }
        ctx.interpolationQuality = .high
        // Innermost last: Core Graphics' bottom-left image placement → the
        // source's top-left pixels → the output's top-left pixels → the
        // context's bottom-left device space.
        ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
        ctx.concatenate(geometry.outputToSourceTransform(imageSize: source).inverted())
        ctx.translateBy(x: 0, y: source.height); ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(origin: .zero, size: source))
        return ctx.makeImage()
    }
}
