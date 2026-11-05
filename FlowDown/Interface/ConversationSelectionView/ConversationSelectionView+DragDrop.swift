//
//  ConversationSelectionView+DragDrop.swift
//  FlowDown
//
//  Created by 秋星桥 on 8/22/26.
//

import Storage
import UIKit

/// Drag a conversation onto a folder row (or any row inside an expanded
/// folder) to file it there; drop it anywhere in the unfiled list to take it
/// out of its folder.
///
/// The drop target is resolved from the pointer location by section rather
/// than from the table's insertion index path, which flips between rows and
/// the gaps around them as the pointer moves. The target region is outlined
/// by `dropHighlightView`, and the table's own insertion gap is suppressed
/// because the sidebar order is not user-controlled.
extension ConversationSelectionView: UITableViewDragDelegate, UITableViewDropDelegate {
    enum DropTarget: Equatable {
        case folder(ConversationFolder.ID)
        case unfiled
    }

    // MARK: - Drag

    func tableView(_: UITableView, itemsForBeginning _: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        guard case let .conversation(identifier) = dataSource.itemIdentifier(for: indexPath) else { return [] }
        let dragItem = UIDragItem(itemProvider: NSItemProvider(object: identifier as NSString))
        dragItem.localObject = identifier
        return [dragItem]
    }

    func tableView(_: UITableView, dragSessionIsRestrictedToDraggingApplication _: UIDragSession) -> Bool {
        true
    }

    func tableView(_ tableView: UITableView, dragPreviewParametersForRowAt indexPath: IndexPath) -> UIDragPreviewParameters? {
        roundedPreviewParameters(forRowAt: indexPath, in: tableView)
    }

    // MARK: - Drop

    func tableView(_: UITableView, canHandle session: UIDropSession) -> Bool {
        session.localDragSession != nil
    }

    func tableView(_ tableView: UITableView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath _: IndexPath?) -> UITableViewDropProposal {
        let identifiers = draggedConversationIdentifiers(in: session)
        guard !identifiers.isEmpty else {
            updateDropHighlight(nil)
            return UITableViewDropProposal(operation: .forbidden)
        }

        let target = dropTarget(at: session.location(in: tableView))
        guard let target, dropChangesMembership(of: identifiers, to: target) else {
            updateDropHighlight(nil)
            return UITableViewDropProposal(operation: .cancel)
        }

        updateDropHighlight(target)
        return UITableViewDropProposal(operation: .move, intent: .unspecified)
    }

    func tableView(_ tableView: UITableView, performDropWith coordinator: UITableViewDropCoordinator) {
        let identifiers = draggedConversationIdentifiers(in: coordinator.session)
        let target = dropTarget(at: coordinator.session.location(in: tableView)) ?? currentDropTarget
        updateDropHighlight(nil)
        guard !identifiers.isEmpty, let target, dropChangesMembership(of: identifiers, to: target) else { return }

        switch target {
        case let .folder(folderId):
            // Shrink the drag preview into the folder row before the list
            // updates, so it is clear where the conversation went.
            if let folderRow = dataSource.indexPath(for: .folder(folderId)),
               let cell = tableView.cellForRow(at: folderRow)
            {
                for item in coordinator.items {
                    coordinator.drop(item.dragItem, intoRowAt: folderRow, rect: cell.bounds)
                }
            }
            ConversationManager.shared.moveConversations(identifiers, toFolder: folderId)
            expandFolder(folderId)
        case .unfiled:
            ConversationManager.shared.moveConversations(identifiers, toFolder: nil)
        }
    }

    func tableView(_: UITableView, dropSessionDidExit _: UIDropSession) {
        updateDropHighlight(nil)
    }

    func tableView(_: UITableView, dropSessionDidEnd _: UIDropSession) {
        updateDropHighlight(nil)
    }

    func tableView(_ tableView: UITableView, dropPreviewParametersForRowAt indexPath: IndexPath) -> UIDragPreviewParameters? {
        roundedPreviewParameters(forRowAt: indexPath, in: tableView)
    }

    // MARK: - Spring Loading

