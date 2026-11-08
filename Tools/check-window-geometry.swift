import Foundation
import CoreGraphics

/// Narrow regression executable; no image loading, rendering, shared defaults,
/// or UI automation. Compile alongside Workspace/ProfessionalWindowGeometry.swift.
@main enum WindowGeometryChecks {
    static func main() {
        func close(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a-b) < 0.00001 }
        let bounds = ProfessionalWindowBounds(available: CGSize(width: 3000, height: 2000))
        var horizontal = ProfessionalResizeGesture(bounds: bounds, initial: CGSize(width: 1300, height: 1000))
        let request = CGSize(width: 1180, height: 1000)
        let first = horizontal.constrain(request)
        precondition(first == CGSize(width: 1250, height: 1000), "A side drag must stop at the aspect boundary without moving the other edge")
        for _ in 0..<100 { precondition(horizontal.constrain(request) == first, "Repeated boundary requests must not alternate") }
        var vertical = ProfessionalResizeGesture(bounds: bounds, initial: CGSize(width: 1800, height: 1000))
        let wide = vertical.constrain(CGSize(width: 1800, height: 780))
        precondition(close(wide.width, 1800) && close(wide.width/wide.height, 1.9))
        for _ in 0..<100 { precondition(vertical.constrain(CGSize(width: 1800, height: 780)) == wide) }
        // A side-to-corner gesture may gain an axis, but never switch back and
        // reinterpret a correction as fresh pointer intent.
        _ = horizontal.constrain(CGSize(width: 1180, height: 1050))
        precondition(horizontal.axis == .both)
        _ = horizontal.constrain(request)
        precondition(horizontal.axis == .both)
        let screens = [CGSize(width: 3000, height: 2000), CGSize(width: 1410, height: 980),
                       CGSize(width: 1280, height: 720), CGSize(width: 1024, height: 700),
                       CGSize(width: 800, height: 600)]
        var cases = 0
        for screen in screens {
            let b = ProfessionalWindowBounds(available: screen)
            for w in stride(from: 100, through: 3600, by: 70) {
                for h in stride(from: 100, through: 2400, by: 65) {
                    let s = b.constrain(CGSize(width: CGFloat(w), height: CGFloat(h)))
                    let ratio = s.width/s.height
                    precondition(ratio >= 1.25-0.00001 && ratio <= 1.9+0.00001)
                    precondition(s.width >= b.minimum.width-0.00001 && s.height >= b.minimum.height-0.00001)
                    precondition(s.width <= b.maximum.width+0.00001 && s.height <= b.maximum.height+0.00001)
                    let twice = b.constrain(s)
                    precondition(close(s.width,twice.width) && close(s.height,twice.height), "Restoring a legal frame must be a no-op")
                    cases += 1
                }
            }
        }
        print("PASS: stable edge/corner gestures and \(cases) size-boundary/idempotence cases across five screen bounds")
    }
}
