//
//  ConversationSelectionView+DragDrop.swift
//  FlowDown
//
//  Created by 秋星桥 on 8/22/26.
//

import Storage
import UIKit

extension ConversationSelectionView: UITableViewDragDelegate, UITableViewDropDelegate {
    func tableView(_: UITableView, itemsForBeginning _: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        guard let item = dataSource.itemIdentifier(for: indexPath), case let .conversation(identifier) = item else { return [] }
        let dragItem = UIDragItem(itemProvider: NSItemProvider(object: identifier as NSString))
        dragItem.localObject = identifier
        return [dragItem]
    }

    func tableView(_: UITableView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath indexPath: IndexPath?) -> UITableViewDropProposal {
        guard session.localDragSession != nil else {
            return UITableViewDropProposal(operation: .forbidden)
        }

        if let indexPath {
            guard dataSource.itemIdentifier(for: indexPath) != nil else {
                return UITableViewDropProposal(operation: .forbidden)
            }
            let intent: UITableViewDropProposal.Intent = {
                guard let section = sectionIdentifier(at: indexPath), case .folder = section else {
                    return .insertAtDestinationIndexPath
                }
                return .insertIntoDestinationIndexPath
            }()
            return UITableViewDropProposal(operation: .move, intent: intent)
        }

        // Dropping into unused space in the list removes a conversation from
        // its folder. This makes the unfiled list a reachable drag target even
        // when its rows are not currently visible.
        return UITableViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
    }

    func tableView(_: UITableView, performDropWith coordinator: UITableViewDropCoordinator) {
        let folderId: ConversationFolder.ID?
        if let destination = coordinator.destinationIndexPath {
            guard let section = sectionIdentifier(at: destination) else { return }
            switch section {
            case let .folder(identifier):
                folderId = identifier
            case .date:
                folderId = nil
            }
        } else {
            folderId = nil
        }

        let identifiers = coordinator.items.compactMap { $0.dragItem.localObject as? Conversation.ID }
        guard !identifiers.isEmpty else { return }
        ConversationManager.shared.moveConversations(identifiers, toFolder: folderId)
        if let folderId {
            expandFolder(folderId)
        }
    }

    private func sectionIdentifier(at indexPath: IndexPath) -> SectionIdentifier? {
        let sections = dataSource.snapshot().sectionIdentifiers
        guard sections.indices.contains(indexPath.section) else { return nil }
        return sections[indexPath.section]
    }
}
