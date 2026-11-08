import Foundation
import CoreGraphics

/// Content sizes only. Frame decorations are converted once at the AppKit
/// boundary; an already-corrected frame must never become the next drag axis.
struct ProfessionalWindowBounds {
    static let designMinimum = CGSize(width: 1180, height: 780)
    static let preferred = CGSize(width: 1440, height: 1000)
    static let aspect: ClosedRange<CGFloat> = 1.25...1.9
    let minimum: CGSize
    let maximum: CGSize
    let defaultSize: CGSize

    init(available: CGSize) {
        maximum = CGSize(width: max(1, min(3000, available.width)),
                         height: max(1, min(2000, available.height)))
        // Match the accepted 16-inch occupancy (1440 × 1000 in 1728 × 1080)
        // on smaller and external screens, retaining the workbench aspect.
        let preferredScale = min(maximum.width / 1728, maximum.height / 1080)
        defaultSize = CGSize(width: floor(Self.preferred.width * preferredScale / 5) * 5,
                             height: floor(Self.preferred.height * preferredScale / 5) * 5)
        let scale = min(1, defaultSize.width / Self.designMinimum.width,
                        defaultSize.height / Self.designMinimum.height)
        minimum = CGSize(width: Self.designMinimum.width * scale,
                         height: Self.designMinimum.height * scale)
    }

    enum Axis { case width, height, both }

    func constrain(_ proposed: CGSize, axis: Axis = .both, fixed: CGSize? = nil) -> CGSize {
        let low = Self.aspect.lowerBound, high = Self.aspect.upperBound
        func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
            min(upper, max(lower, value))
        }
        if axis == .width, let fixed {
            let h = clamp(fixed.height, max(minimum.height, minimum.width / high),
                          min(maximum.height, maximum.width / low))
            return CGSize(width: clamp(proposed.width, max(minimum.width, h * low),
                                       min(maximum.width, h * high)), height: h)
        }
        if axis == .height, let fixed {
            let w = clamp(fixed.width, max(minimum.width, minimum.height * low),
                          min(maximum.width, maximum.height * high))
            return CGSize(width: w, height: clamp(proposed.height, max(minimum.height, w / high),
                                                 min(maximum.height, w / low)))
        }
        let w = clamp(proposed.width, minimum.width, maximum.width)
        let h = clamp(proposed.height, minimum.height, maximum.height)
        let ratio = w / h
        guard ratio < low || ratio > high else { return CGSize(width: w, height: h) }
        // Orthogonal projection onto the nearest allowed aspect boundary is
        // deterministic and idempotent, including a corner hitting two limits.
        let r = ratio < low ? low : high
        let projectedH = clamp((r * w + h) / (r * r + 1),
                               max(minimum.height, minimum.width / r),
                               min(maximum.height, maximum.width / r))
        return CGSize(width: r * projectedH, height: projectedH)
    }
}

/// Latch intent against the start of the gesture, never against its previous
/// constrained result. A corner may acquire a second axis, but never flip back.
struct ProfessionalResizeGesture {
    let bounds: ProfessionalWindowBounds
    let initial: CGSize
    private(set) var axis: ProfessionalWindowBounds.Axis?

    mutating func constrain(_ proposed: CGSize) -> CGSize {
        let dx = abs(proposed.width - initial.width)
        let dy = abs(proposed.height - initial.height)
        if axis == nil {
            if dx > 0.5 && dy > 0.5 { axis = .both }
            else if dx > 0.5 { axis = .width }
            else if dy > 0.5 { axis = .height }
        } else if (axis == .width && dy > 2) || (axis == .height && dx > 2) {
            axis = .both
        }
        return bounds.constrain(proposed, axis: axis ?? .both, fixed: initial)
    }
}
