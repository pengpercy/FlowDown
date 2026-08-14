//
//  Created by ktiays on 2025/2/6.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import ListViewKit
import MarkdownView
import Storage
import UIKit

final class AiMessageView: MessageListRowView {
    private(set) lazy var markdownView: MarkdownTextView = .init().with {
        $0.throttleInterval = 1 / 60
    }

    private var representedMessageID: Message.ID?

    var linkTapHandler: ((LinkPayload, NSRange, CGPoint) -> Void)? {
        get { markdownView.linkHandler }
        set { markdownView.linkHandler = newValue }
    }

    var codePreviewHandler: ((String?, NSAttributedString) -> Void)? {
        get { markdownView.codePreviewHandler }
        set { markdownView.codePreviewHandler = newValue }
    }

    init() {
        super.init(frame: .zero)
        configureSubviews()
    }

    @available(*, unavailable)
    @MainActor required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureSubviews() {
        contentView.addSubview(markdownView)
    }

    /// Puts the message content on screen.
    ///
    /// The first fill for a message is applied immediately so a reused row
    /// never paints an empty fence. Later tokens on the same message stay
    /// throttled to avoid rebuilding the code view on every chunk. Layout is
    /// forced without animation: the list's apply is often inside a spring,
    /// which would otherwise interpolate the code view from a zero frame
    /// (flicker) and leave it hidden until the next width change.
    func setMarkdownPackage(_ package: MarkdownContent, for messageID: Message.ID) {
        UIView.performWithoutAnimation {
            if representedMessageID == messageID {
                markdownView.setContent(package)
            } else {
                representedMessageID = messageID
                markdownView.setContentImmediately(package, theme: theme)
            }
            if bounds.width > 0 {
                installMarkdownFrameAndRelayout()
            }
        }
        setNeedsLayout()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        representedMessageID = nil
        // Parked cells still receive CodeHighlighter notifications which trigger
        // a full document rebuild; empty their content so that rebuild is free.
        markdownView.reset()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        UIView.performWithoutAnimation {
            installMarkdownFrameAndRelayout()
        }
    }

    /// Sizes the markdown view to the row and places fenced code / table
    /// views. A fence can be built while the row still has zero width, which
    /// hides those views; if the list then keeps the same `placedFrame` it
    /// never asks for another layout, so a width-only window resize was the
    /// only thing that brought them back.
    private func installMarkdownFrameAndRelayout() {
        markdownView.trackedScrollView = nearestScrollView
        markdownView.frame = contentView.bounds
        let width = contentView.bounds.width
        guard width > 0 else { return }
        markdownView.textLabelView.preferredMaxLayoutWidth = width
        let hasFence = markdownView.textLabelView.attributedText.string.contains("\u{FFFC}")
        let hasVisibleContext = markdownView.subviews.contains { view in
            view !== markdownView.textLabelView
                && !view.isHidden
                && view.bounds.height > 1
                && markdownView.bounds.intersects(view.frame)
        }
        if hasFence, !hasVisibleContext {
            markdownView.textLabelView.reloadTextLayout()
        }
        markdownView.setNeedsLayout()
        markdownView.layoutIfNeeded()
    }
}
