//
//  StackScrollController+Cards.swift
//  FlowDown
//

import ConfigurableKit
import UIKit

/// Pages build their stack as a flat run of section headers, rows, footers
/// and hairlines. With `arrangesSectionsInCards` set, the rows between two
/// section labels move into one rounded card, as Mac settings group them,
/// and the hairlines become insets between the card's rows. It runs on every
/// layout pass, so a page that rebuilds its stack is grouped again.
extension StackScrollController {
    func arrangeSectionsInCardsIfNeeded() {
        guard arrangesSectionsInCards else { return }
        let arranged = stackView.arrangedSubviews
        guard arranged.contains(where: { Self.role(of: $0) != .label && !($0 is SectionCardView) }) else {
            return
        }

        var ordered: [UIView] = []
        var rows: [UIView] = []
        func flushRows() {
            guard !rows.isEmpty else { return }
            ordered.append(SectionCardView(rows: rows))
            rows.removeAll()
        }
        for view in arranged {
            switch Self.role(of: view) {
            case .separator:
                view.removeFromSuperview()
            case .label:
                flushRows()
                Self.styleSectionLabel(view)
                ordered.append(view)
            case .row:
                if view is SectionCardView {
                    flushRows()
                    ordered.append(view)
                } else {
                    rows.append(view)
                }
            }
        }
        flushRows()

        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
        }
        for view in ordered {
            stackView.addArrangedSubview(view)
        }
    }

    /// Section titles sit large above their card, slightly in from its
    /// edge; footers explain beneath it in the same column.
    private static func styleSectionLabel(_ view: UIView) {
        guard let margin = view as? AutoLayoutMarginView else { return }
        let inset = SectionCardView.cardInset + 10
        if let header = margin.view as? ConfigurableSectionHeaderView {
            header.titleLabel.font = .preferredFont(forTextStyle: .title3).bold
            margin.viewInsets = .init(top: 24, left: inset, bottom: 10, right: inset)
        } else {
            margin.viewInsets = .init(top: 8, left: inset, bottom: 4, right: inset)
        }
    }

    private enum Role {
        case separator
        case label
        case row
    }

    private static func role(of view: UIView) -> Role {
        if view is SeparatorView {
            return .separator
        }
        let inner = (view as? AutoLayoutMarginView)?.view ?? view
        if inner is ConfigurableSectionHeaderView || inner is ConfigurableSectionFooterView {
            return .label
        }
        return .row
    }
}

/// One section's rows on a rounded card, separated by inset hairlines.
final class SectionCardView: UIView {
    static let cardInset: CGFloat = 20
    private static let rowInsets = UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)

    private let card = UIView()
    private let rowStack = UIStackView()

    init(rows: [UIView]) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        card.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? .white.withAlphaComponent(0.05)
                : .black.withAlphaComponent(0.03)
        }
        card.layer.cornerRadius = 10
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.clipsToBounds = true
        addSubview(card)
        card.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview()
            make.leading.trailing.equalToSuperview().inset(Self.cardInset)
        }

        rowStack.axis = .vertical
        rowStack.spacing = 0
        card.addSubview(rowStack)
        rowStack.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        for (index, row) in rows.enumerated() {
            if index > 0 {
                rowStack.addArrangedSubview(Hairline())
            }
            if let margin = row as? AutoLayoutMarginView {
                margin.viewInsets = .init(
                    top: min(margin.viewInsets.top, Self.rowInsets.top),
                    left: Self.rowInsets.left,
                    bottom: min(margin.viewInsets.bottom, Self.rowInsets.bottom),
                    right: Self.rowInsets.right,
                )
            }
            rowStack.addArrangedSubview(row)
        }
        updateBorder()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateBorder()
    }

    private func updateBorder() {
        let border = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? .white.withAlphaComponent(0.12)
                : .black.withAlphaComponent(0.10)
        }
        card.layer.borderColor = border.resolvedColor(with: traitCollection).cgColor
        card.layer.borderWidth = 1.0 / max(1, traitCollection.displayScale)
    }

    private final class Hairline: UIView {
        private let line = UIView()

        override init(frame: CGRect) {
            super.init(frame: frame)
            line.backgroundColor = .separator.withAlphaComponent(0.5)
            addSubview(line)
            snp.makeConstraints { make in
                make.height.equalTo(1)
            }
            line.snp.makeConstraints { make in
                make.leading.equalToSuperview().inset(SectionCardView.rowInsets.left)
                make.trailing.equalToSuperview()
                make.centerY.equalToSuperview()
                make.height.equalTo(0.5)
            }
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }
    }
}
