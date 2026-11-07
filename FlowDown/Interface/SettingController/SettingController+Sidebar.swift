//
//  SettingController+Sidebar.swift
//  FlowDown
//

#if targetEnvironment(macCatalyst)

    import SnapKit
    import UIKit

    extension SettingController {
        /// The Settings source list: the panes in a few groups under the
        /// window buttons, with the app version pinned underneath.
        final class SidebarController: UIViewController, UICollectionViewDelegate {
            var onSelect: ((Pane) -> Void)?

            /// Panes grouped as a Mac settings sidebar spaces them.
            private static let groups: [[Pane]] = [
                [.general, .inference, .model, .tools],
                [.memory, .dataControl, .permission],
                [.support],
            ]

            private let separator = UIView().with {
                $0.backgroundColor = SeparatorView.color
            }

            private lazy var collectionView: UICollectionView = {
                var configuration = UICollectionLayoutListConfiguration(appearance: .sidebar)
                configuration.showsSeparators = false
                configuration.backgroundColor = .clear
                let layout = UICollectionViewCompositionalLayout { _, environment in
                    let section = NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: environment)
                    section.contentInsets.bottom = 14
                    return section
                }
                return UICollectionView(frame: .zero, collectionViewLayout: layout)
            }()

            private lazy var dataSource: UICollectionViewDiffableDataSource<Int, Pane> = {
                let registration = UICollectionView.CellRegistration<UICollectionViewListCell, Pane> { cell, _, pane in
                    cell.configurationUpdateHandler = { cell, state in
                        Self.configure(cell, for: pane, state: state)
                    }
                }
                return .init(collectionView: collectionView) { collectionView, indexPath, pane in
                    collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: pane)
                }
            }()

            private let versionLabel = UILabel().with {
                let version = String(AnchorVersion.version)
                let build = String(AnchorVersion.build)
                $0.text = String(format: String(localized: "Version %@ (%@)"), version, build)
                $0.font = .preferredFont(forTextStyle: .caption2)
                $0.textColor = .tertiaryLabel
                $0.textAlignment = .center
                $0.numberOfLines = 1
            }

            private var pendingSelection: Pane?

            override func viewDidLoad() {
                super.viewDidLoad()
                view.backgroundColor = .secondarySystemBackground

                collectionView.backgroundColor = .clear
                collectionView.delegate = self
                collectionView.allowsMultipleSelection = false
                collectionView.contentInsetAdjustmentBehavior = .never
                collectionView.contentInset = .init(top: 0, left: 0, bottom: 8, right: 0)
                view.addSubview(collectionView)
                view.addSubview(versionLabel)
                view.addSubview(separator)

                versionLabel.snp.makeConstraints { make in
                    make.leading.trailing.equalToSuperview().inset(12)
                    make.bottom.equalToSuperview().inset(12)
                }
                collectionView.snp.makeConstraints { make in
                    make.top.equalToSuperview().offset(SettingController.dragBandHeight)
                    make.leading.trailing.equalToSuperview()
                    make.bottom.equalTo(versionLabel.snp.top).offset(-8)
                }
                // Hairline between the pane list and the pane.
                separator.snp.makeConstraints { make in
                    make.top.bottom.trailing.equalToSuperview()
                    make.width.equalTo(1.0 / max(1, traitCollection.displayScale))
                }

                var snapshot = NSDiffableDataSourceSnapshot<Int, Pane>()
                for (index, group) in Self.groups.enumerated() {
                    snapshot.appendSections([index])
                    snapshot.appendItems(group, toSection: index)
                }
                dataSource.apply(snapshot, animatingDifferences: false)

                if let pendingSelection {
                    select(pendingSelection)
                }
            }

            override func viewWillAppear(_ animated: Bool) {
                super.viewWillAppear(animated)
                navigationController?.setNavigationBarHidden(true, animated: false)
            }

            /// Whether a click at `point` lands on the list's empty space or
            /// the version label, where it can drag the window instead.
            func isEmptySpace(at point: CGPoint) -> Bool {
                let inList = collectionView.convert(point, from: view)
                guard collectionView.bounds.contains(inList) else { return true }
                return collectionView.indexPathForItem(at: inList) == nil
            }

            func select(_ pane: Pane) {
                guard isViewLoaded, let indexPath = dataSource.indexPath(for: pane) else {
                    pendingSelection = pane
                    return
                }
                pendingSelection = nil
                guard collectionView.indexPathsForSelectedItems != [indexPath] else { return }
                collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
            }

            func collectionView(_: UICollectionView, didSelectItemAt indexPath: IndexPath) {
                guard let pane = dataSource.itemIdentifier(for: indexPath) else { return }
                onSelect?(pane)
            }

            func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
                // Clicking the open pane again keeps it as it is.
                collectionView.indexPathsForSelectedItems?.contains(indexPath) != true
            }

            // MARK: - Row Appearance

            /// A Mac source-list row: the pane's glyph in the app's accent
            /// color, and a rounded, inset selection filled with it.
            private static func configure(_ cell: UICollectionViewCell, for pane: Pane, state: UICellConfigurationState) {
                let selected = state.isSelected || state.isHighlighted

                var content = UIListContentConfiguration.sidebarCell()
                content.text = pane.title
                content.textProperties.font = .preferredFont(forTextStyle: .body)
                content.textProperties.color = selected ? .white : .label
                content.image = UIImage(systemName: pane.icon)
                content.imageProperties.tintColor = selected ? .white : .accent
                content.imageProperties.preferredSymbolConfiguration = .init(textStyle: .body, scale: .medium)
                content.imageProperties.reservedLayoutSize = .init(width: 22, height: 22)
                content.imageToTextPadding = 8
                content.directionalLayoutMargins = .init(top: 6, leading: 18, bottom: 6, trailing: 18)
                cell.contentConfiguration = content

                var background = UIBackgroundConfiguration.clear()
                background.cornerRadius = 8
                background.backgroundInsets = .init(top: 1, leading: 10, bottom: 1, trailing: 10)
                background.backgroundColor = selected ? .accent : .clear
                cell.backgroundConfiguration = background
            }
        }
    }

#endif
