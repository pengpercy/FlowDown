//
//  SettingController.swift
//  FlowDown
//
//  Created by 秋星桥 on 2025/1/2.
//

import AlertController
import UIKit

#if targetEnvironment(macCatalyst)
    /// Settings on Mac: a sheet sized to the window it opens over, laid out
    /// like a Mac preferences window with a pane list on the left and the
    /// selected pane, with its own navigation stack, on the right.
    class SettingController: AlertBaseController {
        override open var keyCommands: [UIKeyCommand]? {
            [
                UIKeyCommand(
                    title: String(localized: "Back"),
                    action: #selector(escapePressed),
                    input: UIKeyCommand.inputEscape,
                    modifierFlags: [],
                ),
                UIKeyCommand(
                    title: String(localized: "Back"),
                    action: #selector(goBack),
                    input: "[",
                    modifierFlags: .command,
                ),
            ]
        }

        private(set) var content: SplitController!

        private var sheetSizingConstraints: [NSLayoutConstraint] = []

        override convenience init() {
            let split = SplitController()
            // No fixed size up front: the sheet sizes itself against the
            // window it is actually presented into, read once it is there.
            self.init(
                rootViewController: split,
                preferredWidth: nil,
                preferredHeight: nil,
            )

            content = split
            shouldDismissWhenTappedAround = false
            shouldDismissWhenEscapeKeyPressed = true

            split.onClose = { [weak self] in
                self?.dismiss(animated: true)
            }
            if let entry = SettingController.getNextEntryPage() {
                split.show(entry: entry)
            }
        }

        override func viewWillLayoutSubviews() {
            super.viewWillLayoutSubviews()
            // Size against the window the sheet is actually presented into,
            // refreshing on every pass so a live window resize is followed.
            guard let window = view.window else { return }
            let size = ModalWindowSize.resolve(in: window)
            if sheetSizingConstraints.isEmpty {
                let constraints = [
                    contentView.widthAnchor.constraint(equalToConstant: size.width),
                    contentView.heightAnchor.constraint(equalToConstant: size.height),
                ]
                NSLayoutConstraint.activate(constraints)
                sheetSizingConstraints = constraints
            } else {
                sheetSizingConstraints[0].constant = size.width
                sheetSizingConstraints[1].constant = size.height
            }
        }

        override func contentViewDidLoad() {
            super.contentViewDidLoad()
            contentView.backgroundColor = .background
        }

        @objc override func escapePressed() {
            guard presentedViewController == nil else { return }
            if !content.popDetail() {
                dismiss(animated: true)
            }
        }

        @objc private func goBack() {
            guard presentedViewController == nil else { return }
            _ = content.popDetail()
        }

        /// The pane list beside the selected pane.
        class SplitController: UISplitViewController {
            var onClose: (() -> Void)? {
                get { sidebar.onClose }
                set { sidebar.onClose = newValue }
            }

            private let sidebar = SidebarController()
            private let detail = UINavigationController()
            private var paneRoots: [Pane: UIViewController] = [:]

            init() {
                super.init(style: .doubleColumn)
                preferredDisplayMode = .oneBesideSecondary
                preferredSplitBehavior = .tile
                presentsWithGesture = false
                displayModeButtonVisibility = .never
                preferredPrimaryColumnWidth = 210
                minimumPrimaryColumnWidth = 180
                maximumPrimaryColumnWidth = 240

                detail.navigationBar.prefersLargeTitles = false
                detail.view.backgroundColor = .background

                setViewController(sidebar, for: .primary)
                setViewController(detail, for: .secondary)

                sidebar.onSelect = { [weak self] pane in
                    self?.show(pane: pane)
                }
                show(pane: .general)
            }

            @available(*, unavailable)
            required init?(coder _: NSCoder) {
                fatalError()
            }

            override func viewDidLoad() {
                super.viewDidLoad()
                view.backgroundColor = .background
                view.alpha = 0
            }

            override func viewWillAppear(_ animated: Bool) {
                super.viewWillAppear(animated)
                // Fade in once the sheet has its size, so the columns are not
                // seen laying out at the presentation's starting frame.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(100))
                    UIView.animate(withDuration: 0.25) {
                        self.view.alpha = 1
                    }
                }
            }

            override func viewDidAppear(_ animated: Bool) {
                super.viewDidAppear(animated)
                view.window?.firstResponder()?.resignFirstResponder()
            }

            /// Opens a pane, then pushes the entry's own page on top of it.
            func show(entry: EntryPage) {
                let destination = entry.destination
                show(pane: destination.pane)
                if let page = destination.page {
                    detail.pushViewController(page, animated: false)
                }
            }

            func show(pane: Pane) {
                sidebar.select(pane)
                let root = paneRoots[pane] ?? pane.makeController()
                paneRoots[pane] = root
                detail.setViewControllers([root], animated: false)
            }

            /// Steps back one page in the selected pane; false at its root.
            func popDetail() -> Bool {
                guard detail.presentedViewController == nil,
                      detail.viewControllers.count > 1
                else { return false }
                detail.popViewController(animated: true)
                return true
            }
        }
    }
#else
    class SettingController: UINavigationController {
        init() {
            super.init(rootViewController: SettingContent())
            navigationBar.prefersLargeTitles = false
            modalPresentationStyle = .formSheet
            modalTransitionStyle = .coverVertical
            view.backgroundColor = .background
        }

        // UINavigationController derives its preferred content size from the
        // top view controller, so pages that stack a search bar under the
        // navigation bar (Model, Memory, Logs) grow the form sheet on push
        // and shrink it back on pop. Pin the size so the sheet stays put.
        override var preferredContentSize: CGSize {
            get { .init(width: 550, height: 550) }
            set { _ = newValue }
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }
    }
#endif

extension SettingController {
    enum EntryPage {
        case general
        case inference
        case chatTemplateEditor(templateIdentifier: ChatTemplate.ID)
        case modelManagement
        case modelEditor(model: ModelManager.ModelIdentifier)
        case tools
        case mcp
        case memory
        case dataControl
        case permissionList
        case contactUs
    }

    private static var nextEntryPage: EntryPage?

    static func setNextEntryPage(_ page: EntryPage) {
        nextEntryPage = page
    }

    static func getNextEntryPage() -> EntryPage? {
        if let ret = nextEntryPage {
            nextEntryPage = nil
            return ret
        }
        return nil
    }
}
