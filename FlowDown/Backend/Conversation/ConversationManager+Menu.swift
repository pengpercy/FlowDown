//
//  ConversationManager+Menu.swift
//  FlowDown
//
//  Created by 秋星桥 on 2/5/25.
//

import AlertController
import Foundation
import Storage
import UIKit

extension ConversationManager {
    /// Builds the conversation context menu.
    ///
    /// Actions sit at the top level, separated into inline sections: edit,
    /// organize, model actions, export, delete. The only submenus are one
    /// level deep (Move to Folder, Save Image, Export).
    ///
    /// The root menu must not be `.displayInline`: Catalyst renders inline
    /// sections nested inside an inline root as untitled submenus.
    func menu(
        forConversation identifier: Conversation.ID?,
        view: UIView,
    ) -> UIMenu? {
        guard let controller = view.parentViewController else { return nil }
        guard let conv = conversation(identifier: identifier) else { return nil }

        let session = ConversationSessionManager.shared.session(for: conv.id)
        let convHasEmptyContent = session.messages
            .filter { [.user, .assistant].contains($0.role) }
            .isEmpty

        var sections: [UIMenuElement] = []

        if session.currentTask != nil {
            sections.append(UIMenu(options: [.displayInline], children: [
                UIAction(
                    title: String(localized: "Terminate"),
                    image: UIImage(systemName: "stop.circle"),
                    attributes: [.destructive],
                ) { _ in
                    session.cancelCurrentTask {}
                },
            ]))
        }

        let deleteIconAction: UIAction? = conv.icon.isEmpty ? nil : UIAction(
            title: String(localized: "Delete Icon"),
            image: UIImage(systemName: "xmark.circle"),
        ) { _ in
            ConversationManager.shared.editConversation(identifier: conv.id) {
                $0.update(\.icon, to: .init())
            }
        }

        sections.append(UIMenu(
            options: [.displayInline],
            children: [
                UIAction(
                    title: String(localized: "Rename"),
                    image: UIImage(systemName: "pencil"),
                ) { _ in
                    let alert = AlertInputViewController(
                        title: "Rename",
                        message: "Set a new title for the conversation. Leave empty to keep unchanged. This will disable auto-renaming.",
                        placeholder: "Title",
                        text: conv.title,
                    ) { text in
                        guard !text.isEmpty else { return }
                        ConversationManager.shared.editConversation(identifier: conv.id) {
                            $0.update(\.title, to: text)
                            $0.update(\.shouldAutoRename, to: false)
                        }
                    }
                    controller.present(alert, animated: true)
                },
                UIAction(
                    title: String(localized: "Pick New Icon"),
                    image: UIImage(systemName: "face.smiling"),
                ) { _ in
                    let picker = EmojiPickerViewController(sourceView: view) { emoji in
                        ConversationManager.shared.editConversation(identifier: conv.id) {
                            let icon = emoji.emoji.textToImage(size: 128)?.pngData() ?? .init()
                            $0.update(\.icon, to: icon)
                            $0.update(\.shouldAutoRename, to: false)
                        }
                    }
                    controller.present(picker, animated: true)
                },
                deleteIconAction,
            ].compactMap(\.self),
        ))

        sections.append(UIMenu(
            options: [.displayInline],
            children: [
                UIAction(
                    title: conv.isFavorite
                        ? String(localized: "Unfavorite")
                        : String(localized: "Favorite"),
                    image: UIImage(systemName: conv.isFavorite ? "star.slash" : "star"),
                ) { _ in
                    ConversationManager.shared.editConversation(identifier: conv.id) {
                        $0.update(\.isFavorite, to: !conv.isFavorite)
                    }
                },
                moveToFolderMenu(for: [conv.id], controller: controller),
            ],
        ))

        if !convHasEmptyContent {
            // Title generation falls back to a plain completion when the model
            // cannot answer a forced tool call, so the action is never gated on
            // tool capability — a greyed-out entry reads as a broken feature.
            sections.append(UIMenu(options: [.displayInline], children: [
                UIAction(
                    title: String(localized: "Generate New Title"),
                    image: UIImage(systemName: "arrow.clockwise"),
                ) { _ in
                    Indicator.progress(
                        title: "Generating New Title",
                        controller: controller,
                    ) { completion in
                        let sessionManager = ConversationSessionManager.shared
                        let session = sessionManager.session(for: conv.id)
                        let metadata = await session.generateConversationMetadata()
                        await completion {
                            if let metadata {
                                ConversationManager.shared.applyMetadata(
                                    metadata,
                                    to: conv.id,
                                    disablingAutoRename: false,
                                )
                            } else {
                                Indicator.present(
                                    title: "Unable to generate title",
                                    preset: .error,
                                    referencingView: view,
                                )
                            }
                        }
                    }
                },
                UIAction(
                    title: String(localized: "Duplicate"),
                    image: UIImage(systemName: "doc.on.doc"),
                ) { _ in
                    if let id = ConversationManager.shared.duplicateConversation(identifier: conv.id) {
                        ChatSelection.shared.select(id, options: [.collapseSidebar])
                    }
                },
                UIAction(
                    title: String(localized: "Compress to New Chat"),
                    image: UIImage(systemName: "arrow.down.doc"),
                ) { _ in
                    let model = session.models.chat
                    let name = ModelManager.shared.modelName(identifier: model)
                    guard let model, !name.isEmpty else {
                        let alert = AlertViewController(
                            title: "Model Not Available",
                            message: "Please select a model to generate chat template.",
                        ) { context in
                            context.allowSimpleDispose()
                            context.addAction(title: "OK", attribute: .accent) {
                                context.dispose()
                            }
                        }
                        controller.present(alert, animated: true)
                        return
                    }
                    let alert = AlertViewController(
                        title: "Compress to New Chat",
                        message: "This will use \(name) compress the current conversation into a short summary and create a new chat with it. The original conversation will remain unchanged.",
                    ) { context in
                        context.allowSimpleDispose()
                        context.addAction(title: "Cancel") {
                            context.dispose()
                        }
                        context.addAction(title: "Compress", attribute: .accent) {
                            context.dispose {
                                Indicator.progress(
                                    title: "Compressing",
                                    controller: controller,
                                ) { completion in
                                    let result = await withCheckedContinuation { continuation in
                                        ConversationManager.shared.compressConversation(
                                            identifier: conv.id,
                                            model: model,
                                        ) { convId in
                                            ChatSelection.shared.select(convId, options: [.collapseSidebar])
                                        } completion: { result in
                                            continuation.resume(returning: result)
                                        }
                                    }

                                    switch result {
                                    case .success:
                                        await completion {
                                            Indicator.present(
                                                title: "Conversation Compressed",
                                                preset: .done,
                                                referencingView: view,
                                            )
                                        }
                                    case let .failure(failure):
                                        throw failure
                                    }
                                }
                            }
                        }
                    }
                    controller.present(alert, animated: true)
                },
                UIAction(
                    title: String(localized: "Generate Chat Template"),
                    image: UIImage(systemName: "wind"),
                    attributes: ChatTemplateManager.modelSupportsToolCalls(session.models.chat)
                        ? []
                        : [.disabled],
                ) { _ in
                    let model = session.models.chat
                    let name = ModelManager.shared.modelName(identifier: model)
                    guard let model, !name.isEmpty else {
                        let alert = AlertViewController(
                            title: "Model Not Available",
                            message: "Please select a model to generate chat template.",
                        ) { context in
                            context.allowSimpleDispose()
                            context.addAction(title: "OK", attribute: .accent) {
                                context.dispose()
                            }
                        }
                        controller.present(alert, animated: true)
                        return
                    }
                    let alert = AlertViewController(
                        title: "Generate Chat Template",
                        message: "This will extract your requests from the current conversation using \(name) and save it as a template for later use. This may take some time.",
                    ) { context in
                        context.allowSimpleDispose()
                        context.addAction(title: "Cancel") {
                            context.dispose()
                        }
                        context.addAction(title: "Generate", attribute: .accent) {
                            context.dispose {
                                Indicator.progress(
                                    title: "Generating Template",
                                    controller: controller,
                                ) { completion in
                                    let result = await withCheckedContinuation { continuation in
                                        ChatTemplateManager.shared.createTemplateFromConversation(
                                            conv,
                                            model: model
                                        ) { result in
                                            continuation.resume(returning: result)
                                        }
                                    }

                                    let template = try result.get()
                                    await completion {
                                        ChatTemplateManager.shared.addTemplate(template)
                                        let alert = AlertViewController(
                                            title: "Template Generated",
                                            message: "Template \(template.name) has been successfully generated and saved.",
                                        ) { context in
                                            context.allowSimpleDispose()
                                            context.addAction(title: "OK") {
                                                context.dispose()
                                            }
                                            context.addAction(title: "Edit", attribute: .accent) {
                                                context.dispose {
                                                    let setting = SettingController()
                                                    SettingController.setNextEntryPage(
                                                        .chatTemplateEditor(templateIdentifier: template.id)
                                                    )
                                                    controller.present(setting, animated: true)
                                                }
                                            }
                                        }
                                        controller.present(alert, animated: true)
                                    }
                                }
                            }
                        }
                    }
                    controller.present(alert, animated: true)
                },
            ]))

            sections.append(UIMenu(options: [.displayInline], children: [
                saveImageMenu(session: session, controller: controller, view: view),
                exportDocumentMenu(for: conv.id, view: view),
            ]))
        }

        sections.append(UIMenu(options: [.displayInline], children: [
            UIAction(
                title: String(localized: "Delete"),
                image: UIImage(systemName: "trash"),
                attributes: .destructive,
            ) { _ in
                ConversationManager.shared.deleteConversation(identifier: conv.id)
                if let first = ConversationManager.shared.conversations.value.values.first?.id {
                    ChatSelection.shared.select(first)
                }
            },
        ]))

        return UIMenu(children: sections)
    }

