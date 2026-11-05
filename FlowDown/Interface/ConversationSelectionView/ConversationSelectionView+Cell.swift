//
//  ConversationSelectionView+Cell.swift
//  FlowDown
//
//  Created by 秋星桥 on 2/5/25.
//

import SnapKit
import Storage
import UIKit

extension ConversationSelectionView {
    /// One row of the sidebar: a folder, a conversation, or the placeholder
    /// shown inside an expanded empty folder.
    ///
    /// Selection, context menus and drag & drop are all driven by the table
    /// view delegates, so the cell installs no gesture recognizers of its own
    /// besides hover tracking; a cell-level tap recognizer would race the
    /// table's own selection and drag recognizers.
    class Cell: UITableViewCell {
        enum Metrics {
            static let rowHeight: CGFloat = 34
            static let horizontalInset: CGFloat = 10
            static let chevronWidth: CGFloat = 12
            static let iconSize: CGFloat = 18
            static let spacing: CGFloat = 8
            /// Leading inset of a conversation filed in a folder: one level in
            /// from the folder's own icon so the hierarchy reads at a glance.
            static let nestedInset: CGFloat = horizontalInset + chevronWidth + 6 + 10
            static let cornerRadius: CGFloat = 8
        }

        private let stack = UIStackView().with {
            $0.axis = .horizontal
            $0.spacing = 6
            $0.alignment = .center
            $0.distribution = .fill
        }

        private let chevronView = UIImageView().with {
            $0.contentMode = .center
            $0.image = UIImage(
                systemName: "chevron.right",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold),
            )
            $0.tintColor = .secondaryLabel
        }

        private let iconView = UIImageView().with {
            $0.contentMode = .scaleAspectFit
            $0.tintColor = .accent
            $0.layer.cornerRadius = 4
            $0.layer.cornerCurve = .continuous
            $0.clipsToBounds = true
        }

        private let titleLabel = UILabel().with {
            $0.font = .preferredFont(forTextStyle: .body)
            $0.textColor = .label
            $0.numberOfLines = 1
            $0.lineBreakMode = .byTruncatingTail
            $0.textAlignment = .natural
        }

        private let countLabel = UILabel().with {
            $0.font = .monospacedDigitSystemFont(
                ofSize: UIFont.preferredFont(forTextStyle: .footnote).pointSize,
                weight: .regular,
            )
            $0.textColor = .tertiaryLabel
            $0.numberOfLines = 1
            $0.textAlignment = .right
        }

        private let hoverBackgroundView = UIView().with {
            $0.backgroundColor = .label.withAlphaComponent(0.06)
            $0.layer.cornerRadius = Metrics.cornerRadius
            $0.layer.cornerCurve = .continuous
            $0.isHidden = true
        }

        private var stackLeadingConstraint: Constraint?
        private var isHovering = false {
            didSet { updateBackground() }
        }

        private(set) var item: DataIdentifier?

        override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
            super.init(style: style, reuseIdentifier: reuseIdentifier)

            backgroundColor = .clear
            separatorInset = .zero
            focusStyle = .custom

            selectedBackgroundView = UIView().with {
                $0.backgroundColor = .accent.withAlphaComponent(0.15)
                $0.layer.cornerRadius = Metrics.cornerRadius
                $0.layer.cornerCurve = .continuous
            }

            contentView.addSubview(hoverBackgroundView)
            hoverBackgroundView.snp.makeConstraints { make in
                make.edges.equalToSuperview()
            }

            stack.addArrangedSubview(chevronView)
            stack.addArrangedSubview(iconView)
            stack.addArrangedSubview(titleLabel)
            stack.addArrangedSubview(countLabel)
            stack.setCustomSpacing(Metrics.spacing, after: iconView)
            contentView.addSubview(stack)

            chevronView.snp.makeConstraints { make in
                make.width.equalTo(Metrics.chevronWidth)
                make.height.equalTo(Metrics.iconSize)
            }
            iconView.snp.makeConstraints { make in
                make.width.height.equalTo(Metrics.iconSize)
            }
            stack.snp.makeConstraints { make in
                make.top.bottom.equalToSuperview()
                make.trailing.equalToSuperview().inset(Metrics.horizontalInset)
                stackLeadingConstraint = make.leading.equalToSuperview().inset(Metrics.horizontalInset).constraint
            }

            titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
            titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            countLabel.setContentHuggingPriority(.required, for: .horizontal)
            countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

            addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hoverChanged(_:))))
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }

        override func prepareForReuse() {
            super.prepareForReuse()
            isHovering = false
        }

        override func setSelected(_ selected: Bool, animated: Bool) {
            super.setSelected(selected, animated: animated)
            updateBackground()
        }

        override func setHighlighted(_ highlighted: Bool, animated: Bool) {
            super.setHighlighted(highlighted, animated: animated)
            updateBackground()
        }

        /// Keyboard focus is drawn by `hoverBackgroundView`; the system halo
        /// renders on Catalyst as a thick square ring around the row.
        override var focusEffect: UIFocusEffect? {
            get { nil }
            set { _ = newValue }
        }

        override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
            super.didUpdateFocus(in: context, with: coordinator)
            coordinator.addCoordinatedAnimations { [weak self] in
                self?.updateBackground()
            }
        }

        @objc private func hoverChanged(_ recognizer: UIHoverGestureRecognizer) {
            switch recognizer.state {
            case .began, .changed: isHovering = true
            default: isHovering = false
            }
        }

        private func updateBackground() {
            let isInteractive: Bool = {
                if case .folderPlaceholder = item { return false }
                return item != nil
            }()
            // Selected rows already draw the selection background; hover and
            // keyboard focus share one quieter highlight for every row kind.
            let showsHover = isInteractive
                && !isSelected
                && !isHighlighted
                && (isHovering || isFocused)
            hoverBackgroundView.isHidden = !showsHover
        }

        func use(conversation conv: Conversation?, nested: Bool) {
            item = conv.map { .conversation($0.id) }
            selectionStyle = .default
            chevronView.isHidden = true
            countLabel.isHidden = true
            iconView.isHidden = false
            iconView.contentMode = .scaleAspectFit
            titleLabel.textColor = .label
            titleLabel.font = .preferredFont(forTextStyle: .body)
            stackLeadingConstraint?.update(inset: nested ? Metrics.nestedInset : Metrics.horizontalInset)
            titleLabel.text = conv?.title
            iconView.image = conv?.interfaceImage ?? UIImage(systemName: "doc.text")
            accessibilityTraits = .button
            accessibilityValue = nil
            updateBackground()
        }

        func use(folder: ConversationFolder?, expanded: Bool, count: Int) {
            let previousItem = item
            item = folder.map { .folder($0.id) }
            selectionStyle = .none
            chevronView.isHidden = false
            countLabel.isHidden = count == 0
            countLabel.text = count > 0 ? "\(count)" : nil
            iconView.isHidden = false
            iconView.contentMode = .center
            iconView.image = UIImage(
                systemName: expanded ? "folder" : "folder.fill",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .medium),
            )
            titleLabel.textColor = .label
            titleLabel.font = .preferredFont(forTextStyle: .body)
            titleLabel.text = folder?.title
            stackLeadingConstraint?.update(inset: Metrics.horizontalInset)
            accessibilityTraits = .button
            accessibilityValue = expanded
                ? String(localized: "Expanded")
                : String(localized: "Collapsed")

            let target: CGAffineTransform = expanded ? .init(rotationAngle: .pi / 2) : .identity
            if previousItem == item, chevronView.transform != target {
                UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
                    self.chevronView.transform = target
                }
            } else {
                chevronView.transform = target
            }
            updateBackground()
        }

        func usePlaceholder(folder identifier: ConversationFolder.ID) {
            item = .folderPlaceholder(identifier)
            selectionStyle = .none
            chevronView.isHidden = true
            countLabel.isHidden = true
            iconView.isHidden = true
            titleLabel.textColor = .tertiaryLabel
            titleLabel.font = .preferredFont(forTextStyle: .footnote)
            titleLabel.text = String(localized: "No Conversations")
            stackLeadingConstraint?.update(inset: Metrics.nestedInset)
            accessibilityTraits = .staticText
            accessibilityValue = nil
            updateBackground()
        }
    }
}
