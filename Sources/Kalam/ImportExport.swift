import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum ImportExport {
    // MARK: Markdown

    static func markdown(_ e: Entry, journal: Journal?) -> String {
        var lines = ["---", "date: \(e.day)"]
        if let journal { lines.append("journal: \(journal.name)") }
        if let mood = e.mood.flatMap(Mood.init(rawValue:)) { lines.append("mood: \(mood.name.lowercased())") }
        lines.append("words: \(e.stats.words)")
        lines.append("---")
        lines.append("")
        let title = e.title.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append("# " + (title.isEmpty ? Day.long(e.day) : title))
        lines.append("")
        let body = e.body.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) == ornamentMark ? "\n* * *\n" : $0 }
            .joined(separator: "\n")
        lines.append(body)
        return lines.joined(separator: "\n") + "\n"
    }

    static func exportEntry(_ store: Store) {
        guard let e = store.entry else { store.flash("Nothing written on this day yet"); return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "\(e.day).md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try markdown(e, journal: store.journal).write(to: url, atomically: true, encoding: .utf8)
            store.flash("Exported \(url.lastPathComponent)")
        } catch {
            alert("Couldn't export the entry", error.localizedDescription)
        }
    }

    /// Writes one Markdown file per day into Journal/YYYY/MM/ folders.
    static func exportJournal(_ store: Store, all: Bool = false) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = all ? "Choose a folder for all your journals" : "Choose a folder for “\(store.journal.name)”"
        guard panel.runModal() == .OK, let base = panel.url else { return }
        let journals = all ? store.library.journals : [store.journal]
        var count = 0
        do {
            for j in journals {
                let root = base.appendingPathComponent(safe(j.name), isDirectory: true)
                for e in store.entries(in: j.id) where !e.isBlank {
                    let dir = root.appendingPathComponent(String(e.day.prefix(4)), isDirectory: true)
                        .appendingPathComponent(String(e.day.dropFirst(5).prefix(2)), isDirectory: true)
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    try markdown(e, journal: j).write(to: dir.appendingPathComponent("\(e.day).md"), atomically: true, encoding: .utf8)
                    count += 1
                }
            }
            store.flash("Exported \(count) entries as Markdown")
            NSWorkspace.shared.activateFileViewerSelecting([base])
        } catch {
            alert("Couldn't finish the export", error.localizedDescription)
        }
    }

    /// A full backup of every journal, entry, version and setting, which Kalam can import again.
    static func backup(_ store: Store) {
        store.saveNow()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Kalam Backup \(Day.today).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Store.encoder.encode(store.library).write(to: url, options: .atomic)
            store.flash("Backed up \(store.library.entries.count) entries")
        } catch {
            alert("Couldn't save the backup", error.localizedDescription)
        }
    }

    // MARK: Import

    /// Imports Kalam backups, Day One JSON exports, and Markdown or text files (or folders of them).
    static func importFiles(_ store: Store) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Import"
        panel.message = "Choose a Kalam backup, a Day One JSON export, or Markdown/text files named by date (e.g. 2026-11-22.md)"
        guard panel.runModal() == .OK else { return }

        var files: [URL] = []
        for url in panel.urls {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                while let f = walker?.nextObject() as? URL { files.append(f) }
            } else {
                files.append(url)
            }
        }

        var count = 0, skipped = 0
        for f in files {
            switch f.pathExtension.lowercased() {
            case "json": count += importJSON(f, store)
            case "md", "markdown", "txt", "text":
                if importText(f, store) { count += 1 } else { skipped += 1 }
            default: continue
            }
        }
        store.scheduleSave()
        let note = skipped > 0 ? " (\(skipped) skipped: no date found, or already imported)" : ""
        alert("Import finished", "Added or merged \(count) entries\(note).", style: .informational)
    }

    private static func importJSON(_ url: URL, _ store: Store) -> Int {
        guard let data = try? Data(contentsOf: url) else { return 0 }
        if let lib = try? Store.decoder.decode(Library.self, from: data) {
            return store.merge(library: lib)
        }
        // Day One: {"entries":[{"creationDate":"2024-01-02T08:00:00Z","text":"…"}]}
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = obj["entries"] as? [[String: Any]] else { return 0 }
        let iso = ISO8601DateFormatter()
        var n = 0
        for e in entries {
            guard let text = e["text"] as? String,
                  let ds = e["creationDate"] as? String, let date = iso.date(from: ds) else { continue }
            var body = text.replacingOccurrences(of: "\\", with: "")
            var title = ""
            if let first = body.split(separator: "\n", maxSplits: 1).first, first.hasPrefix("# ") {
                title = String(first.dropFirst(2))
                body = String(body.dropFirst(first.count)).trimmingCharacters(in: .newlines)
            }
            if store.merge(day: Day.key(date), title: title, body: body, into: store.journal.id, created: date) { n += 1 }
        }
        return n
    }

    private static func importText(_ url: URL, _ store: Store) -> Bool {
        guard var text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        var day: String?
        var mood: Int?

        // Front matter
        if text.hasPrefix("---\n"), let end = text.range(of: "\n---", range: text.index(text.startIndex, offsetBy: 4)..<text.endIndex) {
            let front = text[text.index(text.startIndex, offsetBy: 4)..<end.lowerBound]
            for line in front.split(separator: "\n") {
                let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2 else { continue }
                if parts[0] == "date" { day = firstDate(in: parts[1]) }
                if parts[0] == "mood" { mood = Mood.allCases.first { $0.name.lowercased() == parts[1].lowercased() }?.rawValue }
            }
            text = String(text[end.upperBound...])
        }
        day = day ?? firstDate(in: url.deletingPathExtension().lastPathComponent)
        guard let day else { return false }

        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var title = ""
        if let first = text.split(separator: "\n", maxSplits: 1).first, first.hasPrefix("# ") {
            title = String(first.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            if title == Day.long(day) { title = "" }
            text = String(text.dropFirst(first.count))
        }
        let body = text.components(separatedBy: "\n")
            .map { ["* * *", "***", "---", "⁂"].contains($0.trimmingCharacters(in: .whitespaces)) ? ornamentMark : $0 }
            .joined(separator: "\n")
            .replacingOccurrences(of: "\n\n\(ornamentMark)\n\n", with: "\n\(ornamentMark)\n")
        return store.merge(day: day, title: title, body: body, mood: mood, into: store.journal.id)
    }

    private static func firstDate(in s: String) -> String? {
        guard let r = s.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression) else { return nil }
        let key = String(s[r])
        return Day.key(Day.date(key)) == key ? key : nil
    }

    // MARK: Print & PDF

    static func attributed(_ entries: [Entry], journal: Journal) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let body = EditorFont.newYork.nsFont(12)
        let titleFont = EditorFont.newYork.nsFont(18)
        let para = NSMutableParagraphStyle()
        para.lineHeightMultiple = 1.35
        para.paragraphSpacing = 7
        para.baseWritingDirection = .natural
        let center = NSMutableParagraphStyle()
        center.alignment = .center
        center.paragraphSpacing = 10
        center.paragraphSpacingBefore = 6

        for (i, e) in entries.enumerated() {
            if i > 0 { out.append(NSAttributedString(string: "\n", attributes: [.font: body])) }
            out.append(NSAttributedString(string: Day.long(e.day).uppercased() + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: 8.5, weight: .semibold), .foregroundColor: NSColor.darkGray, .kern: 1.2,
            ]))
            let title = e.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                out.append(NSAttributedString(string: title + "\n", attributes: [.font: titleFont, .foregroundColor: NSColor.black]))
            }
            for line in e.body.components(separatedBy: "\n") {
                if line.trimmingCharacters(in: .whitespaces) == ornamentMark {
                    out.append(NSAttributedString(string: ornamentMark + "\n", attributes: [.font: body, .paragraphStyle: center, .foregroundColor: NSColor.gray]))
                } else {
                    out.append(NSAttributedString(string: line + "\n", attributes: [.font: body, .paragraphStyle: para, .foregroundColor: NSColor.black]))
                }
            }
        }
        return out
    }

    private static func printOperation(_ text: NSAttributedString, saveTo url: URL?) -> NSPrintOperation {
        let info = (NSPrintInfo.shared.copy() as! NSPrintInfo)
        info.topMargin = 60; info.bottomMargin = 60; info.leftMargin = 66; info.rightMargin = 66
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isVerticallyCentered = false
        if let url {
            info.jobDisposition = .save
            info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        }
        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        tv.textStorage?.setAttributedString(text)
        tv.isVerticallyResizable = true
        if let lm = tv.layoutManager, let tc = tv.textContainer {
            lm.ensureLayout(for: tc)
            tv.frame.size.height = lm.usedRect(for: tc).height + 20
        }
        let op = NSPrintOperation(view: tv, printInfo: info)
        op.showsPrintPanel = url == nil
        op.showsProgressPanel = true
        return op
    }

    static func printEntry(_ store: Store) {
        guard let e = store.entry, !e.isBlank else { store.flash("Nothing to print on this day"); return }
        printOperation(attributed([e], journal: store.journal), saveTo: nil).run()
    }

    static func exportPDF(_ store: Store) {
        let entries = store.entries().filter { !$0.isBlank }.sorted { $0.day < $1.day }
        guard !entries.isEmpty else { store.flash("This journal has no entries yet"); return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(safe(store.journal.name)).pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if printOperation(attributed(entries, journal: store.journal), saveTo: url).run() {
            store.flash("Saved \(url.lastPathComponent)")
        }
    }

    // MARK: Helpers

    private static func safe(_ name: String) -> String {
        let s = name.components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>")).joined(separator: "-")
        return s.isEmpty ? "Journal" : s
    }

    static func alert(_ title: String, _ text: String, style: NSAlert.Style = .warning) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.alertStyle = style
        a.runModal()
    }
}
