import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

struct PromptSet: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let questions: [String]
}

enum Prompts {
    static let builtIn: [PromptSet] = [
        PromptSet(id: "morning", name: "Morning", icon: "sunrise", questions: [
            "How are you feeling as the day begins?",
            "What are three things you're grateful for?",
            "What would make today a good day?",
            "What is the one thing that matters most today?",
            "What are you ready to let go of?",
        ]),
        PromptSet(id: "evening", name: "Evening", icon: "moon.stars", questions: [
            "What went well today?",
            "What did you learn?",
            "What drained you, and what gave you energy?",
            "Who or what are you grateful for today?",
            "What will you do differently tomorrow?",
        ]),
        PromptSet(id: "stoic", name: "Stoic review", icon: "building.columns", questions: [
            "What was within my control today, and what wasn't?",
            "Where did I act from fear, anger or habit?",
            "What did I do well, by my own values?",
            "What could I have done better?",
            "What will I practise tomorrow?",
        ]),
        PromptSet(id: "reflection", name: "Daily reflection", icon: "leaf", questions: [
            "What's on your mind right now?",
            "What moment from today do you want to remember?",
            "What are you avoiding, and why?",
            "What do you need more of this week?",
        ]),
    ]

    static func set(id: String?, custom: [String]) -> PromptSet {
        if id == "custom" {
            return PromptSet(id: "custom", name: "My questions", icon: "person.crop.circle", questions: custom)
        }
        if let id, let s = builtIn.first(where: { $0.id == id }) { return s }
        let hour = Calendar.current.component(.hour, from: Date())
        return hour < 15 ? builtIn[0] : builtIn[1]
    }

    static func all(custom: [String]) -> [PromptSet] {
        custom.isEmpty ? builtIn : builtIn + [set(id: "custom", custom: custom)]
    }
}

/// Uses Apple's on-device model (macOS 26 with Apple Intelligence) to see which questions the writing answers.
/// Nothing leaves the Mac. Returns nil when the model isn't available.
enum PromptChecker {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) { return SystemLanguageModel.default.isAvailable }
        #endif
        return false
    }

    static var unavailableReason: String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return "Apple Intelligence is ready."
            case .unavailable(.deviceNotEligible): return "This Mac doesn't support Apple Intelligence."
            case .unavailable(.appleIntelligenceNotEnabled): return "Turn on Apple Intelligence in System Settings to tick questions automatically."
            case .unavailable(.modelNotReady): return "Apple Intelligence is still downloading."
            default: return "Apple Intelligence isn't available right now."
            }
        }
        #endif
        return "Automatic ticking needs macOS 26 with Apple Intelligence."
    }

    static func answered(questions: [String], writing: String) async -> [Int]? {
        let text = writing.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !questions.isEmpty, text.count > 20 else { return [] }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard SystemLanguageModel.default.isAvailable else { return nil }
            let session = LanguageModelSession(instructions: """
                You check which journaling questions a piece of personal writing has already answered. \
                A question counts as answered only if the writing clearly responds to it. \
                Reply with only the numbers of the answered questions separated by commas, or NONE.
                """)
            let numbered = questions.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
            let prompt = "Questions:\n\(numbered)\n\nWriting:\n\(String(text.suffix(6000)))"
            do {
                let reply = try await session.respond(to: prompt).content
                let nums = reply.split { !$0.isNumber }.compactMap { Int($0) }
                return nums.map { $0 - 1 }.filter { questions.indices.contains($0) }
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }
}

/// The prompt card under the editor: questions for the current sitting, ticked by hand or automatically.
struct PromptCard: View {
    @EnvironmentObject var store: Store
    @AppStorage(Pref.aiChecks) private var aiChecks = true
    let palette: Palette

    var body: some View {
        let entry = store.entry
        let set = Prompts.set(id: entry?.promptSet, custom: store.customPrompts)
        let sections = Entry.sections(of: store.bodyText)
        let section = sections.count - 1
        let checked = Set(entry?.checked[String(section)] ?? [])

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Menu {
                    ForEach(Prompts.all(custom: store.customPrompts)) { s in
                        Button { store.setPromptSet(s.id) } label: { Label(s.name, systemImage: s.icon) }
                    }
                } label: {
                    Label(set.name, systemImage: set.icon).font(.system(size: 12, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                if set.id == "morning" || set.id == "evening" {
                    Button(set.id == "morning" ? "Switch to evening" : "Switch to morning") {
                        store.setPromptSet(set.id == "morning" ? "evening" : "morning")
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                }
                Spacer()
                if sections.count > 1 {
                    Text("Sitting \(sections.count)").font(.system(size: 11)).foregroundStyle(palette.muted)
                }
                Text("\(checked.count)/\(set.questions.count)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(palette.muted)
                Button { store.showPrompts = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundStyle(palette.muted)
                    .help("Hide prompts (⇧⌘P)")
            }

            if set.questions.isEmpty {
                Text("Add your own questions in Settings › Prompts.")
                    .font(.system(size: 12)).foregroundStyle(palette.muted)
            }

            ForEach(Array(set.questions.enumerated()), id: \.offset) { i, q in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Button { store.toggleCheck(i, section: section) } label: {
                        Image(systemName: checked.contains(i) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 14))
                            .foregroundStyle(checked.contains(i) ? palette.tint : palette.muted)
                    }
                    .buttonStyle(.plain)
                    Text(q)
                        .font(.system(size: 13.5, design: .serif))
                        .foregroundStyle(checked.contains(i) ? palette.muted : palette.ink)
                        .strikethrough(checked.contains(i), color: palette.muted.opacity(0.6))
                        .onTapGesture(count: 2) { store.insertQuestion(q) }
                    Spacer(minLength: 0)
                    Button { store.insertQuestion(q) } label: { Image(systemName: "text.insert") }
                        .buttonStyle(.plain).foregroundStyle(palette.muted)
                        .help("Write this question into the entry")
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(palette.tint.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.tint.opacity(0.18)))
        .task(id: "\(store.day)|\(set.id)|\(sections.last ?? "")") {
            guard aiChecks, PromptChecker.isAvailable else { return }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled, let current = sections.last else { return }
            if let found = await PromptChecker.answered(questions: set.questions, writing: current), !Task.isCancelled {
                await MainActor.run { store.addChecks(found, section: section) }
            }
        }
    }
}