    func tableView(_: UITableView, shouldSpringLoadRowAt indexPath: IndexPath, with _: UISpringLoadedInteractionContext) -> Bool {
        // Hovering a drag over a collapsed folder opens it; an open folder is
        // never collapsed underneath the pointer.
        guard case let .folder(identifier) = dataSource.itemIdentifier(for: indexPath) else { return false }
        return !expandedFolderIds.contains(identifier)
    }

    // MARK: - Helpers

    private func draggedConversationIdentifiers(in session: UIDropSession) -> [Conversation.ID] {
        session.localDragSession?.items.compactMap { $0.localObject as? Conversation.ID } ?? []
    }

    private func dropChangesMembership(of identifiers: [Conversation.ID], to target: DropTarget) -> Bool {
        let memberships = ConversationManager.shared.folderMemberships.value
        switch target {
        case let .folder(folderId):
            return identifiers.contains { memberships[$0] != folderId }
        case .unfiled:
            return identifiers.contains { memberships[$0] != nil }
        }
    }

    /// Resolves the folder or unfiled area under a point in table coordinates.
    func dropTarget(at point: CGPoint) -> DropTarget? {
        let sections = dataSource.snapshot().sectionIdentifiers
        for (index, section) in sections.enumerated() {
            let rect = tableView.rect(forSection: index)
            guard point.y >= rect.minY, point.y < rect.maxY else { continue }
            switch section {
            case .folders: return nil
            case let .folder(identifier): return .folder(identifier)
            case .favorites, .date: return .unfiled
            }
        }
        // Empty space below the last row belongs to the unfiled list, which
        // keeps it reachable even when the list is short.
        if let last = sections.indices.last, point.y >= tableView.rect(forSection: last).maxY {
            return .unfiled
        }
        return nil
    }

    /// Drop updates arrive for every pointer movement, so only a change of
    /// target animates; while the target stays the same (for example during
    /// autoscroll) the outline just follows its frame.
    private func updateDropHighlight(_ target: DropTarget?) {
        let previousTarget = currentDropTarget
        currentDropTarget = target
        guard let target, let frame = highlightFrame(for: target), !frame.isEmpty else {
            guard previousTarget != nil || dropHighlightView.alpha > 0 else { return }
            UIView.animate(withDuration: 0.15, delay: 0, options: [.beginFromCurrentState]) {
                self.dropHighlightView.alpha = 0
            }
            return
        }
        guard target != previousTarget || dropHighlightView.alpha == 0 else {
            if dropHighlightView.frame != frame { dropHighlightView.frame = frame }
            return
        }
        if dropHighlightView.alpha == 0 { dropHighlightView.frame = frame }
        UIView.animate(withDuration: 0.15, delay: 0, options: [.beginFromCurrentState]) {
            self.dropHighlightView.frame = frame
            self.dropHighlightView.alpha = 1
        }
    }

    private func highlightFrame(for target: DropTarget) -> CGRect? {
        let sections = dataSource.snapshot().sectionIdentifiers
        switch target {
        case let .folder(identifier):
            guard let index = sections.firstIndex(of: .folder(identifier)) else { return nil }
            return tableView.rect(forSection: index)
        case .unfiled:
            let rects = sections.enumerated().compactMap { index, section -> CGRect? in
                switch section {
                case .favorites, .date: return tableView.rect(forSection: index)
                default: return nil
                }
            }
            let visible = tableView.bounds
            guard var region = rects.first ?? sections.indices.last.map({
                CGRect(x: 0, y: tableView.rect(forSection: $0).maxY, width: visible.width, height: 0)
            }) else { return nil }
            for rect in rects.dropFirst() {
                region = region.union(rect)
            }
            // Extend over the empty space below the rows, then clip to what
            // is on screen so the outline never runs past the visible list.
            region.size.height = max(region.height, visible.maxY - region.minY)
            return region.intersection(visible)
        }
    }

    private func roundedPreviewParameters(forRowAt indexPath: IndexPath, in tableView: UITableView) -> UIDragPreviewParameters? {
        guard let cell = tableView.cellForRow(at: indexPath) else { return nil }
        let parameters = UIDragPreviewParameters()
        parameters.backgroundColor = .clear
        parameters.visiblePath = UIBezierPath(
            roundedRect: cell.bounds,
            cornerRadius: Cell.Metrics.cornerRadius,
        )
        return parameters
    }
}
