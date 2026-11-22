import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var store: Store
    @AppStorage(Pref.sidebarMode) private var mode = "calendar"
    @State private var search = ""

    var body: some View {
        ThemeReader { palette in
            VStack(spacing: 0) {
                JournalSwitcher().padding(.horizontal, 12).padding(.top, 8)

                Picker("View", selection: $mode) {
                    Label("Calendar", systemImage: "calendar").tag("calendar")
                    Label("List", systemImage: "list.bullet").tag("list")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 12)
                .padding(.top, 10)

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search all journals", text: $search).textFieldStyle(.plain)
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 12))
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06)))
                .padding(.horizontal, 12).padding(.vertical, 10)

                if !search.trimmingCharacters(in: .whitespaces).isEmpty {
                    SearchResults(query: search, palette: palette)
                } else if mode == "calendar" {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            MonthHeader()
                            CalendarGrid(palette: palette)
                            MonthSummary(palette: palette)
                            OnThisDay(palette: palette)
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 16)
                    }
                } else {
                    MonthHeader().padding(.horizontal, 14)
                    EntryList(palette: palette)
                }
            }
        }
    }
}

struct JournalSwitcher: View {
    @EnvironmentObject var store: Store

    var body: some View {
        HStack {
            Menu {
                ForEach(store.library.journals) { j in
                    Button { store.selectJournal(j.id) } label: {
                        Label(j.name, systemImage: j.id == store.journal.id ? "checkmark" : j.icon)
                    }
                }
                Divider()
                Button("New Journal…") { store.beginNewJournal() }
                Button("Edit “\(store.journal.name)”…") { store.editingJournal = store.journal }
            } label: {
                Label(store.journal.name, systemImage: store.journal.icon)
                    .font(.system(size: 13, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            Spacer()
            Button { store.editingJournal = store.journal } label: { Image(systemName: "slider.horizontal.3") }
                .buttonStyle(.borderless)
                .help("Journal name, icon and daily goal")
        }
    }
}

struct MonthHeader: View {
    @EnvironmentObject var store: Store

    var body: some View {
        HStack {
            Text(Day.monthTitle(store.displayedMonth))
                .font(.system(size: 15, weight: .semibold, design: .serif))
            Spacer()
            Button { store.moveMonth(-1) } label: { Image(systemName: "chevron.left") }
                .help("Previous month (⌥⌘[)")
            Button { store.goToday() } label: { Text("Today").font(.system(size: 11)) }
            Button { store.moveMonth(1) } label: { Image(systemName: "chevron.right") }
                .help("Next month (⌥⌘])")
        }
        .buttonStyle(.borderless)
    }
}

struct CalendarGrid: View {
    @EnvironmentObject var store: Store
    let palette: Palette

    var body: some View {
        let byDay = store.entriesByDay()
        let journal = store.journal
        let cells = Day.grid(for: store.displayedMonth)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(Day.weekdaySymbols.enumerated()), id: \.offset) { _, s in
                Text(s).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            }
            ForEach(Array(cells.enumerated()), id: \.offset) { _, key in
                if let key {
                    DayCell(key: key, entry: byDay[key], progress: store.progress(of: byDay[key], journal: journal),
                            selected: key == store.day, palette: palette)
                        .onTapGesture { store.select(day: key) }
                } else {
                    Color.clear.frame(height: 34)
                }
            }
        }
    }
}

struct DayCell: View {
    let key: String
    let entry: Entry?
    let progress: Double
    let selected: Bool
    let palette: Palette

    var level: Double {
        guard let entry, !entry.isBlank else { return 0 }
        switch progress {
        case ..<0.25: return 0.16
        case ..<0.5: return 0.34
        case ..<1: return 0.6
        default: return 1
        }
    }

    var body: some View {
        let isToday = key == Day.today
        let future = key > Day.today
        VStack(spacing: 2) {
            ZStack {
                Circle().fill(palette.tint.opacity(level))
                if selected { Circle().stroke(palette.tint, lineWidth: 1.6).padding(-2) }
                Text(Day.dayNumber(key))
                    .font(.system(size: 12, weight: isToday ? .bold : .regular).monospacedDigit())
                    .foregroundStyle(level >= 0.6 ? Color.white : (future ? Color.secondary.opacity(0.5) : (isToday ? palette.tint : Color.primary)))
            }
            .frame(width: 26, height: 26)
            Circle()
                .fill(entry?.mood.flatMap(Mood.init(rawValue:))?.color ?? .clear)
                .frame(width: 4, height: 4)
        }
        .frame(height: 34)
        .contentShape(Rectangle())
        .help(entry.map { "\($0.displayTitle) · \($0.stats.words) words" } ?? Day.long(key))
    }
}

struct MonthSummary: View {
    @EnvironmentObject var store: Store
    let palette: Palette

