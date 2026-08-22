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

    enum DataIdentifier: Hashable {
        case conversation(Conversation.ID)
        case folder(ConversationFolder.ID)
    }

    enum SectionIdentifier: Hashable {
        case folder(ConversationFolder.ID)
        case date(Date)
    }

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
            tableView.separatorColor = .clear
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath) as! Cell
            switch itemIdentifier {
            case let .conversation(identifier):
                let conversation = ConversationManager.shared.conversation(identifier: identifier)
                let isFiled = ConversationManager.shared.folderMemberships.value[identifier] != nil
                cell.use(conversation: conversation, indented: isFiled)
            case let .folder(identifier):
                let manager = ConversationManager.shared
                let count = manager.folderMemberships.value.values.filter { $0 == identifier }.count
                cell.use(
                    folder: manager.folders.value.first { $0.id == identifier },
                    expanded: (tableView.delegate as? ConversationSelectionView)?.expandedFolderIds.contains(identifier) ?? false,
                    count: count,
                )
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

        tableView.delegate = self
        tableView.dragDelegate = self
        tableView.dropDelegate = self
        tableView.dragInteractionEnabled = true
        tableView.separatorStyle = .none
        tableView.separatorInset = .zero
        tableView.separatorColor = .clear
        tableView.contentInset = .zero
        tableView.allowsMultipleSelection = false
        tableView.selectionFollowsFocus = true
        tableView.backgroundColor = .clear
        tableView.showsVerticalScrollIndicator = false
        tableView.showsHorizontalScrollIndicator = false
        tableView.sectionHeaderTopPadding = 0
        tableView.sectionHeaderHeight = UITableView.automaticDimension

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
            for indexPath in tableView.indexPathsForSelectedRows ?? [] {
                tableView.deselectRow(at: indexPath, animated: false)
            }
            if let identifier,
               let indexPath = dataSource.indexPath(for: .conversation(identifier))
            {
                let visible = tableView.indexPathsForVisibleRows?.contains(indexPath) ?? false
                tableView.selectRow(
                    at: indexPath,
                    animated: false,
                    scrollPosition: visible ? .none : .middle,
                )
            } else if let firstConversation = dataSource.snapshot().itemIdentifiers.first(where: {
                if case .conversation = $0 { return true }
                return false
            }),
                let indexPath = dataSource.indexPath(for: firstConversation)
            {
                let visible = tableView.indexPathsForVisibleRows?.contains(indexPath) ?? false
                tableView.selectRow(
                    at: indexPath,
                    animated: false,
                    scrollPosition: visible ? .none : .middle,
                )
            }
        }
        .store(in: &cancellables)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
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

        for folder in folders {
            let section = SectionIdentifier.folder(folder.id)
            snapshot.appendSections([section])
            snapshot.appendItems([.folder(folder.id)], toSection: section)
            if expandedFolderIds.contains(folder.id) {
                snapshot.appendItems(
                    list.filter { memberships[$0.id] == folder.id }.map { .conversation($0.id) },
                    toSection: section,
                )
            }
        }

        let favorited = unfiled.filter(\.isFavorite)
        if !favorited.isEmpty {
            let favoriteSection = SectionIdentifier.date(Date(timeIntervalSince1970: -1))
            snapshot.appendSections([favoriteSection])
            snapshot.appendItems(favorited.map { .conversation($0.id) }, toSection: favoriteSection)
        }

        let calendar = Calendar.current

        var conversationsByDate: [Date: [Conversation.ID]] = [:]
        for item in unfiled where !item.isFavorite {
            let dateOnly = calendar.startOfDay(for: item.creation)
            if conversationsByDate[dateOnly] == nil {
                conversationsByDate[dateOnly] = []
            }
            conversationsByDate[dateOnly]?.append(item.id)
        }

        let sortedDates = conversationsByDate.keys.sorted(by: >)

        for date in sortedDates {
            let section = SectionIdentifier.date(date)
            snapshot.appendSections([section])
            if let conversations = conversationsByDate[date] {
                snapshot.appendItems(conversations.map { .conversation($0) }, toSection: section)
            }
        }
        let previousSections = dataSource.snapshot().sectionIdentifiers
        if previousSections.count == 1, sortedDates.count > 1 {
            // reload all!
            snapshot.reloadSections(sortedDates.map { .date($0) })
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
        snapshot.reconfigureItems([.folder(identifier)])
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    func expandFolder(_ identifier: ConversationFolder.ID) {
        guard !expandedFolderIds.contains(identifier) else { return }
        toggleFolder(identifier)
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        // detect command + 1/2/3/4 ... 9 to select conversation
        var resolved = false
        for press in presses {
            guard let key = press.key else { continue }
            let keyCode = key.charactersIgnoringModifiers
            guard keyCode.count == 1,
                  key.modifierFlags.contains(.command),
                  var digit = Int(keyCode)
            else { continue }
            digit -= 1
            guard digit >= 0, digit < dataSource.snapshot().numberOfItems else {
                continue
            }

            // now check which section we are in
            let snapshot = dataSource.snapshot()
            var sectionIndex: Int? = nil
            var sectionItemIndex: Int? = nil
            var currentCount = 0
            for (index, section) in snapshot.sectionIdentifiers.enumerated() {
                let count = snapshot.numberOfItems(inSection: section)
                if currentCount + count > digit {
                    sectionIndex = index
                    sectionItemIndex = digit - currentCount
                    break
                }
                currentCount += count
            }
            guard let sectionIndex, let sectionItemIndex else {
                assertionFailure()
                continue
            }
            let indexPath = IndexPath(item: sectionItemIndex, section: sectionIndex)
            guard let identifier = dataSource.itemIdentifier(for: indexPath), case let .conversation(conversationId) = identifier else { continue }
            ChatSelection.shared.select(conversationId)
            resolved = true
        }
        if !resolved {
            super.pressesBegan(presses, with: event)
        }
    }
}
