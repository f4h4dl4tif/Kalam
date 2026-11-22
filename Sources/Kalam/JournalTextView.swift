import SwiftUI
import AppKit

/// Scroll view that keeps its text view exactly as wide as the visible area.
final class PaperScrollView: NSScrollView {
    override func tile() {
        super.tile()
        if let doc = documentView, abs(doc.frame.width - contentSize.width) > 0.5 {
            doc.setFrameSize(NSSize(width: contentSize.width, height: doc.frame.height))
        }
    }
}

/// NSTextView that keeps its writing in a centred column and draws a placeholder.
final class PaperTextView: NSTextView {
    var columnWidth: CGFloat = 660 { didSet { updateInset() } }
    var placeholder: NSAttributedString? { didSet { needsDisplay = true } }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateInset()
    }

    func updateInset() {
        let x = max(32, (bounds.width - columnWidth) / 2)
        if abs(textContainerInset.width - x) > 0.5 {
            textContainerInset = NSSize(width: x, height: 14)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty, let placeholder {
            let pad = textContainer?.lineFragmentPadding ?? 0
            placeholder.draw(at: NSPoint(x: textContainerInset.width + pad, y: textContainerInset.height))
        }
    }
}

struct EditorStyle: Equatable {
    var font: NSFont
    var lineHeight: CGFloat
    var text: NSColor
    var secondary: NSColor
    var accent: NSColor
    var columnWidth: CGFloat
    var typewriter: Bool
}

struct JournalTextView: NSViewRepresentable {
    @Binding var text: String
    var style: EditorStyle
    var placeholder: String
    var focusToken: Int

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = PaperScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.automaticallyAdjustsContentInsets = false

        let tv = PaperTextView(usingTextLayoutManager: false)
        tv.frame = NSRect(x: 0, y: 0, width: 700, height: 500)
        tv.minSize = .zero
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.lineFragmentPadding = 0
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.isAutomaticDashSubstitutionEnabled = false   // so "--" stays two hyphens for the divider
        tv.isAutomaticQuoteSubstitutionEnabled = true
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = true
        tv.isAutomaticTextReplacementEnabled = true
        tv.delegate = context.coordinator
        tv.string = text
        scroll.documentView = tv

        context.coordinator.textView = tv
        context.coordinator.apply(style, force: true)
        context.coordinator.lastFocus = focusToken
        DispatchQueue.main.async { context.coordinator.focus(moveToEnd: true) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        c.parent = self
        guard let tv = c.textView else { return }
        if tv.string != text && !tv.hasMarkedText() {
            tv.string = text
            c.restyle()
            tv.scroll(.zero)
        }
        c.apply(style, force: false)
        if c.lastFocus != focusToken {
            c.lastFocus = focusToken
            DispatchQueue.main.async { c.focus(moveToEnd: true) }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: JournalTextView
        weak var textView: PaperTextView?
        var lastFocus = 0
        private var current: EditorStyle?

        init(_ parent: JournalTextView) { self.parent = parent }

        func apply(_ style: EditorStyle, force: Bool) {
            guard force || style != current, let tv = textView else { return }
            current = style
            tv.columnWidth = style.columnWidth
            tv.insertionPointColor = style.accent
            tv.placeholder = NSAttributedString(string: parent.placeholder, attributes: [
                .font: style.font, .foregroundColor: style.secondary.withAlphaComponent(0.6),
            ])
            tv.selectedTextAttributes = [.backgroundColor: style.accent.withAlphaComponent(0.22)]
            if let scroll = tv.enclosingScrollView {
                let bottom = style.typewriter ? max(120, scroll.bounds.height / 2) : 90
                scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: bottom, right: 0)
            }
            restyle()
        }

        var baseAttributes: [NSAttributedString.Key: Any] {
            guard let s = current else { return [:] }
            let para = NSMutableParagraphStyle()
            para.lineHeightMultiple = s.lineHeight
            para.paragraphSpacing = s.font.pointSize * 0.55
            para.baseWritingDirection = .natural
            para.alignment = .natural
            return [.font: s.font, .foregroundColor: s.text, .paragraphStyle: para]
        }

        /// Re-applies the font and colours, and centres ornamentMark lines.
        func restyle() {
            guard let tv = textView, let s = current, let storage = tv.textStorage, !tv.hasMarkedText() else { return }
            let base = baseAttributes
            let full = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.setAttributes(base, range: full)
            (storage.string as NSString).enumerateSubstrings(in: full, options: .byLines) { sub, range, _, _ in
                guard sub?.trimmingCharacters(in: .whitespaces) == ornamentMark else { return }
                let p = NSMutableParagraphStyle()
                p.alignment = .center
                p.paragraphSpacingBefore = s.font.pointSize * 0.8
                p.paragraphSpacing = s.font.pointSize * 1.1
                p.lineHeightMultiple = s.lineHeight
                storage.addAttributes([
                    .paragraphStyle: p,
                    .foregroundColor: s.accent,
                    .font: NSFont(descriptor: s.font.fontDescriptor, size: s.font.pointSize * 1.2) ?? s.font,
                ], range: range)
            }
            storage.endEditing()
            tv.typingAttributes = base
            tv.needsDisplay = true
        }

        func focus(moveToEnd: Bool) {
            guard let tv = textView, let window = tv.window else { return }
            window.makeFirstResponder(tv)
            if moveToEnd {
                let end = (tv.string as NSString).length
                tv.setSelectedRange(NSRange(location: end, length: 0))
                tv.scrollRangeToVisible(NSRange(location: end, length: 0))
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            parent.text = tv.string
            restyle()
            if current?.typewriter == true { centerCaret() }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            if current?.typewriter == true, NSApp.currentEvent?.type == .keyDown { centerCaret() }
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            let ns = textView.string as NSString
            let sel = textView.selectedRange()
            guard sel.length == 0 else { return false }
            let lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))
            var line = ns.substring(with: lineRange)
            if line.hasSuffix("\n") { line.removeLast() }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed == "--" || trimmed == "—" else { return false }
            let replace = NSRange(location: lineRange.location, length: (line as NSString).length)
            let new = ornamentMark + "\n"
            if textView.shouldChangeText(in: replace, replacementString: new) {
                textView.replaceCharacters(in: replace, with: new)
                textView.didChangeText()
                textView.setSelectedRange(NSRange(location: replace.location + (new as NSString).length, length: 0))
            }
            return true
        }

        /// Typewriter mode: keep the line being written in the middle of the window.
        func centerCaret() {
            guard let tv = textView, let window = tv.window, let scroll = tv.enclosingScrollView else { return }
            let loc = tv.selectedRange().location
            let screen = tv.firstRect(forCharacterRange: NSRange(location: loc, length: 0), actualRange: nil)
            guard screen != .zero else { return }
            let inWindow = window.convertFromScreen(screen)
            let rect = tv.convert(inWindow, from: nil)
            let clip = scroll.contentView
            let target = NSPoint(x: 0, y: rect.midY - clip.bounds.height / 2)
            let constrained = clip.constrainBoundsRect(NSRect(origin: target, size: clip.bounds.size)).origin
            clip.setBoundsOrigin(constrained)
            scroll.reflectScrolledClipView(clip)
        }
    }
}
