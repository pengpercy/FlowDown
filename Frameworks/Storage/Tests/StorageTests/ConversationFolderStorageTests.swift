import Foundation
@testable import Storage
import Testing

struct ConversationFolderStorageTests {
    @Test
    func `folder create assign move rename and remove lifecycle`() throws {
        try StorageTestSupport.withTemporaryStorage { storage in
            let conversation = storage.conversationMake { conversation in
                conversation.update(\.title, to: "Chat")
            }
            let otherConversation = storage.conversationMake { conversation in
                conversation.update(\.title, to: "Other Chat")
            }

            let folder = storage.conversationFolderMake(title: "Work")
            #expect(storage.conversationFolderList().map(\.id) == [folder.id])
            #expect(storage.conversationFolderList().first?.title == "Work")

            storage.conversationAssign([conversation.id, otherConversation.id], toFolder: folder.id)
            #expect(storage.conversationFolderMemberships() == [
                conversation.id: folder.id,
                otherConversation.id: folder.id,
            ])

            let anotherFolder = storage.conversationFolderMake(title: "Personal")
            storage.conversationAssign([otherConversation.id], toFolder: anotherFolder.id)
            #expect(storage.conversationFolderMemberships() == [
                conversation.id: folder.id,
                otherConversation.id: anotherFolder.id,
            ])

            storage.conversationFolderUpdate(identifier: folder.id, title: "Renamed")
            #expect(storage.conversationFolderList().first { $0.id == folder.id }?.title == "Renamed")

            storage.conversationAssign([conversation.id], toFolder: nil)
            #expect(storage.conversationFolderMemberships() == [otherConversation.id: anotherFolder.id])

            storage.conversationAssign([conversation.id], toFolder: folder.id)
            storage.conversationFolderRemove(identifier: folder.id)
            #expect(storage.conversationFolderList().map(\.id) == [anotherFolder.id])
            #expect(storage.conversationFolderMemberships() == [otherConversation.id: anotherFolder.id])
        }
    }
}
