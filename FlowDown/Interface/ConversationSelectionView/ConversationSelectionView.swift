//
//  ConversationSelectionView.swift
//  FlowDown
//
//  Created by 秋星桥 on 2/3/25.
//

import Combine
import Foundation
import Storage
import UIKit

private class GroundedTableView: UITableView {
    @objc var allowsHeaderViewsToFloat: Bool {
        false
    }

    @objc var allowsFooterViewsToFloat: Bool {
        false
    }
}

class ConversationSelectionView: UIView {
    let tableView: UITableView
    let dataSource: DataSource

    var cancellables: Set<AnyCancellable> = []

    /// The selection the list last scrolled to, so that a list update showing
    /// the same selection again leaves the user's scroll position alone.
    private var lastRevealedSelection: Conversation.ID?

    /// Drawn behind the rows that will receive the current drop.
    let dropHighlightView = UIView().with {
        $0.backgroundColor = .accent.withAlphaComponent(0.1)
        $0.layer.borderColor = UIColor.accent.withAlphaComponent(0.6).cgColor
        $0.layer.borderWidth = 1.5
        $0.layer.cornerRadius = Cell.Metrics.cornerRadius
        $0.layer.cornerCurve = .continuous
        $0.layer.zPosition = -1
        $0.isUserInteractionEnabled = false
        $0.alpha = 0
    }

    var currentDropTarget: DropTarget?

    enum DataIdentifier: Hashable {
        case conversation(Conversation.ID)
        case folder(ConversationFolder.ID)
        /// Shown inside an expanded folder that holds no conversations.
        case folderPlaceholder(ConversationFolder.ID)
        /// Ends the recent list while older conversations are hidden.
        case showMore
    }

    /// Top to bottom: favorites, the most recent unfiled conversations, then
    /// the folders.
    enum SectionIdentifier: Hashable {
        case favorites
        case recent
        /// Header-only section carrying the "Folders" title and add button.
        case folders
        case folder(ConversationFolder.ID)
    }

    /// How many recent conversations show before "Show More", and how many
    /// more each click on it reveals.
    static let recentPageSize = 10

    /// Recent conversations currently shown. Grows with "Show More", and to
    /// reach a selected conversation that would otherwise stay hidden.
    var recentLimit = ConversationSelectionView.recentPageSize

    typealias DataSource = UITableViewDiffableDataSource<SectionIdentifier, DataIdentifier>
    typealias Snapshot = NSDiffableDataSourceSnapshot<SectionIdentifier, DataIdentifier>

    private static let expandedFolderIdsDefaultsKey = "ConversationSelectionView.expandedFolderIds"

    var expandedFolderIds: Set<ConversationFolder.ID> = [] {
        didSet {
            UserDefaults.standard.set(Array(expandedFolderIds), forKey: Self.expandedFolderIdsDefaultsKey)
        }
    }

    init() {
        tableView = GroundedTableView(frame: .zero, style: .plain)
        tableView.register(Cell.self, forCellReuseIdentifier: "Cell")

        dataSource = .init(tableView: tableView) { tableView, indexPath, itemIdentifier in
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath) as! Cell
            let manager = ConversationManager.shared
            switch itemIdentifier {
            case let .conversation(identifier):
                let conversation = manager.conversation(identifier: identifier)
                let isFiled = manager.folderMemberships.value[identifier] != nil
                cell.use(conversation: conversation, nested: isFiled)
            case let .folder(identifier):
                let count = manager.folderMemberships.value.values.filter { $0 == identifier }.count
                cell.use(
                    folder: manager.folders.value.first { $0.id == identifier },
                    expanded: (tableView.delegate as? ConversationSelectionView)?.expandedFolderIds.contains(identifier) ?? false,
                    count: count,
                )
            case let .folderPlaceholder(identifier):
                cell.usePlaceholder(folder: identifier)
            case .showMore:
                cell.useShowMore()
            }
            return cell
        }
        dataSource.defaultRowAnimation = .fade

        super.init(frame: .zero)

        isUserInteractionEnabled = true

        addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        tableView.addSubview(dropHighlightView)

        tableView.delegate = self
        tableView.dragDelegate = self
        tableView.dropDelegate = self
        tableView.dragInteractionEnabled = true
        tableView.isSpringLoaded = true
        tableView.separatorStyle = .none
        tableView.separatorInset = .zero
        tableView.separatorColor = .clear
        tableView.rowHeight = Cell.Metrics.rowHeight
        tableView.estimatedRowHeight = Cell.Metrics.rowHeight
        tableView.contentInset = .zero
        tableView.allowsMultipleSelection = false
        tableView.selectionFollowsFocus = true
        tableView.backgroundColor = .clear
        tableView.showsVerticalScrollIndicator = false
        tableView.showsHorizontalScrollIndicator = false
        tableView.sectionHeaderTopPadding = 0
        tableView.sectionHeaderHeight = SectionHeaderView.height
        tableView.estimatedSectionHeaderHeight = SectionHeaderView.height
        tableView.sectionFooterHeight = 0
        tableView.estimatedSectionFooterHeight = 0

