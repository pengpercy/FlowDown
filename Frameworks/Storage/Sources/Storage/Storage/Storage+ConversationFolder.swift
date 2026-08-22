import Foundation
import WCDBSwift

public extension Storage {
    func conversationFolderList() -> [ConversationFolder] {
        (try? db.getObjects(
            fromTable: ConversationFolder.tableName,
            orderBy: [ConversationFolder.Properties.creation.order(.ascending)],
        )) ?? []
    }

    func conversationFolderMemberships() -> [Conversation.ID: ConversationFolder.ID] {
        let memberships: [ConversationFolderMembership] = (try? db.getObjects(
            fromTable: ConversationFolderMembership.tableName,
        )) ?? []
        return Dictionary(uniqueKeysWithValues: memberships.map { ($0.conversationId, $0.folderId) })
    }

    @discardableResult
    func conversationFolderMake(title: String) -> ConversationFolder {
        let folder = ConversationFolder(title: title)
        try? db.insert(folder, intoTable: ConversationFolder.tableName)
        return folder
    }

    func conversationAssign(_ identifiers: [Conversation.ID], toFolder folderId: ConversationFolder.ID?) {
        guard !identifiers.isEmpty else { return }
        try? runTransaction { handle in
            if let folderId {
                for identifier in identifiers {
                    try handle.insertOrReplace(
                        ConversationFolderMembership(conversationId: identifier, folderId: folderId),
                        intoTable: ConversationFolderMembership.tableName,
                    )
                }
            } else {
                try handle.delete(
                    fromTable: ConversationFolderMembership.tableName,
                    where: ConversationFolderMembership.Properties.conversationId.in(identifiers),
                )
            }
        }
    }

    func conversationFolderRemove(identifier: ConversationFolder.ID) {
        try? runTransaction { handle in
            try handle.delete(
                fromTable: ConversationFolderMembership.tableName,
                where: ConversationFolderMembership.Properties.folderId == identifier,
            )
            try handle.delete(
                fromTable: ConversationFolder.tableName,
                where: ConversationFolder.Properties.objectId == identifier,
            )
        }
    }
}
