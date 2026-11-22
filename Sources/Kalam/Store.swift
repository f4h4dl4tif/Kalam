import SwiftUI
import AppKit

/// Holds every journal and entry, saves them as JSON in Application Support, and tracks what is on screen.
final class Store: ObservableObject {
    static let shared = Store()

    @Published var library: Library
    @Published private(set) var journalID: UUID
    @Published private(set) var day: String = Day.today
    @Published var displayedMonth: Date = Day.monthStart(Date())

    // UI state that menu commands and toolbar buttons share.
    @Published var showInfo = false
    @Published var showHistory = false
    @Published var showPrompts = false
    @Published var editingJournal: Journal?
    @Published var focusToken = 0
    @Published var toast: String?

    let folder: URL
    private var fileURL: URL { folder.appendingPathComponent("library.json") }
    private var saveWork: DispatchWorkItem?

    // Editing session, used for version snapshots and writing time.
    private var sessionEntryID: UUID?
    private var lastSnapshot = Date.distantPast
    private var lastKeystroke: Date?

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        if let dir = ProcessInfo.processInfo.environment["KALAM_DATA_DIR"] {
            folder = URL(fileURLWithPath: dir, isDirectory: true)   // for testing with sample data
        } else {
            folder = base.appendingPathComponent("Kalam", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let url = folder.appendingPathComponent("library.json")
        var loaded: Library?
        if let data = try? Data(contentsOf: url) {
            loaded = try? Store.decoder.decode(Library.self, from: data)
            if loaded == nil {
                // Keep an unreadable file instead of overwriting it.
                let bad = folder.appendingPathComponent("library-unreadable-\(Int(Date().timeIntervalSince1970)).json")
                try? FileManager.default.copyItem(at: url, to: bad)
            }
        }
        if loaded == nil || loaded!.journals.isEmpty {
            loaded = Library(journals: [Journal(name: "Journal", icon: "book.closed", dailyGoal: 1)], entries: loaded?.entries ?? [])
        }
        let lib = loaded!
        let saved = UserDefaults.standard.string(forKey: "journalID").flatMap(UUID.init(uuidString:))
        _library = Published(initialValue: lib)
        _journalID = Published(initialValue: lib.journals.first { $0.id == saved }?.id ?? lib.journals[0].id)

        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            self?.saveNow()
        }
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: Saving

    func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    func saveNow() {
        saveWork?.cancel()
        saveWork = nil
        guard let data = try? Store.encoder.encode(library) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func flash(_ message: String) {
        toast = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
            if self?.toast == message { self?.toast = nil }
        }
    }

    // MARK: Lookup

    var journal: Journal { library.journals.first { $0.id == journalID } ?? library.journals[0] }

    func index(day: String, journal: UUID? = nil) -> Int? {
        let j = journal ?? journalID
        return library.entries.firstIndex { $0.journalID == j && $0.day == day }
    }

    var entry: Entry? { index(day: day).map { library.entries[$0] } }

    func entries(in journal: UUID? = nil) -> [Entry] {
        let j = journal ?? journalID
        return library.entries.filter { $0.journalID == j }
    }

    /// Entries for the current journal keyed by day, for quick calendar lookups.
    func entriesByDay(journal: UUID? = nil) -> [String: Entry] {
        var out: [String: Entry] = [:]
        for e in entries(in: journal) { out[e.day] = e }
        return out
    }

    func progress(of entry: Entry?, journal: Journal? = nil) -> Double {
        guard let entry else { return 0 }
        return entry.pages / Double((journal ?? self.journal).dailyGoal)
    }

    /// Average words across the journal's other written entries.
    func averageWords(excluding day: String? = nil) -> Int {
        let counts = entries().filter { $0.day != day }.map { $0.stats.words }.filter { $0 > 0 }
        guard !counts.isEmpty else { return 0 }
        return counts.reduce(0, +) / counts.count
    }

    // MARK: Navigation

    func select(day newDay: String) {
        endSession()
        day = newDay
        let month = Day.monthStart(Day.date(newDay))
        if month != displayedMonth { displayedMonth = month }
        focusToken += 1
    }

    func goToday() { select(day: Day.today) }
    func move(days n: Int) { select(day: Day.add(day, days: n)) }

    func moveMonth(_ n: Int) {
        displayedMonth = Day.calendar.date(byAdding: .month, value: n, to: displayedMonth) ?? displayedMonth
    }

    func selectJournal(_ id: UUID) {
        guard library.journals.contains(where: { $0.id == id }) else { return }
        endSession()
        journalID = id
        UserDefaults.standard.set(id.uuidString, forKey: "journalID")
        focusToken += 1
    }

    // MARK: Editing

    var bodyText: String { entry?.body ?? "" }
    var titleText: String { entry?.title ?? "" }

    func setBody(_ text: String) { edit { $0.body = text } }
    func setTitle(_ text: String) { edit { $0.title = text } }
    func setMood(_ mood: Mood?) { edit(trackTime: false) { $0.mood = mood?.rawValue } }

    func setPromptSet(_ id: String) { edit(trackTime: false) { $0.promptSet = id } }

    func toggleCheck(_ question: Int, section: Int) {
        edit(trackTime: false) {
            var list = $0.checked[String(section)] ?? []
            if let i = list.firstIndex(of: question) { list.remove(at: i) } else { list.append(question) }
            $0.checked[String(section)] = list
        }
    }

    func addChecks(_ questions: [Int], section: Int) {
        guard let e = entry else { return }
        let existing = Set(e.checked[String(section)] ?? [])
        let added = Set(questions).subtracting(existing)
        guard !added.isEmpty else { return }
        edit(trackTime: false) { $0.checked[String(section)] = Array(existing.union(added)).sorted() }
    }

    /// Starts a new sitting: an ornamentMark line at the end of today's writing.
    func newSection() {
        let trimmed = bodyText.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
        guard !trimmed.isEmpty, Entry.sections(of: trimmed).last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            focusToken += 1; return
        }
        setBody(trimmed + "\n" + ornamentMark + "\n")
        focusToken += 1
    }