        if let persisted = UserDefaults.standard.array(forKey: Self.expandedFolderIdsDefaultsKey) as? [String] {
            expandedFolderIds = Set(persisted)
        }

        updateDataSource()

        Publishers.CombineLatest4(
            ConversationManager.shared.conversations,
            ChatSelection.shared.selection,
            ConversationManager.shared.folders,
            ConversationManager.shared.folderMemberships,
        )
        .debounce(for: .milliseconds(16), scheduler: DispatchQueue.main)
        .ensureMainThread()
        .sink { [weak self] _, selection, _, _ in
            guard let self else { return }
            updateDataSource()
            let identifier = selection.identifier
            let optionDescription: String = {
                switch selection {
                case .none:
                    return "none"
                case let .conversation(_, options):
                    var components: [String] = []
                    if options.contains(.collapseSidebar) { components.append("collapseSidebar") }
                    if options.contains(.focusEditor) { components.append("focusEditor") }
                    return components.isEmpty ? "none" : components.joined(separator: ",")
                }
            }()
            Logger.ui.debugFile("ConversationSelectionView received global selection: \(identifier ?? "nil") options: \(optionDescription)")
            reconcileSelection(identifier)
        }
        .store(in: &cancellables)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    private func reconcileSelection(_ identifier: Conversation.ID?) {
        for indexPath in tableView.indexPathsForSelectedRows ?? [] {
            tableView.deselectRow(at: indexPath, animated: false)
        }

        // A new selection filed in a collapsed folder (a search result, a
        // conversation created inside the folder) opens that folder so the
        // row is visible. The same selection is left alone, so collapsing
        // the folder that holds the open chat keeps it collapsed.
        if let identifier,
           identifier != lastRevealedSelection,
           dataSource.indexPath(for: .conversation(identifier)) == nil,
           ConversationManager.shared.conversation(identifier: identifier) != nil
        {
            if let folderId = ConversationManager.shared.folderMemberships.value[identifier] {
                if !expandedFolderIds.contains(folderId) { expandFolder(folderId) }
            } else {
                // An older conversation past "Show More" (from search or the
                // previous/next commands): reveal pages until it shows.
                revealRecent(identifier)
            }
        }

        if let identifier,
           let indexPath = dataSource.indexPath(for: .conversation(identifier))
        {
            let visible = tableView.indexPathsForVisibleRows?.contains(indexPath) ?? false
            // Every list update runs this again for the same selection.
            // Only a new selection is worth scrolling to, otherwise each
            // update pulls the list back from wherever the user scrolled.
            let shouldReveal = !visible && identifier != lastRevealedSelection
            lastRevealedSelection = identifier
            tableView.selectRow(
                at: indexPath,
                animated: false,
                scrollPosition: shouldReveal ? .middle : .none,
            )
            return
        }

        // The selection still exists but sits inside a folder the user
        // collapsed; highlighting another row would misreport what is open.
        if let identifier,
           ConversationManager.shared.conversation(identifier: identifier) != nil,
           ConversationManager.shared.folderMemberships.value[identifier] != nil
        {
            return
        }

        let displayed = displayedConversationIdentifiers()
        guard let firstConversation = displayed.first,
              let indexPath = dataSource.indexPath(for: .conversation(firstConversation))
        else { return }
        let visible = tableView.indexPathsForVisibleRows?.contains(indexPath) ?? false
        tableView.selectRow(
            at: indexPath,
            animated: false,
            scrollPosition: visible ? .none : .middle,
        )
        // The open conversation can leave the list without going
        // through a local delete, for example when another device
        // removes it. Move the chat to the row highlighted above, or
        // it keeps showing and saving into a conversation that no
        // longer appears anywhere.
        if let replacement = ConversationSelectionView.replacementSelection(
            for: identifier,
            displayed: displayed,
            isAvailable: { ConversationManager.shared.conversation(identifier: $0) != nil },
        ) {
            ChatSelection.shared.select(replacement)
        }
    }

    /// Conversations in the order the rows show them.
    func displayedConversationIdentifiers() -> [Conversation.ID] {
        dataSource.snapshot().itemIdentifiers.compactMap {
            guard case let .conversation(identifier) = $0 else { return nil }
            return identifier
        }
    }

