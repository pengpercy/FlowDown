//
//  CloudProviderEditorController.swift
//  FlowDown
//

import AlertController
import Storage
import UIKit

/// Adds or edits a model provider in one flat form: connection, headers and the
/// models to enable. Changes apply only when the user taps Save.
final class CloudProviderEditorController: UIViewController {
    enum Section: Hashable {
        case preset
        case connection
        case headers
        case models
        case danger
    }

    enum Row: Hashable {
        case preset
        case apiType
        case baseURL
        case apiKey
        case getAPIKey
        case testConnection
        case headers
        case fetchModels
        case addModel
        case filter
        case toggleAll
        case model(String)
        case deleteProvider
    }

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded(count: Int)
        case failed(String)
    }

    let isNewProvider: Bool
    var provider: CloudProvider
    var selectedPreset: CloudProviderPreset?
    var headersEdited = false
    var availableModels: [String] = []
    var selectedModels: [String] = []
    let existingIdentifiers: Set<String>
    var loadState: LoadState = .idle
    var loadTask: Task<Void, Never>?
    var filterText = ""
    var hasChanges = false {
        didSet { isModalInPresentation = hasChanges }
    }

    let tableView = UITableView(frame: .zero, style: .insetGrouped)
    lazy var dataSource: DataSource = makeDataSource()

    lazy var baseURLCell = CloudProviderFormFieldCell(title: String(localized: "Base URL")).with {
        $0.textField.placeholder = "https://api.example.com/v1"
        $0.textField.keyboardType = .URL
        $0.textField.textContentType = .URL
        $0.textField.addTarget(self, action: #selector(baseURLChanged), for: .editingChanged)
    }

    lazy var apiKeyCell = CloudProviderFormFieldCell(title: String(localized: "API Key")).with {
        $0.textField.placeholder = String(localized: "Paste your API key")
        $0.textField.isSecureTextEntry = true
        $0.textField.textContentType = .password
        $0.textField.addTarget(self, action: #selector(apiKeyChanged), for: .editingChanged)
        $0.addSecureEntryToggle()
    }

    lazy var filterCell = CloudProviderFormFieldCell(title: nil).with {
        $0.textField.placeholder = String(localized: "Filter models")
        $0.textField.clearButtonMode = .whileEditing
        $0.textField.returnKeyType = .done
        $0.textField.addTarget(self, action: #selector(filterChanged), for: .editingChanged)
    }

    /// - Parameters:
    ///   - provider: The provider to edit, or nil to add a new one.
    ///   - preset: Defaults for a new provider.
    init(provider: CloudProvider?, preset: CloudProviderPreset? = nil) {
        if let provider {
            isNewProvider = false
            self.provider = provider
            selectedPreset = provider.preset
            existingIdentifiers = Set(provider.modelIdentifiers)
            selectedModels = Self.unique(provider.modelIdentifiers)
            availableModels = Self.unique(provider.modelIdentifiers).sorted()
        } else {
            isNewProvider = true
            let preset = preset ?? .openAI
            self.provider = CloudProvider(preset: preset)
            selectedPreset = preset
            existingIdentifiers = []
        }
        super.init(nibName: nil, bundle: nil)
        title = isNewProvider
            ? String(localized: "Add Provider")
            : self.provider.displayName
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    deinit {
        loadTask?.cancel()
    }

    /// Presents the editor in its own navigation stack as a sheet.
    static func present(
        from presenter: UIViewController,
        provider: CloudProvider?,
        preset: CloudProviderPreset? = nil,
    ) {
        let editor = CloudProviderEditorController(provider: provider, preset: preset)
        let navigation = UINavigationController(rootViewController: editor)
        navigation.modalPresentationStyle = .formSheet
        navigation.preferredContentSize = CGSize(width: 620, height: 720)
        presenter.present(navigation, animated: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .background
        tableView.backgroundColor = .clear
        tableView.delegate = self
        tableView.keyboardDismissMode = .interactive
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.register(UITableViewHeaderFooterView.self, forHeaderFooterViewReuseIdentifier: "Footer")
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .cancel,
            primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) },
        )
        let saveItem = UIBarButtonItem(
            title: String(localized: "Save"),
            primaryAction: UIAction { [weak self] _ in self?.save() },
        )
        saveItem.style = .done
        navigationItem.rightBarButtonItem = saveItem

        baseURLCell.textField.text = provider.baseURL
        apiKeyCell.textField.text = provider.apiKey

        applySnapshot(animated: false)

        if !isNewProvider, provider.canSave {
            loadModels()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if isNewProvider, provider.apiKey.isEmpty, selectedPreset?.requiresAPIKey ?? true {
            apiKeyCell.textField.becomeFirstResponder()
        }
    }
}

// MARK: - Data

extension CloudProviderEditorController {
    static func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    var filteredModels: [String] {
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return availableModels }
        return availableModels.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    func isSelected(_ identifier: String) -> Bool {
        selectedModels.contains(identifier)
    }

    func setSelected(_ identifiers: [String], selected: Bool) {
        if selected {
            selectedModels = Self.unique(selectedModels + identifiers)
        } else {
            let removing = Set(identifiers)
            selectedModels.removeAll { removing.contains($0) }
        }
        hasChanges = true
    }

    func mergeAvailableModels(_ identifiers: [String]) {
        availableModels = Self.unique(availableModels + identifiers).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    func sections() -> [Section] {
        var result: [Section] = []
        if isNewProvider { result.append(.preset) }
        result += [.connection, .headers, .models]
        if !isNewProvider { result.append(.danger) }
        return result
    }

    func rows(for section: Section) -> [Row] {
        switch section {
        case .preset:
            return [.preset]
        case .connection:
            var rows: [Row] = [.apiType, .baseURL, .apiKey]
            if selectedPreset?.apiKeyPage != nil { rows.append(.getAPIKey) }
            rows.append(.testConnection)
            return rows
        case .headers:
            return [.headers]
        case .models:
            var rows: [Row] = [.fetchModels, .addModel]
            if availableModels.count > 8 { rows.append(.filter) }
            if !filteredModels.isEmpty { rows.append(.toggleAll) }
            rows += filteredModels.map(Row.model)
            return rows
        case .danger:
            return [.deleteProvider]
        }
    }

    func applySnapshot(animated: Bool = true, reconfiguring: [Row] = []) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()
        for section in sections() {
            snapshot.appendSections([section])
            snapshot.appendItems(rows(for: section), toSection: section)
        }
        let reconfigure = reconfiguring.filter { snapshot.indexOfItem($0) != nil }
        if !reconfigure.isEmpty { snapshot.reconfigureItems(reconfigure) }
        dataSource.apply(snapshot, animatingDifferences: animated)
        refreshFooters()
    }
}

// MARK: - Actions

extension CloudProviderEditorController {
    @objc func baseURLChanged() {
        provider.baseURL = baseURLCell.textField.text ?? ""
        // Pasting a full endpoint picks the matching API type.
        if let inferred = CloudModelAPIContract.inferred(fromEndpoint: provider.baseURL),
           inferred != provider.contract
        {
            provider.contract = inferred
            applySnapshot(animated: false, reconfiguring: [.apiType])
        }
        connectionDidChange()
    }

    @objc func apiKeyChanged() {
        provider.apiKey = (apiKeyCell.textField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        connectionDidChange()
    }

    @objc func filterChanged() {
        filterText = filterCell.textField.text ?? ""
        applySnapshot(animated: false)
    }

    func connectionDidChange() {
        hasChanges = true
        if loadState != .idle {
            loadTask?.cancel()
            loadState = .idle
            applySnapshot(animated: false, reconfiguring: [.testConnection, .fetchModels])
        }
        refreshFooters()
    }

    func select(preset: CloudProviderPreset?) {
        selectedPreset = preset
        if let preset {
            provider.contract = preset.contract
            provider.baseURL = preset.baseURL
            provider.headers = preset.headers
        } else {
            provider.baseURL = ""
            provider.headers = [:]
        }
        headersEdited = false
        baseURLCell.textField.text = provider.baseURL
        loadTask?.cancel()
        loadState = .idle
        availableModels = []
        selectedModels = []
        filterText = ""
        filterCell.textField.text = ""
        hasChanges = true
        applySnapshot(reconfiguring: [.preset, .apiType, .headers, .testConnection, .fetchModels])
        if preset == nil {
            baseURLCell.textField.becomeFirstResponder()
        }
    }

    func select(contract: CloudModelAPIContract) {
        guard contract != provider.contract else { return }
        provider.contract = contract
        if CloudModelAPIContract.inferred(fromEndpoint: provider.baseURL) != nil {
            provider.baseURL = CloudProvider.resolveEndpoint(baseURL: provider.baseURL, contract: contract)
            baseURLCell.textField.text = provider.baseURL
        }
        applySnapshot(animated: false, reconfiguring: [.apiType])
        connectionDidChange()
    }

    func loadModels() {
        view.endEditing(true)
        guard provider.canSave else {
            presentMessage(
                title: String(localized: "Check Connection Settings"),
                message: provider.validationIssues.first(where: \.isError)?.message ?? "",
            )
            return
        }
        loadTask?.cancel()
        loadState = .loading
        applySnapshot(animated: false, reconfiguring: [.testConnection, .fetchModels])
        let request = provider
        loadTask = Task { @MainActor [weak self] in
            let result: Result<[String], Error>
            do {
                let identifiers = try await ModelManager.shared.fetchProviderModels(request)
                result = .success(identifiers)
            } catch {
                result = .failure(error)
            }
            guard let self, !Task.isCancelled else { return }
            switch result {
            case let .success(identifiers):
                mergeAvailableModels(identifiers)
                loadState = .loaded(count: identifiers.count)
            case let .failure(error):
                loadState = .failed(error.localizedDescription)
            }
            applySnapshot(reconfiguring: [.testConnection, .fetchModels])
        }
    }

    func addModelManually() {
        let input = AlertInputViewController(
            title: "Add Model",
            message: "Enter the model identifier exactly as the provider documents it.",
            placeholder: "Model Identifier",
            text: "",
        ) { [weak self] output in
            guard let self else { return }
            let identifiers = output
                .components(separatedBy: CharacterSet(charactersIn: ",\n"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !identifiers.isEmpty else { return }
            mergeAvailableModels(identifiers)
            setSelected(identifiers, selected: true)
            applySnapshot(reconfiguring: identifiers.map(Row.model))
        }
        present(input, animated: true)
    }

    func editHeaders() {
        let data = try? JSONSerialization.data(withJSONObject: provider.headers, options: [.prettyPrinted, .sortedKeys])
        var text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        if text.isEmpty { text = "{}" }
        let editor = JsonStringMapEditorController(text: text)
        editor.title = String(localized: "Custom Headers")
        editor.collectEditedContent { [weak self] result in
            guard let self,
                  let data = result.data(using: .utf8),
                  let object = try? JSONDecoder().decode([String: String].self, from: data)
            else { return }
            provider.headers = object
            headersEdited = true
            hasChanges = true
            applySnapshot(animated: false, reconfiguring: [.headers])
        }
        navigationController?.pushViewController(editor, animated: true)
    }

    func deleteProvider() {
        let count = provider.modelIDs.count
        presentDeleteConfirmation(
            title: "Delete Provider",
            message: "Delete this provider and its \(count) models? Conversations keep their messages.",
        ) { [weak self] in
            guard let self else { return }
            ModelManager.shared.removeCloudProvider(provider)
            dismiss(animated: true)
        }
    }

    func save() {
        view.endEditing(true)
        if let error = provider.validationIssues.first(where: \.isError) {
            presentMessage(title: String(localized: "Check Connection Settings"), message: error.message)
            return
        }
        guard !selectedModels.isEmpty else {
            let message = isNewProvider
                ? String(localized: "Fetch the model list or add a model manually, then check the models you want to use.")
                : String(localized: "Check at least one model. To remove this provider, use Delete Provider.")
            presentMessage(title: String(localized: "No Models Selected"), message: message)
            return
        }

        var target = provider
        var selection = selectedModels
        var applyHeaders = headersEdited || isNewProvider
        if isNewProvider,
           let existing = ModelManager.shared.cloudProviders.first(where: { $0.id == provider.id })
        {
            // Same endpoint and key as an existing provider: add to it instead of duplicating.
            target.modelIDs = existing.modelIDs
            selection = Self.unique(existing.modelIdentifiers + selection)
            applyHeaders = headersEdited
        }

        let existing = target.modelIDs.compactMap { id in
            ModelManager.shared.cloudModel(identifier: id).map { (id: $0.id, identifier: $0.model_identifier) }
        }
        let plan = CloudProvider.plan(existing: existing, selectedIdentifiers: selection)
        let commit = { [weak self] in
            ModelManager.shared.saveCloudProvider(target, selectedIdentifiers: selection, applyHeaders: applyHeaders)
            self?.dismiss(animated: true)
        }
        guard !plan.remove.isEmpty else {
            commit()
            return
        }
        let count = plan.remove.count
        let alert = AlertViewController(
            title: String(localized: "Remove Unchecked Models"),
            message: String(localized: "\(count) unchecked models will be removed from FlowDown."),
        ) { context in
            context.addAction(title: "Cancel") { context.dispose() }
            context.addAction(title: "Save", attribute: .accent) {
                context.dispose { commit() }
            }
        }
        present(alert, animated: true)
    }

    func presentMessage(title: String, message: String) {
        let alert = AlertViewController(title: title, message: message) { context in
            context.allowSimpleDispose()
            context.addAction(title: "OK", attribute: .accent) { context.dispose() }
        }
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDelegate

extension CloudProviderEditorController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let row = dataSource.itemIdentifier(for: indexPath) else { return }
        switch row {
        case .baseURL:
            baseURLCell.textField.becomeFirstResponder()
        case .apiKey:
            apiKeyCell.textField.becomeFirstResponder()
        case .filter:
            filterCell.textField.becomeFirstResponder()
        case .getAPIKey:
            if let url = selectedPreset?.apiKeyPage { UIApplication.shared.open(url) }
        case .testConnection, .fetchModels:
            if loadState != .loading { loadModels() }
        case .addModel:
            addModelManually()
        case .headers:
            editHeaders()
        case .toggleAll:
            let shown = filteredModels
            let allSelected = shown.allSatisfy(isSelected)
            setSelected(shown, selected: !allSelected)
            applySnapshot(animated: false, reconfiguring: [.toggleAll] + shown.map(Row.model))
        case let .model(identifier):
            setSelected([identifier], selected: !isSelected(identifier))
            applySnapshot(animated: false, reconfiguring: [.model(identifier), .toggleAll])
        case .deleteProvider:
            deleteProvider()
        case .preset, .apiType:
            break
        }
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard let text = footerText(for: section) else { return nil }
        let footer = tableView.dequeueReusableHeaderFooterView(withIdentifier: "Footer")
        configureFooter(footer, text: text)
        return footer
    }

    func tableView(_: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        footerText(for: section) == nil ? 8 : UITableView.automaticDimension
    }
}
