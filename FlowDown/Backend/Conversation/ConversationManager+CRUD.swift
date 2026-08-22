//
//  ConversationManager+CRUD.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/31/25.
//

import Combine
import Foundation
import OrderedCollections
import Storage

extension ConversationManager {
    func scanAll() {
        let items: [Conversation] = sdb.conversationList()
        Logger.database.infoFile("scanned \(items.count) conversations")
        // Cannot convert value of type '[Conversation]' to expected argument type 'OrderedDictionary<Conversation.ID, Conversation>' (aka 'OrderedDictionary<Int64, Conversation>')
        let dic = OrderedDictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        conversations.send(dic)
        folders.send(sdb.conversationFolderList())
        var memberships = sdb.conversationFolderMemberships()
        // Memberships can outlive their conversation when a deletion arrives
        // from sync; prune them so folders never count phantom rows.
        let orphaned = memberships.keys.filter { dic[$0] == nil }
        if !orphaned.isEmpty {
            sdb.conversationAssign(orphaned, toFolder: nil)
            orphaned.forEach { memberships[$0] = nil }
        }
        folderMemberships.send(memberships)
    }

    @discardableResult
    func createFolder(title: String = String(localized: "New Folder"), conversations identifiers: [Conversation.ID] = []) -> ConversationFolder {
        let folder = sdb.conversationFolderMake(title: title)
        sdb.conversationAssign(identifiers, toFolder: folder.id)
        scanAll()
        return folder
    }

    func moveConversations(_ identifiers: [Conversation.ID], toFolder folderId: ConversationFolder.ID?) {
        sdb.conversationAssign(identifiers, toFolder: folderId)
        scanAll()
    }

    func renameFolder(identifier: ConversationFolder.ID, title: String) {
        sdb.conversationFolderUpdate(identifier: identifier, title: title)
        scanAll()
    }

    func deleteFolder(identifier: ConversationFolder.ID) {
        sdb.conversationFolderRemove(identifier: identifier)
        scanAll()
    }

    func initialConversation() -> Conversation {
        if let firstItem = conversations.value.values.first,
           message(within: firstItem.id).isEmpty
        {
            Logger.database.debugFile("using first empty conversation id: \(firstItem.id)")
            return firstItem
        }
        Logger.database.infoFile("creating a new conversation")
        return createNewConversation()
    }

    func createNewConversation(_ block: Storage.ConversationMakeInitDataBlock? = nil, autoSelect: Bool = false) -> Conversation {
        let tempObject = sdb.conversationMake {
            $0.update(\.title, to: String(localized: "Conversation"))
            if $0.modelId?.isEmpty ?? true {
                $0.update(\.modelId, to: ModelManager.ModelIdentifier.defaultModelForConversation)
            }

            if let block {
                block($0)
            }
        }

        scanAll()
        guard let object = sdb.conversationWith(identifier: tempObject.id) else {
            preconditionFailure()
        }
        Logger.database.infoFile("created new conversation id: \(object.id)")
        NotificationCenter.default.post(name: .newChatCreated, object: object.id)
        let session = ConversationSessionManager.shared.session(for: object.id)

        // guide message when no history message
        if ConversationManager.shouldShowGuideMessage {
            if conversations.value.count <= 1 {
                let guide = String(localized:
                    """
                    **Welcome to FlowDown🐦**, a blazing fast and smooth client app for LLMs with respect of your privacy.

                    Use Apple Intelligence or _run local models_ on supported devices. You can also _configure cloud models_ with your own provider.

                    💡 For more information, check out [our wiki](https://flowdown.ai/docs/).

                    ---
                    **What to do next?**

                    1. Select or _add a new model_, and **create a new conversation**.
                    2. Later, you can go to **Settings** to customize your experience.
                    3. For any issues, feel free to [contact us](https://discord.gg/UHKMRyJcgc).

                    ✨ **Enjoy your FlowDown experience!**
                    """)

                session.appendNewMessage(role: .assistant) {
                    $0.update(\.document, to: guide)
                }
                session.save()
                session.notifyMessagesDidChange()

                editConversation(identifier: object.id) { conversation in
                    let icon = "🥳".textToImage(size: 128)?.pngData() ?? .init()

                    conversation.update(\.title, to: String(localized: "Introduction to FlowDown"))
                    conversation.update(\.icon, to: icon)
                    conversation.update(\.shouldAutoRename, to: false)
                }

                ConversationManager.shouldShowGuideMessage = false
            }
        }

        session.prepareSystemPrompt()

        if autoSelect { ChatSelection.shared.select(object.id, options: [.collapseSidebar, .focusEditor]) }

        return object
    }

    func conversation(identifier: Conversation.ID?) -> Conversation? {
        guard let identifier else { return nil }
        if let cached = conversations.value[identifier] {
            return cached
        }
        return sdb.conversationWith(identifier: identifier)
    }

    func editConversation(identifier: Conversation.ID, block: @escaping (inout Conversation) -> Void) {
        let conv = conversation(identifier: identifier)
        guard var conv else { return }
        block(&conv)
        sdb.conversationUpdate(object: conv)
        scanAll()
    }

    func duplicateConversation(identifier: Conversation.ID) -> Conversation.ID? {
        let ans = sdb.conversationDuplicate(identifier: identifier) { conv in
            let title = String(localized: "\(conv.title) Copy")
            conv.update(\.title, to: title)
        }
        scanAll()
        return ans
    }

    func deleteConversation(identifier: Conversation.ID) {
        let session = ConversationSessionManager.shared.session(for: identifier)
        session.cancelCurrentTask {}
        sdb.conversationRemove(conversationWith: identifier)
        sdb.conversationAssign([identifier], toFolder: nil)
        try? Storage.db().deleteSummary(forConversation: identifier.description)
        setRichEditorObject(identifier: identifier, nil)
        scanAll()
        // Invalidate session cache so next access reloads from DB
        ConversationSessionManager.shared.invalidateSession(for: identifier)
    }

    func eraseAll() {
        sdb.conversationsDrop()
        clearRichEditorObject()
        ConversationManager.shouldShowGuideMessage = true
        scanAll()
        // Clear all cached sessions after mass deletion
        for (identifier, _) in conversations.value {
            ConversationSessionManager.shared.invalidateSession(for: identifier)
        }
    }

    func conversationIdentifierLookup(from messageIdentifier: Message.ID) -> Conversation.ID? {
        sdb.conversationIdentifierLookup(identifier: messageIdentifier)
    }
}

extension ConversationManager {
    func message(within conv: Conversation.ID) -> [Message] {
        sdb.listMessages(within: conv)
    }
}

extension Notification.Name {
    static let newChatCreated = Notification.Name("newChatCreated")
}

extension ConversationManager {
    static var shouldShowGuideMessage: Bool {
        get {
            if UserDefaults.standard.object(forKey: "ShowGuideMessage") == nil {
                // true on initial start
                UserDefaults.standard.set(true, forKey: "ShowGuideMessage")
                return true
            }
            return UserDefaults.standard.bool(forKey: "ShowGuideMessage")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "ShowGuideMessage")
        }
    }
}
