//
//  Value+ChatLayoutWidth.swift
//  FlowDown
//

import Combine
import ConfigurableKit
import Foundation

/// How wide the conversation column (messages and editor) may grow.
enum ChatLayoutWidth: String, CaseIterable {
    case narrow
    case wide
    case full

    static let storageKey = "app.interface.ChatLayoutWidth"
    static let defaultValue: ChatLayoutWidth = .wide

    /// The applied width; read from layout code on the main thread.
    nonisolated(unsafe) static var current: ChatLayoutWidth = defaultValue

    static let didChange = PassthroughSubject<ChatLayoutWidth, Never>()

    private nonisolated(unsafe) static var cancellables: Set<AnyCancellable> = []

    var title: String.LocalizationValue {
        switch self {
        case .narrow: "Narrow"
        case .wide: "Wide"
        case .full: "Full Width"
        }
    }

    /// The widest a message row's content gets.
    var readableWidth: CGFloat {
        switch self {
        case .narrow: 730
        case .wide: 1080
        // Finite so it can back an Auto Layout constant.
        case .full: 100_000
        }
    }

    /// The widest the editor card gets: the row content plus the card's
    /// 10 pt gap on each side, so the two stay aligned.
    var editorWidth: CGFloat {
        readableWidth + 20
    }

    static let configurableObject: ConfigurableObject = .init(
        icon: "arrow.left.and.right",
        title: "Chat Width",
        explain: "Set how wide messages and the input box may grow in large windows.",
        key: storageKey,
        defaultValue: defaultValue.rawValue,
        annotation: .menu {
            ChatLayoutWidth.allCases.map { input in
                MenuAnnotation.Option(
                    icon: "circle",
                    title: input.title,
                    rawValue: input.rawValue,
                )
            }
        },
    )

    static func subscribeToConfigurableItem() {
        assert(cancellables.isEmpty)
        ConfigurableKit.publisher(forKey: storageKey, type: String.self)
            .receive(on: RunLoop.main)
            .sink { input in
                let value = input.flatMap(ChatLayoutWidth.init(rawValue:)) ?? defaultValue
                guard current != value else { return }
                current = value
                didChange.send(value)
            }
            .store(in: &cancellables)
    }
}
