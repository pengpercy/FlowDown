//
//  CloudProviderEditorController+Cells.swift
//  FlowDown
//

import UIKit

extension CloudProviderEditorController {
    final class DataSource: UITableViewDiffableDataSource<Section, Row> {
        var headerTitle: (Section) -> String? = { _ in nil }

        override func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? {
            guard let identifier = sectionIdentifier(for: section) else { return nil }
            return headerTitle(identifier)
        }
    }

    func makeDataSource() -> DataSource {
        let dataSource = DataSource(tableView: tableView) { [weak self] tableView, indexPath, row in
            guard let self else { return UITableViewCell() }
            return cell(for: row, in: tableView, at: indexPath)
        }
        dataSource.headerTitle = { section in
            switch section {
            case .preset: String(localized: "Provider")
            case .connection: String(localized: "Connection")
            case .headers: String(localized: "Advanced")
            case .models: String(localized: "Models")
            case .danger: nil
            }
        }
        dataSource.defaultRowAnimation = .fade
        return dataSource
    }

    private func cell(for row: Row, in tableView: UITableView, at indexPath: IndexPath) -> UITableViewCell {
        switch row {
        case .baseURL: return baseURLCell
        case .apiKey: return apiKeyCell
        case .filter: return filterCell
        default: break
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.selectionStyle = .default
        var content = UIListContentConfiguration.valueCell()

        switch row {
        case .preset:
            content.text = String(localized: "Preset")
            content.image = UIImage(systemName: selectedPreset?.icon ?? "slider.horizontal.3")
            cell.accessoryView = makePopUpButton(
                title: selectedPreset?.name ?? String(localized: "Custom"),
                menu: makePresetMenu(),
            )
            cell.selectionStyle = .none
        case .apiType:
            content.text = String(localized: "API Type")
            content.image = UIImage(systemName: provider.contract.icon)
            cell.accessoryView = makePopUpButton(
                title: provider.contract.localizedTitle,
                menu: makeContractMenu(),
            )
            cell.selectionStyle = .none
        case .getAPIKey:
            content = .cell()
            content.text = String(localized: "Get an API Key")
            content.textProperties.color = .accent
            content.image = UIImage(systemName: "arrow.up.forward.square")
        case .testConnection:
            content.text = String(localized: "Test Connection")
            content.textProperties.color = .accent
            content.image = UIImage(systemName: "bolt.horizontal.circle")
            applyLoadState(to: &content, cell: cell, verbose: true)
        case .headers:
            content.text = String(localized: "Custom Headers")
            content.image = UIImage(systemName: "list.bullet.rectangle")
            content.secondaryText = provider.headers.isEmpty
                ? String(localized: "None")
                : provider.headers.keys.sorted().joined(separator: ", ")
            content.secondaryTextProperties.numberOfLines = 1
            cell.accessoryType = .disclosureIndicator
        case .fetchModels:
            content.text = String(localized: "Fetch Model List")
            content.textProperties.color = .accent
            content.image = UIImage(systemName: "arrow.down.circle")
            applyLoadState(to: &content, cell: cell, verbose: false)
        case .addModel:
            content = .cell()
            content.text = String(localized: "Add Model Manually")
            content.textProperties.color = .accent
            content.image = UIImage(systemName: "plus.circle")
        case .toggleAll:
            content = .cell()
            let allSelected = filteredModels.allSatisfy(isSelected)
            content.text = allSelected
                ? String(localized: "Deselect All")
                : String(localized: "Select All")
            content.textProperties.color = .accent
            content.image = UIImage(systemName: allSelected ? "circle" : "checkmark.circle")
        case let .model(identifier):
            content = .subtitleCell()
            content.text = identifier
            content.textProperties.numberOfLines = 1
            content.textProperties.lineBreakMode = .byTruncatingMiddle
            let selected = isSelected(identifier)
            let existing = existingIdentifiers.contains(identifier)
            if existing, !selected {
                content.secondaryText = String(localized: "Will be removed on save")
                content.secondaryTextProperties.color = .systemRed
            } else if !existing, selected {
                content.secondaryText = String(localized: "Will be added on save")
                content.secondaryTextProperties.color = .secondaryLabel
            }
            content.image = UIImage(systemName: selected ? "checkmark.circle.fill" : "circle")
            content.imageProperties.tintColor = selected ? .accent : .tertiaryLabel
        case .deleteProvider:
            content = .cell()
            content.text = String(localized: "Delete Provider")
            content.textProperties.color = .systemRed
            content.textProperties.alignment = .center
        case .baseURL, .apiKey, .filter:
            break
        }
        cell.contentConfiguration = content
        return cell
    }

    private func applyLoadState(
        to content: inout UIListContentConfiguration,
        cell: UITableViewCell,
        verbose: Bool,
    ) {
        switch loadState {
        case .idle:
            break
        case .loading:
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.startAnimating()
            cell.accessoryView = indicator
        case let .loaded(count):
            content.secondaryText = verbose
                ? String(localized: "Connected, \(count) models available")
                : String(localized: "\(count) models")
            content.secondaryTextProperties.color = .systemGreen
        case let .failed(message):
            content.secondaryText = verbose ? message : String(localized: "Failed")
            content.secondaryTextProperties.color = .systemRed
            content.secondaryTextProperties.numberOfLines = 3
            if verbose { content.prefersSideBySideTextAndSecondaryText = false }
        }
    }

    private func makePopUpButton(title: String, menu: UIMenu) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.image = UIImage(systemName: "chevron.up.chevron.down")
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 4
        configuration.preferredSymbolConfigurationForImage = .init(scale: .small)
        configuration.contentInsets = .init(top: 4, leading: 8, bottom: 4, trailing: 0)
        let button = UIButton(configuration: configuration)
        button.menu = menu
        button.showsMenuAsPrimaryAction = true
        button.sizeToFit()
        return button
    }

