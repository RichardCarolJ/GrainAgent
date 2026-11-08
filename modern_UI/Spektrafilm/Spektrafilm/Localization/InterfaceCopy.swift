import Foundation

/// Shared by SwiftUI, AppKit and the camera's WebKit surface. Only presentation
/// strings pass through this table: profile IDs, filenames, settings and sidecars
/// never do. Exact messages and anchored numbered templates avoid word replacement.
enum InterfaceCopy {
    static let entries: [String: [String: String]] = {
        guard let url = Bundle.main.url(forResource: "Interface", withExtension: "json", subdirectory: "Resources/Localization"),
              let data = try? Data(contentsOf: url),
              let table = try? JSONDecoder().decode([String: [String: String]].self, from: data) else { return [:] }
        return table
    }()
    private struct Template {
        let key: String
        let expression: NSRegularExpression
        let indices: [String]
    }
    private static let templates: [Template] = entries.keys.filter { $0.contains("{0}") }.sorted {
        // Specific wording must beat a longer generic "{0}: {1}" template.
        let left = $0.replacingOccurrences(of: #"\{\d+\}"#, with: "", options: .regularExpression).count
        let right = $1.replacingOccurrences(of: #"\{\d+\}"#, with: "", options: .regularExpression).count
        return left == right ? $0 < $1 : left > right
    }.compactMap { key in
        let marker = try! NSRegularExpression(pattern: #"\{(\d+)\}"#)
        let ns = key as NSString
        var pattern = "\\A", cursor = 0, indices: [String] = []
        for match in marker.matches(in: key, range: NSRange(location: 0, length: ns.length)) {
            pattern += NSRegularExpression.escapedPattern(for: ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            pattern += "([\\s\\S]*?)"
            indices.append(ns.substring(with: match.range(at: 1)))
            cursor = NSMaxRange(match.range)
        }
        pattern += NSRegularExpression.escapedPattern(for: ns.substring(from: cursor)) + "\\z"
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        return Template(key: key, expression: expression, indices: indices)
    }
    static func translate(_ source: String, english: String? = nil, language: Language) -> String {
        if language == .simplifiedChinese { return source.isEmpty ? english ?? source : source }
        let code = language.localeIdentifier
        // Identical Chinese labels can describe different actions (Copy vs Duplicate).
        // Existing native strings carry English context; preserve that distinction.
        if let english, let row = entries[source + "␟" + english] {
            return row[code] ?? row["en"] ?? english
        }
        if let row = entries[source] { return row[code] ?? row["en"] ?? english ?? source }
        for template in templates {
            let ns = source as NSString
            guard let match = template.expression.firstMatch(in: source, range: NSRange(location: 0, length: ns.length)),
                  let row = entries[template.key], let translation = row[code] ?? row["en"] else { continue }
            var arguments: [String: String] = [:]
            for (index, key) in template.indices.enumerated() { arguments[key] = ns.substring(with: match.range(at: index + 1)) }
            // Replace markers in one pass: a filename containing "{1}" stays intact.
            let marker = try! NSRegularExpression(pattern: #"\{(\d+)\}"#)
            let text = translation as NSString
            var result = "", cursor = 0
            for item in marker.matches(in: translation, range: NSRange(location: 0, length: text.length)) {
                result += text.substring(with: NSRange(location: cursor, length: item.range.location - cursor))
                result += arguments[text.substring(with: item.range(at: 1))] ?? text.substring(with: item.range)
                cursor = NSMaxRange(item.range)
            }
            return result + text.substring(from: cursor)
        }
        return english ?? source
    }
}

@MainActor func G(_ source: String) -> String {
    InterfaceCopy.translate(source, language: Localization.shared.resolved)
}
