//
//  ConversationSelectionView+Cell.swift
//  FlowDown
//
//  Created by 秋星桥 on 2/5/25.
//

import AlertController
import SnapKit
import Storage
import UIKit

extension ConversationSelectionView {
    class Cell: UITableViewCell, UIContextMenuInteractionDelegate, UIGestureRecognizerDelegate {
        let stack = UIStackView().with {
            $0.axis = .horizontal
            $0.spacing = 12
            $0.alignment = .center
            $0.distribution = .fill
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        let iconView = UIImageView().with {
            $0.contentMode = .scaleAspectFit
            $0.image = UIImage(systemName: "doc.text")
            $0.tintColor = .accent
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.snp.makeConstraints { make in
                make.width.height.equalTo(28)
            }
        }

        let titleLabel = UILabel().with {
            $0.font = .preferredFont(forTextStyle: .body)
            $0.textColor = .label
            $0.numberOfLines = 1
            $0.textAlignment = .left
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        let countLabel = UILabel().with {
            $0.font = .preferredFont(forTextStyle: .caption1)
            $0.textColor = .tertiaryLabel
            $0.numberOfLines = 1
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        let chevronView = UIImageView().with {
            $0.contentMode = .scaleAspectFit
            $0.image = UIImage(
                systemName: "chevron.right",
                withConfiguration: UIImage.SymbolConfiguration(font: .preferredFont(forTextStyle: .caption1), scale: .small),
            )
            $0.tintColor = .tertiaryLabel
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        private var stackLeadingConstraint: Constraint?

        override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
            super.init(style: style, reuseIdentifier: reuseIdentifier)
            stack.addArrangedSubview(iconView)
            stack.addArrangedSubview(titleLabel)
            stack.addArrangedSubview(countLabel)
            stack.addArrangedSubview(chevronView)
            contentView.addSubview(stack)

            titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
            titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            backgroundColor = .clear
            separatorInset = .zero

            let selectionColor = UIView().with {
                $0.backgroundColor = .accent.withAlphaComponent(0.15)
                $0.layer.cornerRadius = 12
            }
            selectedBackgroundView = selectionColor

            stack.snp.makeConstraints { make in
                make.top.bottom.equalToSuperview().inset(16)
                make.right.equalToSuperview().inset(24)
                stackLeadingConstraint = make.left.equalToSuperview().inset(24).constraint
            }

            contentView.isUserInteractionEnabled = true
            let tap = UITapGestureRecognizer(target: self, action: #selector(didSelectCell))
            tap.delegate = self
            contentView.addGestureRecognizer(tap)
            #if targetEnvironment(macCatalyst)
                contentView.backgroundColor = .accent.withAlphaComponent(0.001)
            #endif

            let contextMenuInteraction = UIContextMenuInteraction(delegate: self)
            contentView.addInteraction(contextMenuInteraction)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }

        private var item: DataIdentifier?

        func use(conversation conv: Conversation?, indented: Bool = false) {
            item = conv.map { .conversation($0.id) }
            chevronView.isHidden = true
            countLabel.isHidden = true
            stackLeadingConstraint?.update(offset: indented ? 52 : 24)
            guard let conv else {
                titleLabel.text = nil
                iconView.image = UIImage(systemName: "doc.text")
                return
            }
            titleLabel.text = conv.title
            iconView.image = conv.interfaceImage
        }

        func use(folder: ConversationFolder?, expanded: Bool, count: Int) {
            let previousItem = item
            item = folder.map { .folder($0.id) }
            stackLeadingConstraint?.update(offset: 24)
            chevronView.isHidden = false
            countLabel.isHidden = false
            countLabel.text = count > 0 ? "\(count)" : nil
            titleLabel.text = folder?.title
            iconView.image = UIImage(systemName: "folder.fill")

            let target: CGAffineTransform = expanded ? .init(rotationAngle: .pi / 2) : .identity
            let isSameFolder = previousItem == item
            if isSameFolder, chevronView.transform != target {
                UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut]) {
                    self.chevronView.transform = target
                }
            } else {
                chevronView.transform = target
            }
        }

        func contextMenuInteraction(
            _: UIContextMenuInteraction,
            configurationForMenuAtLocation _: CGPoint,
        ) -> UIContextMenuConfiguration? {
            guard let item else { return nil }

            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
                guard let self else { return nil }
                switch item {
                case let .conversation(identifier):
                    return ConversationManager.shared.menu(
                        forConversation: identifier,
                        view: self,
                    )
                case let .folder(identifier):
                    return ConversationManager.shared.folderMenu(
                        forFolder: identifier,
                        view: self,
                    )
                }
            }
        }

        @objc func didSelectCell() {
            guard case let .conversation(id) = item else { return }
            Logger.ui.debugFile("did select conversation cell: \(id)")
            ChatSelection.shared.select(id, options: [.collapseSidebar])
        }

        override func gestureRecognizerShouldBegin(_: UIGestureRecognizer) -> Bool {
            // Folder rows must not be intercepted here: the tap has to reach
            // the table view so the delegate can toggle the folder.
            if case .folder = item { return false }
            return true
        }
    }
}