    var body: some View {
        let prefix = String(Day.key(store.displayedMonth).prefix(7))
        let month = store.entries().filter { $0.day.hasPrefix(prefix) && !$0.isBlank }
        let words = month.reduce(0) { $0 + $1.stats.words }
        let met = month.filter { store.progress(of: $0) >= 1 }.count

        HStack(spacing: 0) {
            stat("\(month.count)", month.count == 1 ? "day" : "days")
            Divider().frame(height: 26)
            stat(words.formatted(), "words")
            Divider().frame(height: 26)
            stat("\(met)", "goals met")
        }
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.system(size: 14, weight: .semibold, design: .serif)).monospacedDigit()
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Entries written on this day in earlier years, in any journal.
struct OnThisDay: View {
    @EnvironmentObject var store: Store
    let palette: Palette

    var body: some View {
        let md = String(store.day.suffix(5))
        let year = Int(store.day.prefix(4)) ?? 0
        let past = store.library.entries
            .filter { $0.day.hasSuffix(md) && $0.day < store.day && !$0.isBlank }
            .sorted { $0.day > $1.day }

        if !past.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("On this day", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                ForEach(past.prefix(5)) { e in
                    let ago = year - (Int(e.day.prefix(4)) ?? year)
                    Button {
                        store.selectJournal(e.journalID)
                        store.select(day: e.day)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ago == 1 ? "A year ago" : "\(ago) years ago")
                                .font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.tint)
                            Text(e.displayTitle).font(.system(size: 13, design: .serif)).lineLimit(1)
                            Text(snippet(e.body)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 9).fill(palette.tint.opacity(0.07)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func snippet(_ body: String) -> String {
        body.replacingOccurrences(of: ornamentMark, with: " ").split(whereSeparator: \.isNewline).joined(separator: " ")
    }
}

struct EntryList: View {
    @EnvironmentObject var store: Store
    let palette: Palette

    var body: some View {
        let prefix = String(Day.key(store.displayedMonth).prefix(7))
        let month = store.entries().filter { $0.day.hasPrefix(prefix) && !$0.isBlank }.sorted { $0.day > $1.day }

        List(selection: Binding<String?>(get: { store.day }, set: { if let d = $0 { store.select(day: d) } })) {
            if month.isEmpty {
                Text("No entries this month").foregroundStyle(.secondary)
            }
            ForEach(month) { e in
                HStack(alignment: .top, spacing: 10) {
                    VStack(spacing: 0) {
                        Text(Day.dayNumber(e.day)).font(.system(size: 17, weight: .semibold, design: .serif))
                        Text(Day.format(e.day, "EEE")).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                    }
                    .frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.displayTitle).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        HStack(spacing: 6) {
                            Text("\(e.stats.words) words")
                            if let mood = e.mood.flatMap(Mood.init(rawValue:)) {
                                Image(systemName: mood.symbol).foregroundStyle(mood.color)
                            }
                        }
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 3)
                .tag(e.day)
            }
        }
        .listStyle(.sidebar)
    }
}

struct SearchResults: View {
    @EnvironmentObject var store: Store
    let query: String
    let palette: Palette

    var body: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        let hits = store.library.entries
            .filter { $0.title.localizedCaseInsensitiveContains(q) || $0.body.localizedCaseInsensitiveContains(q) }
            .sorted { $0.day > $1.day }

        List {
            Text("\(hits.count) \(hits.count == 1 ? "entry" : "entries")").font(.caption).foregroundStyle(.secondary)
            ForEach(hits.prefix(200)) { e in
                let journal = store.library.journals.first { $0.id == e.journalID }
                Button {
                    store.selectJournal(e.journalID)
                    store.select(day: e.day)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Image(systemName: journal?.icon ?? "book").foregroundStyle(palette.tint)
                            Text(Day.short(e.day)).font(.system(size: 11, weight: .semibold))
                            Text(e.displayTitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Text(highlighted(snippet(e, q), q)).font(.system(size: 12)).lineLimit(3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 2)
            }
        }
        .listStyle(.sidebar)
    }

    private func snippet(_ e: Entry, _ q: String) -> String {
        let flat = e.body.replacingOccurrences(of: ornamentMark, with: " ").split(whereSeparator: \.isNewline).joined(separator: " ")
        guard let r = flat.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) else { return String(flat.prefix(140)) }
        let start = flat.index(r.lowerBound, offsetBy: -50, limitedBy: flat.startIndex) ?? flat.startIndex
        let end = flat.index(r.upperBound, offsetBy: 90, limitedBy: flat.endIndex) ?? flat.endIndex
        return (start > flat.startIndex ? "…" : "") + flat[start..<end] + (end < flat.endIndex ? "…" : "")
    }

    private func highlighted(_ text: String, _ q: String) -> AttributedString {
        var a = AttributedString(text)
        var searchStart = a.startIndex
        while searchStart < a.endIndex,
              let r = a[searchStart...].range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) {
            a[r].inlinePresentationIntent = .stronglyEmphasized
            a[r].foregroundColor = palette.tint
            searchStart = r.upperBound
        }
        return a
    }
}
