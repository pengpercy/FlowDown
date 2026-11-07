//
//  SettingController+Pane.swift
//  FlowDown
//

import UIKit

extension SettingController {
    /// A top-level page of Settings, listed in the Settings sidebar.
    enum Pane: CaseIterable {
        case general
        case inference
        case model
        case tools
        case memory
        case dataControl
        case permission
        case support

        var icon: String {
            switch self {
            case .general: "gear"
            case .inference: "bolt"
            case .model: "doc.text.magnifyingglass"
            case .tools: "hammer"
            case .memory: "moon.stars"
            case .dataControl: "lock.shield"
            case .permission: "key"
            case .support: "envelope"
            }
        }

        var title: String {
            switch self {
            case .general: String(localized: "General")
            case .inference: String(localized: "Inference")
            case .model: String(localized: "Model")
            case .tools: String(localized: "Tools")
            case .memory: String(localized: "Memory")
            case .dataControl: String(localized: "Data")
            case .permission: String(localized: "Permission")
            case .support: String(localized: "Support")
            }
        }

        func makeController() -> UIViewController {
            switch self {
            case .general: SettingContent.GeneralController()
            case .inference: SettingContent.InferenceController()
            case .model: SettingContent.ModelController()
            case .tools: SettingContent.ToolsController()
            case .memory: SettingContent.MemoryController()
            case .dataControl: SettingContent.DataControlController()
            case .permission: SettingContent.PermissionController()
            case .support: SettingContent.SupportController()
            }
        }
    }

    /// Presents Settings over `presenter`, optionally opened at `entry`.
    @MainActor
    static func open(_ entry: EntryPage? = nil, from presenter: UIViewController?) {
        if let entry { setNextEntryPage(entry) }
        presenter?.present(SettingController(), animated: true)
    }
}

extension SettingController.EntryPage {
    /// The sidebar pane an entry belongs to, and the page to push over it.
    var destination: (pane: SettingController.Pane, page: UIViewController?) {
        switch self {
        case .general: (.general, nil)
        case .inference: (.inference, nil)
        case let .chatTemplateEditor(templateIdentifier):
            (.inference, ChatTemplateEditorController(templateIdentifier: templateIdentifier))
        case .modelManagement: (.model, nil)
        case .modelEditor: (.model, controller)
        case .tools: (.tools, nil)
        case .mcp: (.tools, SettingController.SettingContent.MCPController())
        case .memory: (.memory, nil)
        case .dataControl: (.dataControl, nil)
        case .permissionList: (.permission, nil)
        case .contactUs: (.support, nil)
        }
    }
}
