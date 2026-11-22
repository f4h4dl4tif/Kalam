import SwiftUI

/// Earlier versions of the current entry, with a preview and Restore.
struct HistoryView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var selection: UUID?

    var body: some View {
        let entry = store.entry
        let versions = (entry?.versions ?? []).reversed() as [EntryVersion]
        let chosen = versions.first { $0.id == selection }

        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Version History").font(.headline)
                    Text(Day.long(store.day)).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(16)
            Divider()

            if versions.isEmpty {
                ContentUnavailableView("No earlier versions yet", systemImage: "clock.arrow.circlepath",
                                       description: Text("Kalam keeps a version each time you come back to an entry, and every ten minutes while you write."))
                    .frame(maxHeight: .infinity)
            } else {
                HSplitView {
                    List(selection: $selection) {
                        Section("Current") {
                            row(title: "Now", words: TextStats(entry?.body ?? "").words).tag(UUID?.none)
                        }
                        Section("Earlier") {
                            ForEach(versions) { v in
                                row(title: v.date.formatted(date: .abbreviated, time: .shortened),
                                    words: TextStats(v.body).words)
                                    .tag(Optional(v.id))
                            }
                        }
                    }
                    .frame(minWidth: 200, maxWidth: 260)

                    VStack(alignment: .leading, spacing: 0) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                let title = chosen?.title ?? entry?.title ?? ""
                                if !title.isEmpty {
                                    Text(title).font(.system(size: 20, weight: .semibold, design: .serif))
                                }
                                Text(chosen?.body ?? entry?.body ?? "")
                                    .font(.system(size: 14, design: .serif))
                                    .lineSpacing(5)
                                    .textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)
                        }
                        Divider()
                        HStack {
                            Spacer()
                            Button("Restore This Version") {
                                if let chosen { store.restore(chosen); dismiss() }
                            }
                            .disabled(chosen == nil)
                            .keyboardShortcut(.defaultAction)
                        }
                        .padding(12)
                    }
                    .frame(minWidth: 380)
                }
            }
        }
        .frame(width: 760, height: 520)
    }

    private func row(title: String, words: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text("\(words) words").font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Create or edit a journal: name, icon and daily goal.
struct JournalEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var journal: Journal
    @State private var confirmDelete = false

    static let icons = ["book.closed", "book", "text.book.closed", "pencil.line", "heart", "sun.max", "moon.stars",
                        "leaf", "brain.head.profile", "figure.walk", "airplane", "briefcase", "graduationcap",
                        "house", "music.note", "camera", "fork.knife", "dumbbell", "sparkles", "star",
                        "lightbulb", "cloud.sun", "hands.sparkles", "flame"]

    var isNew: Bool { !store.library.journals.contains { $0.id == journal.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(isNew ? "New Journal" : "Edit Journal").font(.headline)

            TextField("Name", text: $journal.name, prompt: Text("Gratitude, Work log, Travel…"))
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 8) {
                Text("Icon").font(.subheadline).foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 6), count: 8), spacing: 6) {
                    ForEach(Self.icons, id: \.self) { icon in
                        Button { journal.icon = icon } label: {
                            Image(systemName: icon)
                                .frame(width: 32, height: 32)
                                .background(RoundedRectangle(cornerRadius: 7)
                                    .fill(journal.icon == icon ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.05)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Daily goal").font(.subheadline).foregroundStyle(.secondary)
                Picker("Daily goal", selection: $journal.dailyGoal) {
                    ForEach(1...5, id: \.self) { n in Text("\(n) \(n == 1 ? "page" : "pages")").tag(n) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text("About \(journal.dailyGoal * Int(wordsPerPage)) words. Days in the calendar fill in as you get closer.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                if !isNew && store.library.journals.count > 1 {
                    Button("Delete Journal…", role: .destructive) { confirmDelete = true }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isNew ? "Create" : "Save") { store.saveJournal(journal); dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
        .confirmationDialog("Delete “\(journal.name)” and all its entries?", isPresented: $confirmDelete) {
            Button("Delete Journal and Entries", role: .destructive) { store.deleteJournal(journal.id); dismiss() }
        } message: {
            Text("\(store.entries(in: journal.id).count) entries will be removed. Export a backup first if you might want them later.")
        }
    }
}

/// Shown while ⌘ is held down for a moment.
struct ShortcutsOverlay: View {
    static let items: [(String, String)] = [
        ("⌘T", "Today"), ("⌘[  ⌘]", "Previous / next day"), ("⌥⌘[  ⌥⌘]", "Previous / next month"),
        ("⌘1 – ⌘9", "Switch journal"), ("⇧⌘N", "New sitting (or type -- then Return)"),
        ("⌃⌘S", "Show or hide the sidebar"), ("⌘I", "Entry info"), ("⇧⌘H", "Version history"),
        ("⇧⌘P", "Guided prompts"), ("⌘F", "Find in entry"), ("⇧⌘E", "Export entry"),
        ("⌘P", "Print entry"), ("⌃⌘L", "Lock Kalam"), ("⌃⌥J", "Open today from anywhere"), ("⌘,", "Settings"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Keyboard Shortcuts").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 7) {
                ForEach(Self.items, id: \.0) { key, label in
                    GridRow {
                        Text(key).font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)
                        Text(label).font(.system(size: 13))
                    }
                }
            }
        }
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 20)
        .allowsHitTesting(false)
    }
}
