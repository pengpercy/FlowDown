//
//  SectionDateHeaderView.swift
//  FlowDown
//
//  Created by 秋星桥 on 6/28/25.
//

import SnapKit
import UIKit

/// A compact sidebar section header: a small secondary title aligned with the
/// row content, plus an optional trailing accessory such as an add button.
class SectionDateHeaderView: UIView {
    static let height: CGFloat = 30

    private let titleLabel = UILabel()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = .current
        // Reads "Today" and "Yesterday" in the user's language for recent days.
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    init(accessory: UIView? = nil) {
        super.init(frame: .zero)

        titleLabel.font = .systemFont(
            ofSize: UIFont.preferredFont(forTextStyle: .caption1).pointSize,
            weight: .semibold,
        )
        titleLabel.textColor = .secondaryLabel
        titleLabel.textAlignment = .natural
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail

        addSubview(titleLabel)

        let inset = ConversationSelectionView.Cell.Metrics.horizontalInset
        if let accessory {
            addSubview(accessory)
            accessory.snp.makeConstraints { make in
                make.trailing.equalToSuperview().inset(inset - 6)
                make.centerY.equalTo(titleLabel)
                make.width.height.equalTo(24)
            }
        }
        titleLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(inset)
            make.bottom.equalToSuperview().inset(6)
            if let accessory {
                make.trailing.lessThanOrEqualTo(accessory.snp.leading).offset(-8)
            } else {
                make.trailing.lessThanOrEqualToSuperview().inset(inset)
            }
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateTitle(_ title: String) {
        titleLabel.text = title
        titleLabel.accessibilityTraits = .header
    }

    func updateTitle(date: Date) {
        updateTitle(Self.dateFormatter.string(from: date))
    }
}
