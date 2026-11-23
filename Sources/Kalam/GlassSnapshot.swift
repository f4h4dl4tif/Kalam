#if DEBUG
import SwiftUI
import AppKit

/// Debug aid: `Kalam --glass-snapshot <dir>` captures the main window, Settings and the menu bar panel
/// with the Liquid Glass theme off and on, in light and dark, using sample data in a temporary folder.
/// It captures the real on-screen windows (cacheDisplay can't draw Liquid Glass), then quits.
/// Preferences it touches are put back afterwards.
enum GlassSnapshot {
    static var openSettings: (() -> Void)?
    static var openMenuBarPanel: (() -> Void)?
    static var isActive: Bool { CommandLine.arguments.contains("--glass-snapshot") }
    private static let touchedKeys = [Pref.theme, Pref.glass, Pref.sidebarMode, "journalID"]
    private static var saved: [String: Any?] = [:]

    /// Called before anything reads preferences or the journal store.
    static func prepare() {
        guard isActive else { return }
        let dir = NSTemporaryDirectory() + "kalam-glass-snapshot-\(getpid())"
        try? FileManager.default.removeItem(atPath: dir)
        setenv("KALAM_DATA_DIR", dir, 1)
        for k in touchedKeys { saved[k] = UserDefaults.standard.object(forKey: k) }
        UserDefaults.standard.set(ThemeChoice.system.rawValue, forKey: Pref.theme)
        UserDefaults.standard.set("calendar", forKey: Pref.sidebarMode)
    }

    private static func restore() {
        for (k, v) in saved {
            if let v { UserDefaults.standard.set(v, forKey: k) } else { UserDefaults.standard.removeObject(forKey: k) }
        }
        if let dir = ProcessInfo.processInfo.environment["KALAM_DATA_DIR"] { try? FileManager.default.removeItem(atPath: dir) }
    }

    private static func seed() {
        let s = Store.shared
        let cal = Calendar.current
        let samples: [(Int, String, String)] = [
            (-1, "A slow Sunday", "Read on the balcony until the light went. Called home."),
            (-2, "Errands", "Groceries, the post office, and a long walk back by the canal."),
            (-4, "Rain", "It rained all afternoon. I didn't mind."),
            (-6, "New notebook", "Started this journal again. Small steps."),
            (-365, "Last year", "The first cold morning of the season."),
        ]
        for (offset, title, body) in samples {
            s.select(day: Day.key(cal.date(byAdding: .day, value: offset, to: Date())!))
            s.setTitle(title)
            s.setBody(body)
        }
        s.goToday()
        s.setTitle("The quiet before work")
        s.setBody("""
        Woke before the alarm and made tea in the dark. The street was still, just the bakery van and a few lit windows across the way.

        I want to keep mornings like this — no phone for the first hour, a page here, then the day. Yesterday felt scattered; today I'd like to finish the draft and leave the rest.

        Grateful for: the tea, the quiet, the letter from Sara.
        """)
        s.setMood(Mood.allCases.first)
        s.showPrompts = true
    }

    static func run(into path: String) {
        let out = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        seed()

        var steps: [() -> Void] = []
        for dark in [false, true] {
            for glass in [false, true] {
                let suffix = "\(glass ? "glass" : "plain")-\(dark ? "dark" : "light")"
                steps.append {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                    UserDefaults.standard.set(glass, forKey: Pref.glass)
                    mainWindow()?.setContentSize(NSSize(width: 1120, height: 760))
                    mainWindow()?.makeKeyAndOrderFront(nil)
                }
                steps.append { capture(mainWindow(), out.appendingPathComponent("main-\(suffix).png")) }
                steps.append { openSettings?() }
                steps.append {
                    let sw = NSApp.windows.first { $0.isVisible && $0 != mainWindow() && !$0.className.contains("StatusBar") && !$0.className.contains("MenuBarExtra") }
                    capture(sw, out.appendingPathComponent("settings-\(suffix).png"))
                    sw?.close()
                    openMenuBarPanel?()
                }
                steps.append {
                    let w = NSApp.windows.first { $0.isVisible && $0.title == "Menu Bar Panel" }
                    capture(w, out.appendingPathComponent("menubar-\(suffix).png"))
                    w?.orderOut(nil)
                }
            }
        }
        steps.append {
            restore()
            NSApp.terminate(nil)
        }

        func next(_ i: Int) {
            guard i < steps.count else { return }
            steps[i]()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { next(i + 1) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { next(0) }
    }

    private static func mainWindow() -> NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true } ?? NSApp.windows.first { $0.canBecomeMain && $0.title == "Journal" }
    }

    private typealias CapFn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    private static func capture(_ window: NSWindow?, _ url: URL) {
        guard let window, let sym = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage") else {
            print("glass-snapshot: no window for \(url.lastPathComponent)"); return
        }
        let f = unsafeBitCast(sym, to: CapFn.self)
        guard let img = f(.null, 8, UInt32(window.windowNumber), 1 | 8)?.takeRetainedValue() else { return }
        try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: url)
        print("glass-snapshot: wrote \(url.path)")
    }
}
#endif
