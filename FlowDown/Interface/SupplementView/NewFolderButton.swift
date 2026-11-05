//
//  NewFolderButton.swift
//  FlowDown
//
//  Created by 秋星桥 on 8/22/26.
//

import UIKit

/// The compact "+" shown next to the sidebar's Folders header.
final class NewFolderButton: UIButton {
    init() {
        super.init(frame: .zero)
        setImage(
            UIImage(
                systemName: "plus",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold),
            ),
            for: .normal,
        )
        tintColor = .secondaryLabel
        accessibilityLabel = String(localized: "New Folder")
        toolTip = String(localized: "New Folder")
        isPointerInteractionEnabled = true
        addTarget(self, action: #selector(createFolder), for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    @objc private func createFolder() {
        guard let controller = parentViewController else { return }
        ConversationManager.shared.presentNewFolderAlert(from: controller)
    }
}
