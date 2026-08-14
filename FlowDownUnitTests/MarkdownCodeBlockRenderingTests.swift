@testable import FlowDown
import MarkdownParser
import MarkdownView
import Testing
import UIKit

/// Assistant replies that contain a fenced code block were painting as empty
/// space. These pin the parse → repair → size → show path that the message
/// list uses, so a fence that disappears again fails here instead of in chat.
@Suite(.serialized)
struct MarkdownCodeBlockRenderingTests {
    private let fencedSwift = """
    Here is the function:

    ```swift
    func hello() {
        print("world")
    }
    ```

    That is all.
    """

    @MainActor
    private func package(_ markdown: String, theme: MarkdownTheme = .default) -> MarkdownContent {
        MarkdownContent(repairing: MarkdownParser().parse(markdown), theme: theme)
    }

    @MainActor
    private func visibleContextViews(in markdownView: MarkdownTextView) -> [UIView] {
        markdownView.subviews.filter { view in
            view !== markdownView.textLabelView && !view.isHidden && view.bounds.width > 0
                && view.bounds.height > 0 && markdownView.bounds.intersects(view.frame)
        }
    }

    @Test
    func `parser keeps a fenced swift block after math placeholder repair`() {
        let result = MarkdownParser().parse(fencedSwift)
        #expect(result.document.contains { if case .codeBlock = $0 { true } else { false } })

        let repaired = result.documentByRepairingInlineMathPlaceholders()
        #expect(repaired.contains { if case .codeBlock = $0 { true } else { false } })
        #expect(repaired.contains { block in
            if case let .codeBlock(language, content) = block {
                return language == "swift" && content.contains("print(\"world\")")
            }
            return false
        })
    }

    @Test
    @MainActor
    func `a fenced block measures taller than the surrounding prose`() {
        let theme = MarkdownTheme.default
        let withFence = package(fencedSwift, theme: theme)
        let proseOnly = package("Here is the function:\n\nThat is all.", theme: theme)

        let fenceView = MarkdownTextView()
        fenceView.setContentImmediately(withFence, theme: theme)
        let proseView = MarkdownTextView()
        proseView.setContentImmediately(proseOnly, theme: theme)

        let fenceHeight = fenceView.boundingSize(for: 320).height
        let proseHeight = proseView.boundingSize(for: 320).height
        #expect(fenceHeight > proseHeight + 40, "fence \(fenceHeight) vs prose \(proseHeight)")
        #expect(fenceView.textLabelView.attributedText.string.contains("\u{FFFC}"))
    }

    @Test
    @MainActor
    func `an assistant row shows a visible code view for a fenced block`() {
        let theme = MarkdownTheme.default
        let content = package(fencedSwift, theme: theme)
        let row = AiMessageView()
        row.theme = theme
        row.frame = CGRect(x: 0, y: 0, width: 360, height: 480)
        row.setMarkdownPackage(content, for: "code-block-render")
        row.layoutIfNeeded()

        let height = row.markdownView.boundingSize(for: row.contentView.bounds.width).height
        row.frame = CGRect(x: 0, y: 0, width: 360, height: height + MessageListView.listRowInsets.bottom)
        row.layoutIfNeeded()

        #expect(!visibleContextViews(in: row.markdownView).isEmpty)
        #expect(row.markdownView.textLabelView.attributedText.string.contains("\u{FFFC}"))
        #expect(row.markdownView.bounds.height > 80)
    }

    @Test
    @MainActor
    func `a fence configured at zero width appears once the row is laid out`() {
        let theme = MarkdownTheme.default
        let content = package(fencedSwift, theme: theme)
        let row = AiMessageView()
        row.theme = theme
        row.setMarkdownPackage(content, for: "zero-width")
        #expect(row.markdownView.bounds.width == 0)

        let height = MarkdownTextView().with {
            $0.setContentImmediately(content, theme: theme)
        }.boundingSize(for: 360).height
        row.frame = CGRect(x: 0, y: 0, width: 360, height: height + MessageListView.listRowInsets.bottom)
        row.layoutIfNeeded()

        #expect(!visibleContextViews(in: row.markdownView).isEmpty)
    }

    @Test
    @MainActor
    func `replacing empty content with a fence without changing the row size shows the code view`() {
        let theme = MarkdownTheme.default
        let empty = package("Just prose.", theme: theme)
        let fenced = package(fencedSwift, theme: theme)
        let row = AiMessageView()
        row.theme = theme
        let height = MarkdownTextView().with {
            $0.setContentImmediately(fenced, theme: theme)
        }.boundingSize(for: 360).height
        row.frame = CGRect(x: 0, y: 0, width: 360, height: height + MessageListView.listRowInsets.bottom)
        row.layoutIfNeeded()

        row.setMarkdownPackage(empty, for: "same-size")
        row.layoutIfNeeded()
        row.setMarkdownPackage(fenced, for: "same-size")
        row.setNeedsLayout()
        row.layoutIfNeeded()

        #expect(!visibleContextViews(in: row.markdownView).isEmpty)
    }

    @Test
    @MainActor
    func `sizing pool and visible row agree on height for a fenced block`() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()
        let conversation = sdb.conversationMake { conversation in
            conversation.update(\.title, to: "Code Block Render \(UUID().uuidString.prefix(8))")
        }
        defer { ConversationManager.shared.deleteConversation(identifier: conversation.id) }
        let session = ConversationSessionManager.shared.session(for: conversation.id)
        let message = session.appendNewMessage(role: .assistant) {
            $0.update(\.document, to: fencedSwift)
        }
        let representation = MessageListView.MessageRepresentation(from: message)
        let theme = MarkdownTheme.default
        let pool = MessageListView.MarkdownSizingViewPool()
        let content = package(fencedSwift, theme: theme)

        let measured = pool.view(for: representation, theme: theme) { content }
            .boundingSize(for: 320).height
        let visible = MarkdownTextView()
        visible.setContentImmediately(content, theme: theme)
        let shown = visible.boundingSize(for: 320).height

        #expect(abs(measured - shown) < 0.5, "pool \(measured) vs visible \(shown)")
        #expect(measured > 80)
    }
}
