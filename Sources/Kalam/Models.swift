import SwiftUI

/// The line that separates sittings within one day ("--" then Return).
let ornamentMark = "⁂"
/// One "page" of writing, used for daily goals and the page counter.
let wordsPerPage = 250.0

struct Journal: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var icon: String = "book.closed"
    var dailyGoal: Int = 1
    var created = Date()

    init(name: String, icon: String = "book.closed", dailyGoal: Int = 1) {
        self.name = name; self.icon = icon; self.dailyGoal = dailyGoal
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Journal"
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? "book.closed"
        dailyGoal = min(5, max(1, try c.decodeIfPresent(Int.self, forKey: .dailyGoal) ?? 1))
        created = try c.decodeIfPresent(Date.self, forKey: .created) ?? Date()
    }
}

struct EntryVersion: Codable, Identifiable, Hashable {
    var id = UUID()
    var date = Date()
    var title: String
    var body: String
}

struct Entry: Codable, Identifiable, Hashable {
    var id = UUID()
    var journalID: UUID
    var day: String
    var title = ""
    var body = ""
    var mood: Int?
    var created = Date()
    var modified = Date()
    var versions: [EntryVersion] = []
    var promptSet: String?
    /// Section index (as text) -> indices of prompt questions ticked in that section.
    var checked: [String: [Int]] = [:]
    var writingSeconds: Double = 0

    init(journalID: UUID, day: String) {
        self.journalID = journalID; self.day = day
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        journalID = try c.decode(UUID.self, forKey: .journalID)
        day = try c.decode(String.self, forKey: .day)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        mood = try c.decodeIfPresent(Int.self, forKey: .mood)
        created = try c.decodeIfPresent(Date.self, forKey: .created) ?? Date()
        modified = try c.decodeIfPresent(Date.self, forKey: .modified) ?? created
        versions = try c.decodeIfPresent([EntryVersion].self, forKey: .versions) ?? []
        promptSet = try c.decodeIfPresent(String.self, forKey: .promptSet)
        checked = try c.decodeIfPresent([String: [Int]].self, forKey: .checked) ?? [:]
        writingSeconds = try c.decodeIfPresent(Double.self, forKey: .writingSeconds) ?? 0
    }

    var isBlank: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var stats: TextStats { TextStats(body) }
    var pages: Double { Double(stats.words) / wordsPerPage }

    /// The writing split into sittings by ornamentMark lines.
    var sections: [String] { Entry.sections(of: body) }

    static func sections(of body: String) -> [String] {
        var out: [String] = [""]
        for line in body.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces) == ornamentMark { out.append("") }
            else { out[out.count - 1] += (out[out.count - 1].isEmpty ? "" : "\n") + line }
        }
        return out
    }

    /// Title, or the first line of writing, for lists.
    var displayTitle: String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        let first = body.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && $0 != ornamentMark }
        return first.map { String($0) } ?? "Untitled"
    }
}

struct Library: Codable {
    var version = 1
    var journals: [Journal]
    var entries: [Entry]
    var customPrompts: [String] = []

    init(journals: [Journal], entries: [Entry], customPrompts: [String] = []) {
        self.journals = journals; self.entries = entries; self.customPrompts = customPrompts
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        journals = try c.decode([Journal].self, forKey: .journals)
        entries = try c.decodeIfPresent([Entry].self, forKey: .entries) ?? []
        customPrompts = try c.decodeIfPresent([String].self, forKey: .customPrompts) ?? []
    }
}

// MARK: - Days

/// Entries are keyed by "yyyy-MM-dd" in the Gregorian calendar, whatever the system calendar is.
enum Day {
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = Calendar.current.firstWeekday
        c.timeZone = .current
        c.locale = .current
        return c
    }

    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func key(_ date: Date) -> String { keyFormatter.string(from: date) }
    static func date(_ key: String) -> Date { keyFormatter.date(from: key) ?? Date() }
    static var today: String { key(Date()) }

    static func add(_ key: String, days: Int) -> String {
        Day.key(calendar.date(byAdding: .day, value: days, to: date(key)) ?? date(key))
    }

    static func format(_ key: String, _ template: String) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate(template)
        return f.string(from: date(key))
    }

    static func long(_ key: String) -> String { format(key, "EEEEdMMMMyyyy") }
    static func short(_ key: String) -> String { format(key, "EEEdMMM") }

    static func monthStart(_ date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    static func monthTitle(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.setLocalizedDateFormatFromTemplate("MMMMyyyy")
        return f.string(from: date)
    }

    /// Day keys for a month grid, padded with nils so the first day sits under its weekday.
    static func grid(for month: Date) -> [String?] {
        let cal = calendar
        let start = monthStart(month)
        let count = cal.range(of: .day, in: .month, for: start)?.count ?? 30
        let weekday = cal.component(.weekday, from: start)
        let lead = (weekday - cal.firstWeekday + 7) % 7
        var cells: [String?] = Array(repeating: nil, count: lead)
        for d in 0..<count {
            cells.append(key(cal.date(byAdding: .day, value: d, to: start)!))
        }
        return cells
    }

    static var weekdaySymbols: [String] {
        let cal = calendar
        let s = cal.veryShortStandaloneWeekdaySymbols
        let i = cal.firstWeekday - 1
        return Array(s[i...] + s[..<i])
    }

    static func dayNumber(_ key: String) -> String { String(Int(key.suffix(2)) ?? 0) }
}

// MARK: - Stats

struct TextStats {
    var words = 0
    var paragraphs = 0
    var characters = 0

    init(_ text: String) {
        var w = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in w += 1 }
        words = w
        paragraphs = text.split(whereSeparator: \.isNewline)
            .filter { let t = $0.trimmingCharacters(in: .whitespaces); return !t.isEmpty && t != ornamentMark }
            .count
        characters = text.filter { !$0.isWhitespace && String($0) != ornamentMark }.count
    }

    var pages: Double { Double(words) / wordsPerPage }
    var readingMinutes: Int { max(words > 0 ? 1 : 0, Int((Double(words) / 230).rounded(.up))) }
}

// MARK: - Mood

enum Mood: Int, CaseIterable, Identifiable {
    case awful = 1, low, okay, good, great
    var id: Int { rawValue }

    var name: String {
        switch self {
        case .awful: return "Awful"
        case .low: return "Low"
        case .okay: return "Okay"
        case .good: return "Good"
        case .great: return "Great"
        }
    }

    var symbol: String {
        switch self {
        case .awful: return "cloud.bolt.rain"
        case .low: return "cloud.drizzle"
        case .okay: return "cloud.sun"
        case .good: return "sun.max"
        case .great: return "sparkles"
        }
    }

    var color: Color {
        switch self {
        case .awful: return Color(hex: 0x7E6BAF)
        case .low: return Color(hex: 0x6C8EBF)
        case .okay: return Color(hex: 0x9C968C)
        case .good: return Color(hex: 0xD9A441)
        case .great: return Color(hex: 0xE07A4F)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}
