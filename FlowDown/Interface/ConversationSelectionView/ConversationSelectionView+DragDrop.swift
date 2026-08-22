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
        guard session.localDragSession != nil,
              let indexPath,
              let item = dataSource.itemIdentifier(for: indexPath),
              case .folder = item
        else { return UITableViewDropProposal(operation: .forbidden) }
        return UITableViewDropProposal(operation: .move, intent: .insertIntoDestinationIndexPath)
    }

    func tableView(_: UITableView, performDropWith coordinator: UITableViewDropCoordinator) {
        guard let destination = coordinator.destinationIndexPath,
              let item = dataSource.itemIdentifier(for: destination),
              case let .folder(folderId) = item
        else { return }
        let identifiers = coordinator.items.compactMap { $0.dragItem.localObject as? Conversation.ID }
        ConversationManager.shared.moveConversations(identifiers, toFolder: folderId)
        expandFolder(folderId)
    }
}