    func insertQuestion(_ q: String) {
        let body = bodyText
        let sep = body.isEmpty ? "" : (body.hasSuffix("\n\n") ? "" : (body.hasSuffix("\n") ? "\n" : "\n\n"))
        setBody(body + sep + q + "\n")
        focusToken += 1
    }

    /// Adds a quick note from the menu bar to today's entry in the current journal.
    func appendToToday(_ text: String) {
        let note = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty else { return }
        edit(day: Day.today, trackTime: false) {
            $0.body = $0.body.isEmpty ? note : $0.body.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) + "\n\n" + note
        }
    }

    private func edit(day editDay: String? = nil, trackTime: Bool = true, _ change: (inout Entry) -> Void) {
        let d = editDay ?? day
        let i: Int
        if let found = index(day: d) { i = found } else {
            library.entries.append(Entry(journalID: journalID, day: d))
            i = library.entries.count - 1
        }
        if d == day { beginSession(i) }
        change(&library.entries[i])
        library.entries[i].modified = Date()

        if trackTime && d == day {
            let now = Date()
            if let last = lastKeystroke, now.timeIntervalSince(last) < 60 {
                library.entries[i].writingSeconds += now.timeIntervalSince(last)
            }
            lastKeystroke = now
            if now.timeIntervalSince(lastSnapshot) > 600 { snapshot(i) }
        }

        let e = library.entries[i]
        if e.isBlank && e.versions.isEmpty && e.mood == nil {
            library.entries.remove(at: i)
        }
        scheduleSave()
    }

    // MARK: Versions

    private func beginSession(_ i: Int) {
        guard sessionEntryID != library.entries[i].id else { return }
        sessionEntryID = library.entries[i].id
        snapshot(i)
    }

    private func endSession() {
        sessionEntryID = nil
        lastKeystroke = nil
    }

    /// Keeps the entry's current text as an earlier version, if it differs from the last one.
    private func snapshot(_ i: Int) {
        lastSnapshot = Date()
        let e = library.entries[i]
        guard !e.isBlank else { return }
        if let last = e.versions.last, last.body == e.body, last.title == e.title { return }
        library.entries[i].versions.append(EntryVersion(title: e.title, body: e.body))
        if library.entries[i].versions.count > 60 {
            library.entries[i].versions.removeFirst(library.entries[i].versions.count - 60)
        }
    }

    func restore(_ version: EntryVersion) {
        guard let i = index(day: day) else { return }
        snapshot(i)
        library.entries[i].title = version.title
        library.entries[i].body = version.body
        library.entries[i].modified = Date()
        sessionEntryID = library.entries[i].id
        scheduleSave()
        flash("Restored the version from \(version.date.formatted(date: .abbreviated, time: .shortened))")
    }

    // MARK: Journals

    func beginNewJournal() {
        editingJournal = Journal(name: "", icon: "book", dailyGoal: 1)
    }

    func saveJournal(_ j: Journal) {
        var j = j
        if j.name.trimmingCharacters(in: .whitespaces).isEmpty { j.name = "Untitled Journal" }
        if let i = library.journals.firstIndex(where: { $0.id == j.id }) {
            library.journals[i] = j
        } else {
            library.journals.append(j)
            selectJournal(j.id)
        }
        scheduleSave()
    }

    func deleteJournal(_ id: UUID) {
        guard library.journals.count > 1 else { return }
        library.journals.removeAll { $0.id == id }
        library.entries.removeAll { $0.journalID == id }
        if journalID == id { selectJournal(library.journals[0].id) }
        scheduleSave()
    }

    // MARK: Prompts

    var customPrompts: [String] {
        get { library.customPrompts }
        set { library.customPrompts = newValue; scheduleSave() }
    }

    // MARK: Import

    /// Merges an entry into a journal: new days are added, existing days get the text appended as a new section.
    @discardableResult
    func merge(day: String, title: String, body: String, mood: Int? = nil, into journal: UUID, created: Date? = nil) -> Bool {
        let body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty || !title.isEmpty else { return false }
        if let i = index(day: day, journal: journal) {
            let e = library.entries[i]
            if !body.isEmpty && e.body.contains(body) { return false }
            if e.title.isEmpty { library.entries[i].title = title }
            if !body.isEmpty {
                library.entries[i].body = e.body.isEmpty ? body : e.body + "\n" + ornamentMark + "\n" + body
            }
            if library.entries[i].mood == nil { library.entries[i].mood = mood }
            library.entries[i].modified = Date()
        } else {
            var e = Entry(journalID: journal, day: day)
            e.title = title; e.body = body; e.mood = mood
            if let created { e.created = created; e.modified = created }
            library.entries.append(e)
        }
        return true
    }

    /// Merges a whole Kalam backup, matching journals by id, then by name.
    func merge(library other: Library) -> Int {
        var map: [UUID: UUID] = [:]
        for j in other.journals {
            if library.journals.contains(where: { $0.id == j.id }) { map[j.id] = j.id }
            else if let same = library.journals.first(where: { $0.name.caseInsensitiveCompare(j.name) == .orderedSame }) { map[j.id] = same.id }
            else { library.journals.append(j); map[j.id] = j.id }
        }
        var count = 0
        for e in other.entries {
            guard let target = map[e.journalID] else { continue }
            if let i = library.entries.firstIndex(where: { $0.id == e.id }) {
                if e.modified > library.entries[i].modified { library.entries[i] = e; count += 1 }
            } else if index(day: e.day, journal: target) == nil {
                var copy = e; copy.journalID = target
                library.entries.append(copy); count += 1
            } else if merge(day: e.day, title: e.title, body: e.body, mood: e.mood, into: target) {
                count += 1
            }
        }
        for p in other.customPrompts where !library.customPrompts.contains(p) { library.customPrompts.append(p) }
        scheduleSave()
        return count
    }
}