    private func makePresetMenu() -> UIMenu {
        func action(for preset: CloudProviderPreset) -> UIAction {
            UIAction(
                title: preset.name,
                image: UIImage(systemName: preset.icon),
                state: preset == selectedPreset ? .on : .off,
            ) { [weak self] _ in
                self?.select(preset: preset)
            }
        }
        let custom = UIAction(
            title: String(localized: "Custom"),
            image: UIImage(systemName: "slider.horizontal.3"),
            state: selectedPreset == nil ? .on : .off,
        ) { [weak self] _ in
            self?.select(preset: nil)
        }
        return UIMenu(children: [
            UIMenu(options: .displayInline, children: CloudProviderPreset.cloud.map(action)),
            UIMenu(options: .displayInline, children: CloudProviderPreset.local.map(action)),
            UIMenu(options: .displayInline, children: [custom]),
        ])
    }

    private func makeContractMenu() -> UIMenu {
        UIMenu(children: CloudModelAPIContract.allCases.map { contract in
            let action = UIAction(
                title: contract.localizedTitle,
                image: UIImage(systemName: contract.icon),
                state: contract == provider.contract ? .on : .off,
            ) { [weak self] _ in
                self?.select(contract: contract)
            }
            action.subtitle = contract.localizedDescription
            return action
        })
    }
}

// MARK: - Footers

extension CloudProviderEditorController {
    func footerText(for sectionIndex: Int) -> NSAttributedString? {
        guard let section = dataSource.sectionIdentifier(for: sectionIndex) else { return nil }
        let secondary: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.secondaryLabel]
        switch section {
        case .preset:
            return NSAttributedString(
                string: String(localized: "Pick a known provider to fill in its address, or choose Custom for any compatible server."),
                attributes: secondary,
            )
        case .connection:
            let text = NSMutableAttributedString()
            let endpoint = provider.endpoint
            if !endpoint.isEmpty {
                text.append(NSAttributedString(
                    string: String(localized: "Requests are sent to \(endpoint)"),
                    attributes: secondary,
                ))
            }
            for issue in provider.validationIssues {
                if text.length > 0 { text.append(NSAttributedString(string: "\n")) }
                text.append(NSAttributedString(
                    string: issue.message,
                    attributes: [.foregroundColor: issue.isError ? UIColor.systemRed : UIColor.systemOrange],
                ))
            }
            return text.length > 0 ? text : nil
        case .headers:
            return NSAttributedString(
                string: String(localized: "Custom headers are sent with every request to this provider and can override the default authorization."),
                attributes: secondary,
            )
        case .models:
            let count = selectedModels.count
            let summary = String(localized: "\(count) models selected.")
            let hint = String(localized: "Checked models appear in the model picker. Per-model options such as capabilities and context length can be changed later in each model's settings.")
            return NSAttributedString(string: summary + " " + hint, attributes: secondary)
        case .danger:
            return nil
        }
    }

    func configureFooter(_ footer: UITableViewHeaderFooterView?, text: NSAttributedString) {
        guard let footer else { return }
        var content = UIListContentConfiguration.groupedFooter()
        content.attributedText = text
        footer.contentConfiguration = content
    }

    /// Updates footer text in place so typing in a field never reloads its cell.
    func refreshFooters() {
        var changed = false
        for index in 0 ..< tableView.numberOfSections {
            guard let footer = tableView.footerView(forSection: index),
                  let text = footerText(for: index)
            else { continue }
            configureFooter(footer, text: text)
            changed = true
        }
        guard changed else { return }
        UIView.performWithoutAnimation {
            tableView.performBatchUpdates(nil)
        }
    }
}

// MARK: - Form Field Cell

final class CloudProviderFormFieldCell: UITableViewCell {
    let titleLabel = UILabel()
    let textField = UITextField()

    init(title: String?) {
        super.init(style: .default, reuseIdentifier: nil)
        selectionStyle = .none

        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.clearButtonMode = .whileEditing
        textField.font = .preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true
        textField.delegate = self

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 12
        stack.alignment = .center
        if let title {
            titleLabel.text = title
            titleLabel.font = .preferredFont(forTextStyle: .body)
            titleLabel.adjustsFontForContentSizeCategory = true
            titleLabel.setContentHuggingPriority(.required, for: .horizontal)
            titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
            titleLabel.snp.makeConstraints { make in
                make.width.greaterThanOrEqualTo(96)
            }
            stack.addArrangedSubview(titleLabel)
        } else {
            let icon = UIImageView(image: UIImage(systemName: "magnifyingglass"))
            icon.tintColor = .secondaryLabel
            icon.setContentHuggingPriority(.required, for: .horizontal)
            stack.addArrangedSubview(icon)
        }
        stack.addArrangedSubview(textField)
        contentView.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalTo(contentView.layoutMarginsGuide)
            make.height.greaterThanOrEqualTo(32)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    func addSecureEntryToggle() {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "eye"), for: .normal)
        button.tintColor = .secondaryLabel
        button.accessibilityLabel = String(localized: "Show API Key")
        button.addAction(UIAction { [weak self, weak button] _ in
            guard let self else { return }
            textField.isSecureTextEntry.toggle()
            button?.setImage(UIImage(systemName: textField.isSecureTextEntry ? "eye" : "eye.slash"), for: .normal)
        }, for: .touchUpInside)
        button.setContentHuggingPriority(.required, for: .horizontal)
        textField.clearButtonMode = .never
        (contentView.subviews.first as? UIStackView)?.addArrangedSubview(button)
    }
}

extension CloudProviderFormFieldCell: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
