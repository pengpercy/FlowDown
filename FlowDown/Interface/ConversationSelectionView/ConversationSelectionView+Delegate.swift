//
//  ConversationSelectionView+Delegate.swift
//  FlowDown
//
//  Created by 秋星桥 on 2/5/25.
//

import Storage
import UIKit

extension ConversationSelectionView: UITableViewDelegate {
    // MARK: - Selection

    func tableView(_: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        if case .folderPlaceholder = dataSource.itemIdentifier(for: indexPath) { return false }
        return true
    }

    func tableView(_: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        if case .folderPlaceholder = dataSource.itemIdentifier(for: indexPath) { return nil }
        return indexPath
    }

    func tableView(_: UITableView, canFocusRowAt indexPath: IndexPath) -> Bool {
        if case .folderPlaceholder = dataSource.itemIdentifier(for: indexPath) { return false }
        return true
    }

    func tableView(_: UITableView, selectionFollowsFocusForRowAt indexPath: IndexPath) -> Bool {
        // Moving keyboard focus across a folder row must not toggle it.
        guard case .conversation = dataSource.itemIdentifier(for: indexPath) else { return false }
        return true
    }

    func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        switch item {
        case let .conversation(identifier):
            Logger.ui.debugFile("ConversationSelectionView didSelectRowAt: \(identifier)")
            ChatSelection.shared.select(identifier, options: [.collapseSidebar])
        case let .folder(identifier):
            // Keep the highlight off folder rows so every click starts from an
            // unselected row and reliably re-triggers this delegate call.
            tableView.deselectRow(at: indexPath, animated: false)
            toggleFolder(identifier)
        case .folderPlaceholder:
            tableView.deselectRow(at: indexPath, animated: false)
        }
    }

    // MARK: - Swipe Actions

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

            let identifiers = displayedConversationIdentifiers()
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

    // MARK: - Context Menu

    func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point _: CGPoint,
    ) -> UIContextMenuConfiguration? {
        guard let item = dataSource.itemIdentifier(for: indexPath),
              let cell = tableView.cellForRow(at: indexPath)
        else { return nil }

        let menu: UIMenu?
        switch item {
        case let .conversation(identifier):
            menu = ConversationManager.shared.menu(forConversation: identifier, view: cell)
        case let .folder(identifier):
            menu = ConversationManager.shared.folderMenu(forFolder: identifier, view: cell)
        case .folderPlaceholder:
            menu = nil
        }
        guard let menu else { return nil }

        return UIContextMenuConfiguration(
            identifier: indexPath as NSIndexPath,
            previewProvider: nil,
        ) { _ in menu }
    }

    func tableView(
        _ tableView: UITableView,
        previewForHighlightingContextMenuWithConfiguration configuration: UIContextMenuConfiguration,
    ) -> UITargetedPreview? {
        roundedPreview(for: configuration, in: tableView)
    }

    func tableView(
        _ tableView: UITableView,
        previewForDismissingContextMenuWithConfiguration configuration: UIContextMenuConfiguration,
    ) -> UITargetedPreview? {
        roundedPreview(for: configuration, in: tableView)
    }

    private func roundedPreview(
        for configuration: UIContextMenuConfiguration,
        in tableView: UITableView,
    ) -> UITargetedPreview? {
        guard let indexPath = configuration.identifier as? IndexPath,
              let cell = tableView.cellForRow(at: indexPath)
        else { return nil }
        let parameters = UIPreviewParameters()
        parameters.backgroundColor = .clear
        parameters.visiblePath = UIBezierPath(
            roundedRect: cell.bounds,
            cornerRadius: Cell.Metrics.cornerRadius,
        )
        return UITargetedPreview(view: cell, parameters: parameters)
    }

    // MARK: - Section Headers

    func tableView(_: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let sectionIdentifiers = dataSource.snapshot().sectionIdentifiers
        guard sectionIdentifiers.indices.contains(section) else { return nil }
        switch sectionIdentifiers[section] {
        case .folders:
            return SectionDateHeaderView(accessory: NewFolderButton()).with {
                $0.updateTitle(String(localized: "Folders"))
            }
        case .folder:
            return nil
        case .favorites:
            return SectionDateHeaderView().with {
                $0.updateTitle(String(localized: "Favorite"))
            }
        case let .date(date):
            return SectionDateHeaderView().with {
                $0.updateTitle(date: date)
            }
        }
    }

    func tableView(_: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        let sectionIdentifiers = dataSource.snapshot().sectionIdentifiers
        guard sectionIdentifiers.indices.contains(section) else { return 0 }
        if case .folder = sectionIdentifiers[section] { return 0 }
        return SectionDateHeaderView.height
    }

    func tableView(_: UITableView, heightForFooterInSection _: Int) -> CGFloat {
        0
    }

    func tableView(_: UITableView, viewForFooterInSection _: Int) -> UIView? {
        nil
    }
}
