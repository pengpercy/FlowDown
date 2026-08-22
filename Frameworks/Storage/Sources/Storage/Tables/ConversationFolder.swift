import Foundation
import WCDBSwift

public final class ConversationFolder: Identifiable, Codable, TableNamed, TableCodable {
    public static let tableName = "ConversationFolder"

    public var id: String { objectId }
    public package(set) var objectId = UUID().uuidString
    public package(set) var title = ""
    public package(set) var creation = Date.now

    public enum CodingKeys: String, CodingTableKey {
        public typealias Root = ConversationFolder
        public static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(objectId, isNotNull: true, isUnique: true)
            BindColumnConstraint(title, isNotNull: true, defaultTo: "")
            BindColumnConstraint(creation, isNotNull: true)
            BindIndex(creation, namedWith: "_creationIndex")
        }

        case objectId
        case title
        case creation
    }

    public init(title: String) {
        self.title = title
    }
}

public struct ConversationFolderMembership: TableNamed, TableCodable {
    public static let tableName = "ConversationFolderMembership"

    public var conversationId = ""
    public var folderId = ""

    public enum CodingKeys: String, CodingTableKey {
        public typealias Root = ConversationFolderMembership
        public static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(conversationId, isNotNull: true, isUnique: true)
            BindColumnConstraint(folderId, isNotNull: true)
            BindIndex(folderId, namedWith: "_folderIdIndex")
        }

        case conversationId
        case folderId
    }

    public init(conversationId: String, folderId: String) {
        self.conversationId = conversationId
        self.folderId = folderId
    }
}