    func updateDataSource() {
        let list = ConversationManager.shared.conversations.value.values
        guard !list.isEmpty else {
            _ = ConversationManager.shared.initialConversation()
            return
        }

        var snapshot = Snapshot()

        let memberships = ConversationManager.shared.folderMemberships.value
        let folders = ConversationManager.shared.folders.value
        expandedFolderIds.formIntersection(folders.map(\.id))
        let unfiled = list.filter { memberships[$0.id] == nil }

        let favorited = unfiled.filter(\.isFavorite)
        if !favorited.isEmpty {
            snapshot.appendSections([.favorites])
            snapshot.appendItems(favorited.map { .conversation($0.id) }, toSection: .favorites)
        }

        // Newest first, as storage already orders them.
        let recent = unfiled.filter { !$0.isFavorite }
        if !recent.isEmpty {
            snapshot.appendSections([.recent])
            snapshot.appendItems(
                recent.prefix(recentLimit).map { .conversation($0.id) },
                toSection: .recent,
            )
            if recent.count > recentLimit {
                snapshot.appendItems([.showMore], toSection: .recent)
            }
        }

        snapshot.appendSections([.folders])
        for folder in folders {
            let section = SectionIdentifier.folder(folder.id)
            snapshot.appendSections([section])
            snapshot.appendItems([.folder(folder.id)], toSection: section)
            guard expandedFolderIds.contains(folder.id) else { continue }
            let members = list.filter { memberships[$0.id] == folder.id }
            if members.isEmpty {
                snapshot.appendItems([.folderPlaceholder(folder.id)], toSection: section)
            } else {
                snapshot.appendItems(members.map { .conversation($0.id) }, toSection: section)
            }
        }

        dataSource.apply(snapshot, animatingDifferences: true)

        Task { @MainActor [self] in
            var snapshot = dataSource.snapshot()
            let visibleRows = tableView.indexPathsForVisibleRows ?? []
            let visibleItemIdentifiers = visibleRows
                .compactMap { dataSource.itemIdentifier(for: $0) }
            snapshot.reconfigureItems(visibleItemIdentifiers)
            dataSource.apply(snapshot, animatingDifferences: true)
        }
    }

    func toggleFolder(_ identifier: ConversationFolder.ID) {
        if expandedFolderIds.contains(identifier) {
            expandedFolderIds.remove(identifier)
        } else {
            expandedFolderIds.insert(identifier)
        }
        updateDataSource()
        // Reconfigure the folder row so its chevron reflects the new state;
        // the cell animates the rotation itself.
        var snapshot = dataSource.snapshot()
        guard snapshot.indexOfItem(.folder(identifier)) != nil else { return }
        snapshot.reconfigureItems([.folder(identifier)])
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    func expandFolder(_ identifier: ConversationFolder.ID) {
        guard !expandedFolderIds.contains(identifier) else { return }
        toggleFolder(identifier)
    }

    func showMoreRecent() {
        recentLimit += Self.recentPageSize
        updateDataSource()
    }

    /// Grows the recent list by whole pages until `identifier` is in it.
    private func revealRecent(_ identifier: Conversation.ID) {
        let recent = ConversationManager.shared.conversations.value.values.filter {
            !$0.isFavorite && ConversationManager.shared.folderMemberships.value[$0.id] == nil
        }
        guard let index = recent.firstIndex(where: { $0.id == identifier }),
              index >= recentLimit
        else { return }
        let pages = index / Self.recentPageSize + 1
        recentLimit = pages * Self.recentPageSize
        updateDataSource()
    }

    static func replacementSelection(
        for selected: Conversation.ID?,
        displayed: [Conversation.ID],
        isAvailable: (Conversation.ID) -> Bool,
    ) -> Conversation.ID? {
        guard let selected, !isAvailable(selected) else { return nil }
        guard let first = displayed.first, isAvailable(first) else { return nil }
        return first
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        // Command + 1...9 selects the nth conversation row in display order.
        var resolved = false
        for press in presses {
            guard let key = press.key else { continue }
            let keyCode = key.charactersIgnoringModifiers
            guard keyCode.count == 1,
                  key.modifierFlags.contains(.command),
                  let digit = Int(keyCode),
                  digit >= 1
            else { continue }
            let displayed = displayedConversationIdentifiers()
            guard displayed.indices.contains(digit - 1) else { continue }
            ChatSelection.shared.select(displayed[digit - 1])
            resolved = true
        }
        if !resolved {
            super.pressesBegan(presses, with: event)
        }
    }
}