    /// A single-level submenu listing every folder (the current one checked),
    /// followed by creating a folder and removing from the current one.
    func moveToFolderMenu(
        for identifiers: [Conversation.ID],
        controller: UIViewController,
    ) -> UIMenu {
        let memberships = folderMemberships.value
        let currentFolders = Set(identifiers.compactMap { memberships[$0] })
        let isFiled = !currentFolders.isEmpty

        let folderActions: [UIMenuElement] = folders.value.map { folder in
            UIAction(
                title: folder.title,
                image: UIImage(systemName: "folder"),
                state: currentFolders == [folder.id] ? .on : .off,
            ) { _ in
                ConversationManager.shared.moveConversations(identifiers, toFolder: folder.id)
            }
        }

        var management: [UIMenuElement] = [
            UIAction(
                title: String(localized: "New Folder"),
                image: UIImage(systemName: "folder.badge.plus"),
            ) { _ in
                ConversationManager.shared.presentNewFolderAlert(from: controller, moving: identifiers)
            },
        ]
        if isFiled {
            management.append(UIAction(
                title: String(localized: "Remove from Folder"),
                image: UIImage(systemName: "folder.badge.minus"),
            ) { _ in
                ConversationManager.shared.moveConversations(identifiers, toFolder: nil)
            })
        }

        var children: [UIMenuElement] = []
        if !folderActions.isEmpty {
            children.append(UIMenu(options: [.displayInline], children: folderActions))
        }
        children.append(UIMenu(options: [.displayInline], children: management))

        return UIMenu(
            title: String(localized: "Move to Folder"),
            image: UIImage(systemName: "folder"),
            children: children,
        )
    }

