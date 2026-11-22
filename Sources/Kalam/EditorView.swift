import SwiftUI

struct EditorView: View {
    @EnvironmentObject var store: Store
    @AppStorage(Pref.font) private var fontName = EditorFont.newYork.rawValue
    @AppStorage(Pref.fontSize) private var fontSize = 18.0
    @AppStorage(Pref.lineHeight) private var lineHeight = 1.55
    @AppStorage(Pref.columnWidth) private var columnWidth = 660.0
    @AppStorage(Pref.typewriter) private var typewriter = false

    var body: some View {
        ThemeReader { palette in
            content(palette)
        }
    }

    private func content(_ palette: Palette) -> some View {
        let font = (EditorFont(rawValue: fontName) ?? .newYork)
        let entry = store.entry
        let isToday = store.day == Day.today

        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(Day.long(store.day).uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(isToday ? palette.tint : palette.muted)
                    if let mood = entry?.mood.flatMap(Mood.init(rawValue:)) {
                        Image(systemName: mood.symbol).font(.system(size: 11)).foregroundStyle(mood.color)
                            .help(mood.name)
                    }
                }
                TextField("Title", text: Binding(get: { store.titleText }, set: { store.setTitle($0) }))
                    .textFieldStyle(.plain)
                    .font(font.font(CGFloat(fontSize) * 1.45).weight(.semibold))
                    .foregroundStyle(palette.ink)
                    .onSubmit { store.focusToken += 1 }
            }
            .frame(maxWidth: columnWidth, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 26)
            .padding(.bottom, 4)

            JournalTextView(
                text: Binding(get: { store.bodyText }, set: { store.setBody($0) }),
                style: EditorStyle(font: font.nsFont(CGFloat(fontSize)), lineHeight: CGFloat(lineHeight),
                                   text: palette.text, secondary: palette.secondary, accent: palette.accent,
                                   columnWidth: CGFloat(columnWidth), typewriter: typewriter),
                placeholder: isToday ? "Write a little. What's on your mind today?" : "Nothing written this day yet.",
                focusToken: store.focusToken
            )
            .id(store.journalID.uuidString + store.day)

            if store.showPrompts {
                PromptCard(palette: palette)
                    .frame(maxWidth: columnWidth)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 54)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(palette.bg)
        .overlay(alignment: .bottomTrailing) { PageCounter(palette: palette) }
        .overlay(alignment: .top) {
            if let toast = store.toast {
                Text(toast)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: store.showPrompts)
        .animation(.easeOut(duration: 0.2), value: store.toast)
    }
}

/// "0.6 of 2 pages" in the corner, with a thin bar that fills toward the daily goal.
struct PageCounter: View {
    @EnvironmentObject var store: Store
    let palette: Palette

    var body: some View {
        let words = TextStats(store.bodyText).words
        let pages = Double(words) / wordsPerPage
        let goal = store.journal.dailyGoal
        let fraction = min(1, pages / Double(goal))

        Button { store.showInfo.toggle() } label: {
            VStack(alignment: .trailing, spacing: 5) {
                HStack(spacing: 4) {
                    if fraction >= 1 { Image(systemName: "checkmark.seal.fill").foregroundStyle(palette.tint) }
                    Text(String(format: "%.1f", pages)).monospacedDigit()
                    Text("of \(goal) \(goal == 1 ? "page" : "pages")")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.muted)
                Capsule().fill(palette.muted.opacity(0.18))
                    .frame(width: 92, height: 3)
                    .overlay(alignment: .leading) {
                        Capsule().fill(palette.tint).frame(width: 92 * fraction, height: 3)
                    }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(palette.bg.opacity(0.92), in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .help("\(words) words · click for details (⌘I)")
        .padding(14)
    }
}

/// The entry info popover: pages, words, reading time, goal progress and how it compares.
struct EntryInfoView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let entry = store.entry
        let stats = TextStats(store.bodyText)
        let goal = store.journal.dailyGoal
        let progress = stats.pages / Double(goal)
        let average = store.averageWords(excluding: store.day)

        VStack(alignment: .leading, spacing: 14) {
            Text(Day.long(store.day)).font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                row("Pages", String(format: "%.1f", stats.pages))
                row("Words", stats.words.formatted())
                row("Paragraphs", stats.paragraphs.formatted())
                row("Characters", stats.characters.formatted())
                row("Reading time", stats.words == 0 ? "–" : "\(stats.readingMinutes) min")
                row("Sittings", "\(Entry.sections(of: store.bodyText).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count)")
                if let secs = entry?.writingSeconds, secs >= 60 {
                    row("Time writing", Duration.seconds(secs).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Daily goal")
                    Spacer()
                    Text("\(Int((progress * 100).rounded()))% of \(goal) \(goal == 1 ? "page" : "pages")")
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: min(progress, 1))
            }
            if average > 0 && stats.words > 0 {
                let diff = Double(stats.words - average) / Double(average)
                Label(abs(diff) < 0.1 ? "About your usual length (\(average) words)"
                      : "\(Int(abs(diff) * 100))% \(diff > 0 ? "longer" : "shorter") than your usual \(average) words",
                      systemImage: diff >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let entry {
                Text("Edited \(entry.modified.formatted(date: .abbreviated, time: .shortened)) · \(entry.versions.count) earlier versions")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(18)
        .frame(width: 300)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit().gridColumnAlignment(.trailing)
        }
    }
}
