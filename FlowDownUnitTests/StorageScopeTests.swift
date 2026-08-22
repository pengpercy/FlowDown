@testable import FlowDown
import Storage
import Testing

struct StorageScopeTests {
    @Test
    func `settings backup errors expose actionable descriptions`() {
        let cases: [SettingsBackupError] = [
            .unsupportedStorage,
            .emptyBackup,
            .invalidBackup,
        ]

        for error in cases {
            #expect(!(error.errorDescription ?? "").isEmpty)
        }
    }

    @Test
    func `conversation folder membership retains its conversation and folder identifiers`() {
        let membership = ConversationFolderMembership(conversationId: "conversation-id", folderId: "folder-id")

        #expect(membership.conversationId == "conversation-id")
        #expect(membership.folderId == "folder-id")
    }
}