    /// Asks for a folder name, creates the folder and files the given
    /// conversations into it.
    func presentNewFolderAlert(
        from controller: UIViewController,
        moving identifiers: [Conversation.ID] = [],
    ) {
        let alert = AlertInputViewController(
            title: "New Folder",
            message: identifiers.isEmpty
                ? "Create an empty folder for conversations."
                : "Create a folder for this conversation.",
            placeholder: "Folder Name",
            text: "",
        ) { text in
            let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
            ConversationManager.shared.createFolder(
                title: title.isEmpty ? String(localized: "New Folder") : title,
                conversations: identifiers,
            )
        }
        controller.present(alert, animated: true)
    }

    private func saveImageMenu(
        session: ConversationSession,
        controller: UIViewController,
        view: UIView,
    ) -> UIMenu {
        UIMenu(
            title: String(localized: "Save Image"),
            image: UIImage(systemName: "text.below.photo"),
            children: ConversationCaptureView.LayoutPreset.allCases.map { preset in
                UIAction(
                    title: preset.displayName,
                    image: UIImage(systemName: "text.below.photo"),
                ) { _ in
                    let captureView = ConversationCaptureView(session: session, preset: preset)
                    Indicator.progress(
                        title: "Rendering Content",
                        controller: controller,
                    ) { completion in
                        let image = await withCheckedContinuation { continuation in
                            Task { @MainActor in
                                captureView.capture(controller: controller) { image in
                                    continuation.resume(returning: image)
                                }
                            }
                        }

                        guard let image, let png = image.pngData() else { throw NSError() }
                        let exporter = DisposableExporter(
                            data: png,
                            name: "Exported-\(Int(Date().timeIntervalSince1970))-\(Int(preset.rawValue))"
                                .sanitizedFileName,
                            pathExtension: "png",
                            title: "Export Image",
                        )
                        await completion { exporter.run(anchor: view) }
                    }
                }
            },
        )
    }

