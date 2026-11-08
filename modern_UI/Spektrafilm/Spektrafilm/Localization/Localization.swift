// Shared native/WebKit localization. Resources/Localization/Interface.json
// supplies presentation copy; the observable choice updates existing views
// without rebuilding the workspace, resetting edits or restarting the app.

import Foundation
import Observation

/// A language this app has copy for.
///
/// Four supported languages. Traditional Chinese is not silently mapped to Simplified.
/// See `Localization.resolve` for what happens to a traditional-Chinese reader.
enum Language: String, CaseIterable, Sendable {
    case english
    case simplifiedChinese
    case french
    case spanish

    var localeIdentifier: String {
        switch self {
        case .english: "en"
        case .simplifiedChinese: "zh-Hans"
        case .french: "fr"
        case .spanish: "es"
        }
    }
}

/// What the Settings menu offers: four languages, plus "whatever the system
/// says" — which is the default, and which is not the same thing as English.
enum LanguageSetting: String, CaseIterable, Sendable {
    case system, english, simplifiedChinese, french, spanish

    /// The menu's own label.
    ///
    /// `.english` and `.simplifiedChinese` are written **in their own
    /// language** and never in the active one. A language menu is the one menu
    /// a user reaches for *because* the current language is wrong, so
    /// "Simplified Chinese" rendered in a language its reader cannot read is
    /// the one label guaranteed not to help. Only `.system` follows the active
    /// language, because it has no language of its own to be written in.
    ///
    /// The active language is passed in rather than read from
    /// `Localization.shared` here. `PillMenu` takes a plain `(T) -> String`, so
    /// a closure that touched main-actor state could not be built inside a
    /// view's body without a concurrency error; taking the value as an
    /// argument keeps this a pure function of its inputs, which is also what
    /// makes it checkable without a running app.
    /// The fixed names are literals here rather than table entries: they
    /// are the *names of languages*, and the table's job is copy that changes
    /// meaning under translation. `.system` has no such name of its own, so it
    /// is the one that lives in the table and follows the active language.
    nonisolated func label(in active: Language) -> String {
        switch self {
        case .system:
            switch active {
            case .english: return "Follow System"
            case .simplifiedChinese: return "跟随系统"
            case .french: return "Suivre le système"
            case .spanish: return "Seguir el sistema"
            }
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        case .french: return "Français"
        case .spanish: return "Español"
        }
    }
}

/// The language setting, and the observable every localized string reads.
///
/// `@Observable` rather than a plain singleton, and that is load-bearing
/// rather than stylistic: `L(_:)` reads `resolved` from this object inside a
/// view's body, so SwiftUI records the dependency and a change to `language`
/// repaints every view that draws a string. A plain `static var` would compile,
/// would look right, and would leave every label in the window in the old
/// language until something else happened to invalidate it.
@MainActor
@Observable
final class Localization {
    static let shared = Localization()

    /// What the user picked. Persisted under `ui2.language` — the same `ui2.`
    /// namespace as the rest of this window's state (`Session.uiKey`), so it
    /// travels with the other interface settings rather than starting a
    /// second, parallel convention.
    ///
    /// Assigning it does not touch any view: the views read `resolved` during
    /// their own body, and `@Observable` tells them to re-run.
    var language: LanguageSetting {
        didSet {
            guard language != oldValue else { return }
            defaults.set(language.rawValue, forKey: Keys.language)
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
    }

    /// The language copy is actually drawn in.
    ///
    /// Computed, not stored: it is a function of the setting and the system,
    /// and a stored copy would be a second source of truth for a question that
    /// already has one. It reads `self.language`, which is what registers the
    /// `@Observable` dependency — a stored property would work too, but this
    /// keeps the derivation in one place.
    var resolved: Language {
        switch language {
        case .english: return .english
        case .simplifiedChinese: return .simplifiedChinese
        case .french: return .french
        case .spanish: return .spanish
        case .system: return Self.resolve(Self.systemPreferredLanguages)
        }
    }

    /// The user's preferred languages, read **once**.
    ///
    /// `Locale.preferredLanguages` is a preferences read, not a constant, and
    /// `resolved` is on the path of every text view in the editor — a drag
    /// re-evaluates a rail sixty times a second, and each pass would pay for
    /// the same answer. `static let` is initialized once, lazily. The cost is
    /// that a system language change mid-session is not followed; on macOS it
    /// is not followed by anything else either, and the setting is re-read on
    /// the next launch.
    ///
    /// Resolve the explicit preference order; this also permits a manual
    /// in-app choice independent of macOS per-application language settings.
    private static let systemPreferredLanguages = Locale.preferredLanguages
    static let didChange = Notification.Name("GrainAgent.languageDidChange")

    private let defaults: UserDefaults

    private enum Keys {
        static let language = Session.uiKey + "language"
    }

    /// `defaults` is injectable for the same reason `Diagnostics`' is: a test
    /// can write a setting and read back what the app would do with it without
    /// disturbing the real one.
    init(defaults: UserDefaults = .standard) {
        // `defaults` is assigned before `language` because the `didSet` above
        // may run during this call — `@Observable` rewrites the stored
        // property into a computed one, and the compiler's "observers do not
        // run during initialization" rule does not survive that rewriting.
        // (The same rewriting is why a `didSet` that assigns to *itself*
        // recurses; this one writes to `defaults` and to nothing else.)
        self.defaults = defaults
        let stored = defaults.string(forKey: Keys.language)
            .flatMap(LanguageSetting.init(rawValue:)) ?? .system
        language = stored
    }

    // MARK: - resolution

    /// Match the primary system language only. An unsupported primary language
    /// falls back to English, even when another supported language appears
    /// later in the preference list. Manual selection bypasses this resolver.
    nonisolated static func resolve(_ preferred: [String]) -> Language {
        preferred.first.flatMap(match) ?? .english
    }

    /// One tag, or `nil` when it names a language this app has no copy for.
    private nonisolated static func match(_ tag: String) -> Language? {
        let parts = tag.lowercased()
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .map(String.init)
        guard let primary = parts.first else { return nil }
        switch primary {
        case "en":
            return .english
        case "fr":
            return .french
        case "es":
            return .spanish
        case "zh":
            // Script beats region when both are present: `zh-Hans-TW` is
            // Simplified and `zh-Hant-CN` is not ours.
            if parts.contains("hant") { return nil }
            if parts.contains("hans") { return .simplifiedChinese }
            // No script given, so the region decides — and only the regions
            // that are Simplified by default are claimed. `zh-TW`, `zh-HK` and
            // `zh-MO` are traditional and fall through unmatched, which is
            // what sends them to English.
            if parts.contains("tw") || parts.contains("hk") || parts.contains("mo") { return nil }
            // Bare `zh` and the remaining regions: Simplified. macOS writes a
            // bare `zh` when the script is unstated, and Simplified is the
            // majority reading of an unstated `zh`.
            return .simplifiedChinese
        default:
            return nil
        }
    }
}
