import Foundation

/// Calendar validation shared by capture metadata, both date editors and export.
/// UI display order never changes this ISO storage representation.
struct PhotoCalendarDay: Equatable, Sendable {
    let year: Int, month: Int, day: Int
    static let years = 1900...4012
    init?(year: Int, month: Int, day: Int) {
        guard Self.years.contains(year), (1...12).contains(month) else { return nil }
        let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard (1...days[month-1]).contains(day) else { return nil }
        self.year = year; self.month = month; self.day = day
    }
    init?(_ iso: String) {
        let pieces = iso.split(separator: "-", omittingEmptySubsequences: false)
        guard pieces.count == 3, pieces[0].count == 4, pieces[1].count == 2, pieces[2].count == 2,
              let y = Int(pieces[0]), let m = Int(pieces[1]), let d = Int(pieces[2]) else { return nil }
        self.init(year: y, month: m, day: d)
    }
    var iso: String { String(format: "%04d-%02d-%02d", year, month, day) }
}
