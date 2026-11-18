import SwiftUI
import DesignSystem

/// Keep the streaming run in one Text. Split fenced code into copyable cards once the turn settles.
struct AskReply: View {
    let text: String
    let streaming: Bool
    let copy: (String) -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @LocalState private var dimCaret = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.sm) {
            if streaming {
                Text(inline(text) + AttributedString(" ▍", attributes: AttributeContainer().foregroundColor(.secondary.opacity(dimCaret ? 0.35 : 0.9))))
                    .animation(DS.Motion.gentle(reduced), value: text.count)
                    .onAppear {
                        if !reduced && !DS.rendersOffscreen {
                            withAnimation(DS.Motion.gentle(false).speed(0.45).repeatForever(autoreverses: true)) { dimCaret = true }
                        }
                    }
            } else {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    if block.isCode {
                        VStack(alignment: .leading, spacing: DS.xs) {
                            HStack { Text(block.language.isEmpty ? "Code" : block.language).font(DS.caption); Spacer()
                                IconButton("copy", label: "Copy code", size: DS.xl) { copy(block.content) }
                            }.foregroundStyle(.secondary)
                            ScrollView(.horizontal) { Text(verbatim: block.content).font(DS.mono).fixedSize() }
                        }.padding(DS.sm).background(DS.card(scheme), in: RoundedRectangle(cornerRadius: DS.controlRadius))
                    } else { Text(inline(block.content)) }
                }
            }
        }
        .font(DS.body).lineSpacing(DS.lineSpacing / 2).textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inline(_ value: String) -> AttributedString {
        let lines = value.components(separatedBy: "\n").map { $0.hasPrefix("- ") || $0.hasPrefix("* ") ? "• " + $0.dropFirst(2) : $0 }
        let source = lines.joined(separator: "\n")
        var result = (try? AttributedString(markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(source)
        for run in result.runs where run.inlinePresentationIntent?.contains(.code) == true {
            result[run.range].font = DS.mono
            result[run.range].backgroundColor = DS.card(scheme)
        }
        return result
    }
    private struct Block { let isCode: Bool; let language: String; let content: String }
    private var blocks: [Block] {
        var result: [Block] = [], lines: [String] = [], code = false, language = ""
        func flush() {
            let content = lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !content.isEmpty { result.append(Block(isCode: code, language: language, content: content)) }
            lines.removeAll()
        }
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("```") { flush(); code.toggle(); language = String(line.dropFirst(3)) }
            else { lines.append(line) }
        }
        flush()
        return result
    }
}
