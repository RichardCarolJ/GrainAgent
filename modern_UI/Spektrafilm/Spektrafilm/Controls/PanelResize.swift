// Shared panel width values and persisted layout compatibility.

import SwiftUI

/// What a panel may be, in points.
///
/// `standard` is the drawing's own width and is what a fresh install gets;
/// the bounds are how far the user may take it. A range whose bounds do not
/// contain its standard is a programming error rather than a preference, so
/// it is clamped here rather than discovered later as a panel that snaps on
/// first launch.
struct PanelWidthRange: Equatable, Sendable {
    let narrowest: CGFloat
    let standard: CGFloat
    let widest: CGFloat

    init(narrowest: CGFloat, standard: CGFloat, widest: CGFloat) {
        self.narrowest = min(narrowest, widest)
        self.widest = max(narrowest, widest)
        self.standard = min(max(standard, self.narrowest), self.widest)
    }

    func clamp(_ w: CGFloat) -> CGFloat { min(max(w, narrowest), widest) }

    /// True when the width is at a bound — what a handle uses to stop drawing
    /// as if there were more room in that direction.
    func atNarrowest(_ w: CGFloat) -> Bool { w <= narrowest + 0.5 }
    func atWidest(_ w: CGFloat) -> Bool { w >= widest - 0.5 }
}

/// A panel width that survives a relaunch.
///
/// Keys are namespaced the way `Session`'s UI state is, and for the same
/// reason recorded there: an earlier build of this app shipped under the same
/// bundle identifier and left its own keys behind.
@MainActor
@Observable
final class PanelWidthStore {
    let range: PanelWidthRange
    private let key: String
    /// The suite this store reads **and writes**.
    ///
    /// Held rather than used once: the first version took `defaults` in the
    /// initialiser, read through it, and then wrote through
    /// `UserDefaults.standard` — so the injection was a read-side seam only,
    /// and a test that passed a suite to stay off the user's own preferences
    /// wrote to them anyway. Found by a test of 5f's that failed for the right
    /// reason; the point of the parameter is that both halves honour it.
    private let defaults: UserDefaults

    var width: CGFloat {
        didSet {
            let clamped = range.clamp(width)
            if clamped != width { width = clamped; return }
            defaults.set(Double(width), forKey: key)
        }
    }

    /// `name` is the panel, e.g. "editor.left". A stored value outside the
    /// range — because the range was tightened in a later build — is clamped
    /// on read rather than honoured, so a bound is always a bound.
    static let keyPrefix = "ui.panelWidth."

    init(name: String, range: PanelWidthRange, defaults: UserDefaults = .standard) {
        self.range = range
        self.key = Self.keyPrefix + name
        self.defaults = defaults
        let stored = defaults.object(forKey: key) as? Double
        self.width = range.clamp(stored.map { CGFloat($0) } ?? range.standard)
        // Settings ▸ Reset All Layout. The key is already gone; this puts the
        // live width back without writing it (the drawing's width is the
        // default, and a stored default would outlive the next redraw of it).
        NotificationCenter.default.addObserver(forName: .layoutReset, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.width = self.range.standard
                self.defaults.removeObject(forKey: self.key)
            }
        }
    }
}
