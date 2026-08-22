//
//  NewFolderButton.swift
//  FlowDown
//
//  Created by 秋星桥 on 8/22/26.
//

import AlertController
import UIKit

final class NewFolderButton: UIButton {
    init() {
        super.init(frame: .zero)
        setImage(UIImage(systemName: "folder.badge.plus"), for: .normal)
        tintColor = .label
        accessibilityLabel = String(localized: "New Folder")
        addTarget(self, action: #selector(createFolder), for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    @objc private func createFolder() {
        guard let controller = parentViewController else { return }
        let alert = AlertInputViewController(
            title: String(localized: "New Folder"),
            message: String(localized: "Create an empty folder for conversations."),
            placeholder: String(localized: "Folder Name"),
            text: "",
        ) { text in
            let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
            ConversationManager.shared.createFolder(title: title.isEmpty ? String(localized: "New Folder") : title)
        }
        controller.present(alert, animated: true)
    }
}
