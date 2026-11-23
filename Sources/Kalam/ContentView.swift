import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var lock: LockManager
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Pref.theme) private var theme = ThemeChoice.system.rawValue
    @State private var columns: NavigationSplitViewVisibility = .all
    @State private var showShortcuts = false
    @State private var monitor: Any?
    @State private var holdTimer: Timer?
    #if DEBUG
    @Environment(\.openSettings) private var openSettings
    #endif

    var body: some View {
        ZStack {
            if lock.isLocked {
                LockView()
            } else {
                NavigationSplitView(columnVisibility: $columns) {
                    SidebarView()
                        .navigationSplitViewColumnWidth(min: 250, ideal: 280, max: 360)
                } detail: {
                    EditorView()
                        .toolbar { toolbar }
                }
                .navigationTitle(store.journal.name)
                .navigationSubtitle(store.day == Day.today ? "Today" : Day.short(store.day))
                .sheet(isPresented: $store.showHistory) { HistoryView() }
                .sheet(item: $store.editingJournal) { JournalEditor(journal: $0) }

                if showShortcuts {
                    ShortcutsOverlay().transition(.opacity)
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: showShortcuts)
        .preferredColorScheme((ThemeChoice(rawValue: theme) ?? .system).forcedScheme)
        .onAppear {
            AppActions.openMain = { openWindow(id: "main") }
            #if DEBUG
            GlassSnapshot.openSettings = { openSettings() }
            GlassSnapshot.openMenuBarPanel = { openWindow(id: "glass-snapshot-menubar") }
            #endif
            installHoldCommandMonitor()
        }
        .onDisappear {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { store.move(days: -1) } label: { Image(systemName: "chevron.left") }
                .help("Previous day (⌘[)")
            Button { store.goToday() } label: { Text("Today") }
                .help("Today (⌘T)")
                .disabled(store.day == Day.today)
            Button { store.move(days: 1) } label: { Image(systemName: "chevron.right") }
                .help("Next day (⌘])")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                ForEach(Mood.allCases) { m in
                    Button { store.setMood(m) } label: { Label(m.name, systemImage: m.symbol) }
                }
                if store.entry?.mood != nil {
                    Divider()
                    Button("Clear Mood") { store.setMood(nil) }
                }
            } label: {
                let mood = store.entry?.mood.flatMap(Mood.init(rawValue:))
                Label("Mood", systemImage: mood?.symbol ?? "face.smiling")
            }
            .help("How was the day?")

            Button { store.newSection() } label: { Label("New Sitting", systemImage: "text.append") }
                .help("Start a new sitting on this day (⇧⌘N, or type -- then Return)")

            Toggle(isOn: $store.showPrompts) { Label("Prompts", systemImage: "text.bubble") }
                .help("Guided prompts (⇧⌘P)")

            Button { store.showHistory = true } label: { Label("History", systemImage: "clock.arrow.circlepath") }
                .help("Version history (⇧⌘H)")
                .disabled(store.entry == nil)

            Button { store.showInfo.toggle() } label: { Label("Info", systemImage: "info.circle") }
                .help("Entry info (⌘I)")
                .popover(isPresented: $store.showInfo, arrowEdge: .bottom) {
                    EntryInfoView().environmentObject(store)
                }

            Menu {
                Button("Export Entry as Markdown…") { ImportExport.exportEntry(store) }
                Button("Export Journal as Markdown…") { ImportExport.exportJournal(store) }
                Button("Export Journal as PDF…") { ImportExport.exportPDF(store) }
                Divider()
                Button("Print Entry…") { ImportExport.printEntry(store) }
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
    }

    /// Holding ⌘ on its own for a moment shows every shortcut.
    private func installHoldCommandMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown, .leftMouseDown]) { event in
            holdTimer?.invalidate()
            if event.type == .flagsChanged,
               event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
                holdTimer = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: false) { _ in showShortcuts = true }
            } else {
                showShortcuts = false
            }
            return event
        }
    }
}

struct MenuBarView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var lock: LockManager
    @AppStorage(Pref.glass) private var glass = false
    @State private var note = ""

    var body: some View {
        let today = store.index(day: Day.today).map { store.library.entries[$0] }
        let pages = today?.pages ?? 0
        let goal = store.journal.dailyGoal

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(store.journal.name, systemImage: store.journal.icon).font(.headline)
                Spacer()
                Text(Day.short(Day.today)).font(.caption).foregroundStyle(.secondary)
            }
            if lock.isLocked {
                Label("Kalam is locked", systemImage: "lock.fill").foregroundStyle(.secondary)
                Button("Open Kalam") { AppActions.showToday() }.glassButton(glass)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: min(1, pages / Double(goal)))
                    Text(String(format: "%.1f of %d %@ today · %d words", pages, goal, goal == 1 ? "page" : "pages", today?.stats.words ?? 0))
                        .font(.caption).foregroundStyle(.secondary)
                }
                TextField("A quick thought for today…", text: $note, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Open Today") { AppActions.showToday() }.glassButton(glass)
                    Spacer()
                    Button("Add to Today") {
                        store.appendToToday(note)
                        note = ""
                        store.flash("Added to today")
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .glassButton(glass, prominent: true)
                }
            }
            Divider()
            HStack {
                Text("⌃⌥J opens today from anywhere").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.borderless).font(.caption)
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}
