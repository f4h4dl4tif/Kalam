import SwiftUI

@main
struct KalamApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = Store.shared
    @StateObject private var lock = LockManager.shared
    @AppStorage(Pref.showMenuBar) private var showMenuBar = true

    init() {
        #if DEBUG
        GlassSnapshot.prepare()
        #endif
        Pref.registerDefaults()
    }

    var body: some Scene {
        Window("Kalam", id: "main") {
            ContentView()
                .environmentObject(store)
                .environmentObject(lock)
                .frame(minWidth: 780, minHeight: 520)
        }
        .defaultSize(width: 1120, height: 760)
        .commands { KalamCommands(store: store, lock: lock) }

        Settings {
            SettingsView()
                .environmentObject(store)
                .environmentObject(lock)
        }

        MenuBarExtra(isInserted: $showMenuBar) {
            MenuBarView()
                .environmentObject(store)
                .environmentObject(lock)
        } label: {
            Image(systemName: "pencil.line")
        }
        .menuBarExtraStyle(.window)

        #if DEBUG
        // Only opened by --glass-snapshot: the menu bar panel's content in a window that can be captured.
        Window("Menu Bar Panel", id: "glass-snapshot-menubar") {
            MenuBarView()
                .environmentObject(store)
                .environmentObject(lock)
                .background(.regularMaterial)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        #endif
    }
}

struct KalamCommands: Commands {
    @ObservedObject var store: Store
    @ObservedObject var lock: LockManager
    @AppStorage(Pref.lockEnabled) private var lockEnabled = false

    var body: some Commands {
        SidebarCommands()

        CommandGroup(replacing: .newItem) {
            Button("New Sitting") { store.newSection() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("New Journal…") { store.beginNewJournal() }
                .keyboardShortcut("n", modifiers: [.command, .option])
        }

        CommandGroup(replacing: .importExport) {
            Button("Import…") { ImportExport.importFiles(store) }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Divider()
            Button("Export Entry as Markdown…") { ImportExport.exportEntry(store) }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Button("Export Journal as Markdown…") { ImportExport.exportJournal(store) }
            Button("Export Journal as PDF…") { ImportExport.exportPDF(store) }
            Button("Back Up Everything…") { ImportExport.backup(store) }
        }

        CommandGroup(replacing: .printItem) {
            Button("Print Entry…") { ImportExport.printEntry(store) }
                .keyboardShortcut("p")
        }

        CommandMenu("Go") {
            Button("Today") { store.goToday() }.keyboardShortcut("t")
            Button("Previous Day") { store.move(days: -1) }.keyboardShortcut("[")
            Button("Next Day") { store.move(days: 1) }.keyboardShortcut("]")
            Button("Previous Month") { store.moveMonth(-1) }.keyboardShortcut("[", modifiers: [.command, .option])
            Button("Next Month") { store.moveMonth(1) }.keyboardShortcut("]", modifiers: [.command, .option])
            Divider()
            ForEach(Array(store.library.journals.prefix(9).enumerated()), id: \.element.id) { i, j in
                Button(j.name) { store.selectJournal(j.id) }
                    .keyboardShortcut(KeyEquivalent(Character(String(i + 1))), modifiers: .command)
            }
        }

        CommandMenu("Entry") {
            Button("Entry Info") { store.showInfo.toggle() }.keyboardShortcut("i")
            Button("Version History…") { store.showHistory = true }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(store.entry == nil)
            Button(store.showPrompts ? "Hide Prompts" : "Show Prompts") { store.showPrompts.toggle() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Divider()
            Menu("Mood") {
                ForEach(Mood.allCases) { m in Button(m.name) { store.setMood(m) } }
                Divider()
                Button("Clear") { store.setMood(nil) }
            }
            Button("Edit Journal…") { store.editingJournal = store.journal }
        }

        CommandGroup(after: .appSettings) {
            Button("Lock Kalam") { lock.lock() }
                .keyboardShortcut("l", modifiers: [.command, .control])
                .disabled(!lockEnabled)
        }
    }
}
