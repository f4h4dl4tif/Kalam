import SwiftUI
import AppKit

struct SettingsView: View {
    var body: some View {
        TabView {
            WritingSettings().tabItem { Label("Writing", systemImage: "textformat") }
            PromptSettings().tabItem { Label("Prompts", systemImage: "text.bubble") }
            PrivacySettings().tabItem { Label("Privacy", systemImage: "lock") }
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            DataSettings().tabItem { Label("Data", systemImage: "externaldrive") }
        }
        .frame(width: 520)
    }
}

struct WritingSettings: View {
    @AppStorage(Pref.theme) private var theme = ThemeChoice.system.rawValue
    @AppStorage(Pref.font) private var font = EditorFont.newYork.rawValue
    @AppStorage(Pref.fontSize) private var fontSize = 18.0
    @AppStorage(Pref.lineHeight) private var lineHeight = 1.55
    @AppStorage(Pref.columnWidth) private var columnWidth = 660.0
    @AppStorage(Pref.typewriter) private var typewriter = false
    @AppStorage(Pref.glass) private var glass = false

    var body: some View {
        Form {
            Picker("Theme", selection: $theme) {
                ForEach(ThemeChoice.allCases) { Text($0.rawValue).tag($0.rawValue) }
            }
            VStack(alignment: .leading, spacing: 2) {
                Toggle("Liquid Glass theme", isOn: $glass).disabled(!GlassTheme.supported)
                Text(GlassTheme.supported
                     ? "Floating cards, buttons and notices sit on Apple's Liquid Glass. The page stays plain paper."
                     : "Requires macOS 26.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Picker("Font", selection: $font) {
                ForEach(EditorFont.allCases) { f in Text(f.rawValue).font(f.font(13)).tag(f.rawValue) }
            }
            LabeledContent("Text size") {
                HStack {
                    Slider(value: $fontSize, in: 13...28, step: 1)
                    Text("\(Int(fontSize)) pt").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
            }
            LabeledContent("Line spacing") {
                Slider(value: $lineHeight, in: 1.2...2.1)
            }
            LabeledContent("Column width") {
                Slider(value: $columnWidth, in: 480...900, step: 20)
            }
            Toggle("Typewriter mode: keep the line you're writing in the middle", isOn: $typewriter)
            Text("Type -- then Return to add a divider and start a new sitting on the same day. Arabic and other right-to-left writing lines up automatically.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

struct PromptSettings: View {
    @EnvironmentObject var store: Store
    @AppStorage(Pref.aiChecks) private var aiChecks = true
    @State private var newQuestion = ""

    var body: some View {
        Form {
            Section {
                Toggle("Tick questions automatically as my writing answers them", isOn: $aiChecks)
                Text(PromptChecker.unavailableReason + " Your writing is read only by Apple's on-device model; nothing leaves this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("My questions") {
                ForEach(Array(store.customPrompts.enumerated()), id: \.offset) { i, q in
                    HStack {
                        Text(q)
                        Spacer()
                        Button(role: .destructive) { store.customPrompts.remove(at: i) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField("Add a question", text: $newQuestion).onSubmit(add)
                    Button("Add", action: add).disabled(newQuestion.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text("Your questions appear as “My questions” in the prompt card (⇧⌘P).").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func add() {
        let q = newQuestion.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        store.customPrompts.append(q)
        newQuestion = ""
    }
}

struct PrivacySettings: View {
    @EnvironmentObject var lock: LockManager
    @AppStorage(Pref.lockEnabled) private var lockEnabled = false
    @AppStorage(Pref.lockAfter) private var lockAfter = 5

    var body: some View {
        Form {
            Toggle("Lock Kalam with \(LockManager.methodName)", isOn: $lockEnabled)
            Picker("Lock after leaving the app for", selection: $lockAfter) {
                Text("Immediately").tag(0)
                Text("1 minute").tag(1)
                Text("5 minutes").tag(5)
                Text("15 minutes").tag(15)
                Text("1 hour").tag(60)
            }
            .disabled(!lockEnabled)
            Button("Lock Now") { lock.lock() }.disabled(!lockEnabled)
            Text("Your journal lives only on this Mac, in ~/Library/Application Support/Kalam. No account, no analytics, no tracking.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

struct GeneralSettings: View {
    @AppStorage(Pref.showMenuBar) private var showMenuBar = true
    @AppStorage(Pref.hotKey) private var hotKey = true
    @AppStorage(Pref.reminderEnabled) private var reminder = false
    @AppStorage(Pref.reminderMinutes) private var reminderMinutes = 21 * 60

    var body: some View {
        Form {
            Toggle("Show Kalam in the menu bar for quick notes", isOn: $showMenuBar)
            Toggle("Open today's entry with ⌃⌥J from any app", isOn: $hotKey)
                .onChange(of: hotKey) { _, on in HotKey.shared.setEnabled(on) }
            Section("Reminder") {
                Toggle("Remind me to write each day", isOn: $reminder)
                    .onChange(of: reminder) { _, _ in Reminders.reschedule() }
                DatePicker("At", selection: Binding(
                    get: { Calendar.current.date(bySettingHour: reminderMinutes / 60, minute: reminderMinutes % 60, second: 0, of: Date()) ?? Date() },
                    set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                           reminderMinutes = (c.hour ?? 21) * 60 + (c.minute ?? 0)
                           Reminders.reschedule() }),
                    displayedComponents: .hourAndMinute)
                .disabled(!reminder)
                Text("One gentle notification. No streaks, no guilt.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct DataSettings: View {
    @EnvironmentObject var store: Store

    var body: some View {
        Form {
            LabeledContent("Journals", value: "\(store.library.journals.count)")
            LabeledContent("Entries", value: "\(store.library.entries.filter { !$0.isBlank }.count)")
            LabeledContent("Words written", value: store.library.entries.reduce(0) { $0 + $1.stats.words }.formatted())
            Section("Export") {
                Button("Export All Journals as Markdown…") { ImportExport.exportJournal(store, all: true) }
                Button("Back Up Everything…") { ImportExport.backup(store) }
            }
            Section("Import") {
                Button("Import…") { ImportExport.importFiles(store) }
                Text("Kalam backups, Day One JSON exports, or Markdown and text files named by date (2026-11-22.md). Entries for days you already have are added as a new sitting.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("Show Data Folder in Finder") { NSWorkspace.shared.activateFileViewerSelecting([store.folder]) }
        }
        .formStyle(.grouped)
    }
}
