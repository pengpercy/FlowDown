//
//  SettingController+Sidebar.swift
//  FlowDown
//

#if targetEnvironment(macCatalyst)

    import SnapKit
    import UIKit

    extension SettingController {
        /// The Settings source list: one row per pane under the close
        /// button, with the app version pinned underneath.
        final class SidebarController: UIViewController, UICollectionViewDelegate {
            var onSelect: ((Pane) -> Void)?
            var onClose: (() -> Void)?

            private let closeButton: ImageCircleButton = if #available(iOS 26, macCatalyst 26, *) {
                .init(name: "xmark", distinctStyle: .none, inset: 8)
            } else {
                .init(name: "xmark", distinctStyle: .border, inset: 8)
            }

            private let separator = UIView().with {
                $0.backgroundColor = SeparatorView.color
            }

            private lazy var collectionView: UICollectionView = {
                var configuration = UICollectionLayoutListConfiguration(appearance: .sidebar)
                configuration.showsSeparators = false
                configuration.backgroundColor = .clear
                let layout = UICollectionViewCompositionalLayout.list(using: configuration)
                return UICollectionView(frame: .zero, collectionViewLayout: layout)
            }()

            private lazy var dataSource: UICollectionViewDiffableDataSource<Int, Pane> = {
                let registration = UICollectionView.CellRegistration<UICollectionViewListCell, Pane> { cell, _, pane in
                    var content = UIListContentConfiguration.sidebarCell()
                    content.text = pane.title
                    content.image = UIImage(systemName: pane.icon)
                    content.imageProperties.tintColor = .accent
                    cell.contentConfiguration = content
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

                closeButton.actionBlock = { [weak self] in
                    self?.onClose?()
                }

                collectionView.backgroundColor = .clear
                collectionView.delegate = self
                collectionView.allowsMultipleSelection = false
                collectionView.contentInsetAdjustmentBehavior = .never
                collectionView.contentInset = .init(top: 4, left: 0, bottom: 8, right: 0)
                view.addSubview(closeButton)
                view.addSubview(collectionView)
                view.addSubview(versionLabel)
                view.addSubview(separator)

                closeButton.snp.makeConstraints { make in
                    make.top.leading.equalToSuperview().inset(12)
                    make.width.height.equalTo(28)
                }
                versionLabel.snp.makeConstraints { make in
                    make.leading.trailing.equalToSuperview().inset(12)
                    make.bottom.equalToSuperview().inset(12)
                }
                collectionView.snp.makeConstraints { make in
                    make.top.equalTo(closeButton.snp.bottom).offset(8)
                    make.leading.trailing.equalToSuperview()
                    make.bottom.equalTo(versionLabel.snp.top).offset(-8)
                }
                // Hairline between the pane list and the pane.
                separator.snp.makeConstraints { make in
                    make.top.bottom.trailing.equalToSuperview()
                    make.width.equalTo(1.0 / max(1, traitCollection.displayScale))
                }

                var snapshot = NSDiffableDataSourceSnapshot<Int, Pane>()
                snapshot.appendSections([0])
                snapshot.appendItems(Pane.allCases, toSection: 0)
                dataSource.apply(snapshot, animatingDifferences: false)

                if let pendingSelection {
                    select(pendingSelection)
                }
            }

            override func viewWillAppear(_ animated: Bool) {
                super.viewWillAppear(animated)
                navigationController?.setNavigationBarHidden(true, animated: false)
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
        }
    }

#endif