    private func exportDocumentMenu(for identifier: Conversation.ID, view: UIView) -> UIMenu {
        UIMenu(
            title: String(localized: "Export Document"),
            image: UIImage(systemName: "doc"),
            children: [
                UIAction(
                    title: String(localized: "Export Plain Text"),
                    image: UIImage(systemName: "doc.plaintext"),
                ) { _ in
                    ConversationManager.shared.exportConversation(
                        identifier: identifier,
                        exportFormat: .plainText
                    ) { result in
                        switch result {
                        case let .success(content):
                            DisposableExporter(
                                data: Data(content.utf8),
                                name: "Exported-\(Int(Date().timeIntervalSince1970))",
                                pathExtension: "txt",
                                title: "Export Plain Text",
                            ).run(anchor: view, mode: .file)
                        case .failure:
                            Indicator.present(
                                title: "Export Failed",
                                preset: .error,
                                referencingView: view,
                            )
                        }
                    }
                },
                UIAction(
                    title: String(localized: "Export Markdown"),
                    image: UIImage(systemName: "doc.richtext"),
                ) { _ in
                    ConversationManager.shared.exportConversation(
                        identifier: identifier,
                        exportFormat: .markdown
                    ) { result in
                        switch result {
                        case let .success(content):
                            DisposableExporter(
                                data: Data(content.utf8),
                                name: "Exported-\(Int(Date().timeIntervalSince1970))",
                                pathExtension: "md",
                                title: "Export Markdown",
                            ).run(anchor: view, mode: .file)
                        case .failure:
                            Indicator.present(
                                title: "Export Failed",
                                preset: .error,
                                referencingView: view,
                            )
                        }
                    }
                },
            ],
        )
    }

    func folderMenu(
        forFolder identifier: ConversationFolder.ID,
        view: UIView,
    ) -> UIMenu? {
        guard let controller = view.parentViewController else { return nil }
        guard let folder = folders.value.first(where: { $0.id == identifier }) else { return nil }
        let members = folderMemberships.value
            .filter { $0.value == folder.id }
            .map(\.key)

        return UIMenu(children: [
            UIMenu(options: [.displayInline], children: [
                UIAction(
                    title: String(localized: "New Conversation"),
                    image: UIImage(systemName: "plus.bubble"),
                ) { _ in
                    let conv = ConversationManager.shared.createNewConversation()
                    ConversationManager.shared.moveConversations([conv.id], toFolder: folder.id)
                    // The sidebar expands the folder when a new selection lands
                    // inside it, so the new row is revealed and highlighted.
                    ChatSelection.shared.select(conv.id, options: [.collapseSidebar, .focusEditor])
                },
                UIAction(
                    title: String(localized: "Rename Folder"),
                    image: UIImage(systemName: "pencil"),
                ) { _ in
                    let alert = AlertInputViewController(
                        title: "Rename Folder",
                        message: "Set a new name for the folder.",
                        placeholder: "Folder Name",
                        text: folder.title,
                    ) { text in
                        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !title.isEmpty, title != folder.title else { return }
                        ConversationManager.shared.renameFolder(identifier: folder.id, title: title)
                    }
                    controller.present(alert, animated: true)
                },
            ]),
            UIMenu(options: [.displayInline], children: [
                UIAction(
                    title: String(localized: "Delete Folder"),
                    image: UIImage(systemName: "trash"),
                    attributes: .destructive,
                ) { _ in
                    guard !members.isEmpty else {
                        ConversationManager.shared.deleteFolder(identifier: folder.id)
                        return
                    }
                    let alert = AlertViewController(
                        title: "Delete Folder",
                        message: "Keep the conversations in this folder as unfiled chats, or delete them together with the folder.",
                    ) { context in
                        context.allowSimpleDispose()
                        context.addAction(title: "Cancel") {
                            context.dispose()
                        }
                        context.addAction(title: "Delete All") {
                            context.dispose {
                                for member in members {
                                    ConversationManager.shared.deleteConversation(identifier: member)
                                }
                                ConversationManager.shared.deleteFolder(identifier: folder.id)
                            }
                        }
                        context.addAction(title: "Keep Conversations", attribute: .accent) {
                            context.dispose {
                                ConversationManager.shared.deleteFolder(identifier: folder.id)
                            }
                        }
                    }
                    controller.present(alert, animated: true)
                },
            ]),
        ])
    }
}
