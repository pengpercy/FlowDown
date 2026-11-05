//
//  ModelController+Cell.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/27/25.
//

import ConfigurableKit
import UIKit

extension CloudProvider {
    /// Secondary line for the provider row in model management.
    var listDescriptions: [String] {
        var items = [contract.localizedTitle]
        items.append(String(localized: "\(modelIDs.count) models"))
        if let host = URL(string: endpoint)?.host, host != displayName {
            items.append(host)
        }
        return items
    }
}

extension SettingController.SettingContent.ModelController {
    class ModelCell: UITableViewCell {
        let content = ConfigurablePageView { fatalError() }

        override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
            super.init(style: style, reuseIdentifier: reuseIdentifier)
            backgroundColor = .clear
            selectionStyle = .none
            clipsToBounds = true
            let wrappingView = AutoLayoutMarginView(content)
            contentView.addSubview(wrappingView)
            wrappingView.snp.makeConstraints { make in
                make.edges.equalToSuperview()
            }
            content.configure(icon: .modelLocal)
            content.isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        enum ModelType {
            case provider
            case local
            case cloud

            var image: UIImage {
                switch self {
                case .provider: UIImage(systemName: "server.rack") ?? .modelCloud
                case .local: .modelLocal
                case .cloud: .modelCloud
                }
            }
        }

        func update(type: ModelType, name: String, descriptions: [String]) {
            content.configure(icon: type.image)
            content.configure(title: name)
            let desc = descriptions.joined(separator: ", ")
            content.configure(description: desc)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            preservesSuperviewLayoutMargins = false
            separatorInset = UIEdgeInsets.zero
            layoutMargins = UIEdgeInsets.zero
        }
    }
}
