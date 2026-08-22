//
//  ConversationSelectionView+Delegate.swift
//  FlowDown
//
//  Created by 秋星桥 on 2/5/25.
//

import Storage
import UIKit

extension ConversationSelectionView: UITableViewDelegate {
    func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        switch item {
        case let .conversation(identifier):
            Logger.ui.debugFile("ConversationSelectionView didSelectRowAt: \(identifier)")
            ChatSelection.shared.select(identifier, options: [.collapseSidebar])
        case let .folder(identifier):
            // Keep the highlight off folder rows so every tap starts from an
            // unselected row and reliably re-triggers this delegate call.
            tableView.deselectRow(at: indexPath, animated: true)
            toggleFolder(identifier)
        }
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let item = dataSource.itemIdentifier(for: indexPath), case let .conversation(identifier) = item else { return nil }

        let duplicateAction = UIContextualAction(style: .normal, title: nil) { _, _, completion in
            if let duplicatedId = ConversationManager.shared.duplicateConversation(identifier: identifier) {
                ChatSelection.shared.select(duplicatedId, options: [.collapseSidebar])
            }
            completion(true)
        }
        duplicateAction.image = UIImage(systemName: "doc.on.doc")

        let deleteAction = UIContextualAction(style: .destructive, title: nil) { [weak self] _, _, completion in
            guard let self else {
                completion(false)
                return
            }

            let snapshot = dataSource.snapshot()
            let identifiers = snapshot.itemIdentifiers.compactMap { item -> Conversation.ID? in
                guard case let .conversation(identifier) = item else { return nil }
                return identifier
            }
            let currentSelectionIndex = identifiers.firstIndex(of: identifier)
            let isDeletingSelectedRow = tableView.indexPathForSelectedRow == indexPath

            ConversationManager.shared.deleteConversation(identifier: identifier)

            Task { @MainActor in
                if isDeletingSelectedRow,
                   let currentSelectionIndex,
                   let nextIdentifier = (
                       identifiers.dropFirst(currentSelectionIndex + 1).first
                           ?? identifiers.prefix(currentSelectionIndex).last,
                   )
                {
                    ChatSelection.shared.select(nextIdentifier)
                }
                completion(true)
            }
        }
        deleteAction.image = UIImage(systemName: "trash")

        let configuration = UISwipeActionsConfiguration(actions: [deleteAction, duplicateAction])
        configuration.performsFirstActionWithFullSwipe = true
        return configuration
    }

    func tableView(_: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let item = dataSource.itemIdentifier(for: indexPath), case let .conversation(identifier) = item,
              let conversation = ConversationManager.shared.conversation(identifier: identifier)
        else { return nil }

        let isFavorite = conversation.isFavorite
        let imageName = isFavorite ? "star.slash" : "star"

        let favoriteAction = UIContextualAction(style: .normal, title: nil) { _, _, completion in
            ConversationManager.shared.editConversation(identifier: identifier) { conv in
                conv.update(\.isFavorite, to: !isFavorite)
            }
            completion(true)
        }
        favoriteAction.image = UIImage(systemName: imageName)
        favoriteAction.backgroundColor = .systemYellow

        let configuration = UISwipeActionsConfiguration(actions: [favoriteAction])
        configuration.performsFirstActionWithFullSwipe = true
        return configuration
    }

    func tableView(_: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let sectionIdentifiers = dataSource.snapshot().sectionIdentifiers
        let datedSectionCount = sectionIdentifiers.filter {
            if case .date = $0 { return true }
            return false
        }.count
        // Folder sections never show a header, and their presence alone should
        // not bring back the date headers hidden in single-section lists.
        guard datedSectionCount > 1 else { return nil }
        guard case let .date(sectionIdentifier) = sectionIdentifiers[section] else { return nil }
        return SectionDateHeaderView().with {
            $0.updateTitle(date: sectionIdentifier)
        }
    }

    func tableView(_: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        let sectionIdentifiers = dataSource.snapshot().sectionIdentifiers
        guard case .date = sectionIdentifiers[section] else { return 0 }
        let datedSectionCount = sectionIdentifiers.filter {
            if case .date = $0 { return true }
            return false
        }.count
        return datedSectionCount > 1 ? UITableView.automaticDimension : 0
    }
}
