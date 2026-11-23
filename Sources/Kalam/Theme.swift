import SwiftUI
import AppKit

enum Pref {
    static let theme = "theme"
    static let font = "editorFont"
    static let fontSize = "fontSize"
    static let lineHeight = "lineHeight"
    static let columnWidth = "columnWidth"
    static let typewriter = "typewriter"
    static let showMenuBar = "showMenuBar"
    static let hotKey = "hotKeyEnabled"
    static let aiChecks = "aiChecks"
    static let lockEnabled = "lockEnabled"
    static let lockAfter = "lockAfter"
    static let reminderEnabled = "reminderEnabled"
    static let reminderMinutes = "reminderMinutes"
    static let sidebarMode = "sidebarMode"
    static let glass = "glassTheme"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            theme: ThemeChoice.system.rawValue,
            font: EditorFont.newYork.rawValue,
            fontSize: 18.0,
            lineHeight: 1.55,
            columnWidth: 660.0,
            typewriter: false,
            showMenuBar: true,
            hotKey: true,
            aiChecks: true,
            lockEnabled: false,
            lockAfter: 5,
            reminderEnabled: false,
            reminderMinutes: 21 * 60,
            sidebarMode: "calendar",
            glass: false,
        ])
    }
}

enum ThemeChoice: String, CaseIterable, Identifiable {
    case system = "Automatic", paper = "Paper", sepia = "Sepia", night = "Night"
    var id: String { rawValue }

    var forcedScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .paper, .sepia: return .light
        case .night: return .dark
        }
    }
}

struct Palette {
    let background: NSColor
    let text: NSColor
    let secondary: NSColor
    let accent: NSColor

    var bg: Color { Color(nsColor: background) }
    var ink: Color { Color(nsColor: text) }
    var muted: Color { Color(nsColor: secondary) }
    var tint: Color { Color(nsColor: accent) }

    static let paper = Palette(background: NSColor(hex: 0xFAF6EE), text: NSColor(hex: 0x2B2722),
                               secondary: NSColor(hex: 0x8D857A), accent: NSColor(hex: 0x2F6F73))
    static let sepia = Palette(background: NSColor(hex: 0xF2E8D2), text: NSColor(hex: 0x3B2F22),
                               secondary: NSColor(hex: 0x8F7B62), accent: NSColor(hex: 0x8A5A2B))
    static let night = Palette(background: NSColor(hex: 0x1C1B19), text: NSColor(hex: 0xE6E0D4),
                               secondary: NSColor(hex: 0x8C867C), accent: NSColor(hex: 0x7FB8B3))

    static func resolve(_ theme: ThemeChoice, _ scheme: ColorScheme) -> Palette {
        switch theme {
        case .system: return scheme == .dark ? .night : .paper
        case .paper: return .paper
        case .sepia: return .sepia
        case .night: return .night
        }
    }
}

enum EditorFont: String, CaseIterable, Identifiable {
    case newYork = "New York", georgia = "Georgia", palatino = "Palatino", baskerville = "Baskerville",
         charter = "Charter", iowan = "Iowan Old Style", sans = "System Sans", mono = "Monospaced"
    var id: String { rawValue }

    func nsFont(_ size: CGFloat) -> NSFont {
        let fallback = NSFont.systemFont(ofSize: size)
        switch self {
        case .newYork:
            if let d = fallback.fontDescriptor.withDesign(.serif), let f = NSFont(descriptor: d, size: size) { return f }
            return NSFont(name: "Georgia", size: size) ?? fallback
        case .georgia: return NSFont(name: "Georgia", size: size) ?? fallback
        case .palatino: return NSFont(name: "Palatino-Roman", size: size) ?? fallback
        case .baskerville: return NSFont(name: "Baskerville", size: size) ?? fallback
        case .charter: return NSFont(name: "Charter-Roman", size: size) ?? fallback
        case .iowan: return NSFont(name: "IowanOldStyle-Roman", size: size) ?? fallback
        case .sans: return fallback
        case .mono: return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }
    }

    func font(_ size: CGFloat) -> Font { Font(nsFont(size) as CTFont) }
}

/// Reads the theme settings and works out the palette for the current appearance.
struct ThemeReader<Content: View>: View {
    @AppStorage(Pref.theme) private var theme = ThemeChoice.system.rawValue
    @Environment(\.colorScheme) private var scheme
    let content: (Palette) -> Content

    var body: some View {
        content(Palette.resolve(ThemeChoice(rawValue: theme) ?? .system, scheme))
    }
}

/// Liquid Glass theme (macOS 26+). Off by default; when off, Kalam looks exactly as before.
enum GlassTheme {
    static var supported: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }
}

extension View {
    /// Puts a floating surface on Liquid Glass when the Glass theme is on, otherwise on its usual background.
    @ViewBuilder
    func glassSurface<S: Shape, B: View>(_ glassOn: Bool, in shape: S, tint: Color? = nil,
                                         @ViewBuilder plain: () -> B) -> some View {
        if #available(macOS 26, *), glassOn {
            self.glassEffect(tint.map { SwiftUI.Glass.regular.tint($0) } ?? SwiftUI.Glass.regular, in: shape)
        } else {
            self.background(plain())
        }
    }
}

extension View {
    /// Liquid Glass button style when the Glass theme is on; otherwise the button keeps its usual style
    /// (`.borderedProminent` for prominent buttons).
    @ViewBuilder
    func glassButton(_ glassOn: Bool, prominent: Bool = false) -> some View {
        if #available(macOS 26, *), glassOn {
            if prominent { self.buttonStyle(.glassProminent) } else { self.buttonStyle(.glass) }
        } else if prominent {
            self.buttonStyle(.borderedProminent)
        } else {
            self
        }
    }
}
