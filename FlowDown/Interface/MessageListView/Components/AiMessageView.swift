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

    var codeExpandedBlocks: Set<Int> = [] {
        didSet { markdownView.expandedCodeBlocks = codeExpandedBlocks }
    }
    var codeBlockExpansionHandler: ((_ blockIndex: Int, _ isExpanded: Bool) -> Void)?

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
        markdownView.codeBlockExpansionDidChange = { [weak self] blockIndex, isExpanded in
            self?.codeBlockExpansionHandler?(blockIndex, isExpanded)
        }
        contentView.addSubview(markdownView)
    }

    /// Puts the message content on screen. The first fill for a message is
    /// applied synchronously so a freshly (re)used row never renders blank;
    /// subsequent updates to the same message stream through the throttled
    /// path and update the visible content in place.
    func setMarkdownPackage(_ package: MarkdownContent, for messageID: Message.ID) {
        if representedMessageID == messageID {
            markdownView.setContent(package)
        } else {
            representedMessageID = messageID
            markdownView.setContentImmediately(package)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        representedMessageID = nil
        codeExpandedBlocks = []
        codeBlockExpansionHandler = nil
        // Parked cells still receive CodeHighlighter notifications which trigger
        // a full document rebuild; empty their content so that rebuild is free.
        markdownView.reset()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        markdownView.frame = contentView.bounds
        markdownView.trackedScrollView = nearestScrollView
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // A conversation opened for the first time installs its rows while the
        // hierarchy is not attached to a window yet. Force one real layout pass
        // once it is, so fenced-code views placed against the detached tree are
        // re-synced instead of waiting for a window resize.
        guard window != nil else { return }
        setNeedsLayout()
        layoutIfNeeded()
    }
}
