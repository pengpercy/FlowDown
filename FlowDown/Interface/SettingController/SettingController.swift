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
                UIKeyCommand(
                    title: String(localized: "Forward"),
                    action: #selector(goForward),
                    input: "]",
                    modifierFlags: .command,
                ),
            ]
        }

        private(set) var content: SplitController!

        private let trafficLights = TrafficLightsView()

        private var sheetSizingConstraints: [NSLayoutConstraint] = []

        /// Height of the band along the top of the sheet that drags it, the
        /// same as the pane's navigation bar.
        static let dragBandHeight: CGFloat = 52

        /// How far the sheet has been dragged from the center of the window.
        private var dragOffset: CGPoint = .zero
        private var centerXConstraint: NSLayoutConstraint?
        private var centerYConstraint: NSLayoutConstraint?

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

            if let entry = SettingController.getNextEntryPage() {
                split.show(entry: entry)
            }
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            installDragging()

            // Above both columns, so neither column's bar can cover them,
            // and centered in the top band as in a window's toolbar.
            trafficLights.onClose = { [weak self] in
                self?.dismiss(animated: true)
            }
            contentView.addSubview(trafficLights)
            trafficLights.snp.makeConstraints { make in
                make.leading.equalToSuperview().inset(20)
                make.centerY.equalTo(contentView.snp.top).offset(Self.dragBandHeight / 2)
            }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            contentView.bringSubviewToFront(trafficLights)
        }

        override func viewWillLayoutSubviews() {
            super.viewWillLayoutSubviews()
            clampDragOffset()
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

        @objc private func goForward() {
            guard presentedViewController == nil else { return }
            content.forwardDetail()
        }

        override func dimmingViewTapped() {
            // The base class nudges the sheet with a transform, which would
            // fight the drag offset; a click outside simply does nothing.
        }

        // MARK: - Dragging

        /// Lets the sheet be dragged by its top band, like a window by its
        /// title bar, while staying inside the main window.
        private func installDragging() {
            // Replace the base class's fixed centering with centering that
            // carries the drag offset. It sits below the required edge
            // constraints, which keep the sheet inside the window.
            for constraint in view.constraints where constraint.firstItem === contentView
                && (constraint.firstAttribute == .centerX || constraint.firstAttribute == .centerY)
            {
                constraint.isActive = false
            }
            let centerX = contentView.centerXAnchor.constraint(equalTo: contentLayoutGuide.centerXAnchor)
            let centerY = contentView.centerYAnchor.constraint(equalTo: contentLayoutGuide.centerYAnchor)
            centerX.priority = .defaultHigh
            centerY.priority = .defaultHigh
            NSLayoutConstraint.activate([centerX, centerY])
            centerXConstraint = centerX
            centerYConstraint = centerY

            let pan = UIPanGestureRecognizer(target: self, action: #selector(handleDrag(_:)))
            pan.delegate = self
            contentView.addGestureRecognizer(pan)
        }

        @objc private func handleDrag(_ recognizer: UIPanGestureRecognizer) {
            guard recognizer.state == .changed else { return }
            let translation = recognizer.translation(in: view)
            recognizer.setTranslation(.zero, in: view)
            dragOffset.x += translation.x
            dragOffset.y += translation.y
            clampDragOffset()
            view.layoutIfNeeded()
        }

        /// Keeps the offset within the room the window leaves around the
        /// sheet, so a smaller window pulls a dragged sheet back into view.
        private func clampDragOffset() {
            let guide = contentLayoutGuide.layoutFrame
            let size = contentView.bounds.size
            if guide.width > 0, size.width > 0 {
                let roomX = max(0, (guide.width - size.width) / 2)
                let roomY = max(0, (guide.height - size.height) / 2)
                dragOffset.x = min(max(dragOffset.x, -roomX), roomX)
                dragOffset.y = min(max(dragOffset.y, -roomY), roomY)
            }
            centerXConstraint?.constant = dragOffset.x
            centerYConstraint?.constant = dragOffset.y
        }

        /// The pane list beside the selected pane.
        class SplitController: UISplitViewController {
            let sidebar = SidebarController()
            private let detail = DetailNavigationController()
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
                // The bar reads as part of the pane, with its title beside
                // the arrows, as in a Mac settings window's toolbar.
                let appearance = UINavigationBarAppearance()
                appearance.configureWithOpaqueBackground()
                appearance.backgroundColor = .background
                appearance.shadowColor = .clear
                appearance.titleTextAttributes = [
                    .font: UIFont.preferredFont(forTextStyle: .title3).bold,
                    .foregroundColor: UIColor.label,
                ]
                detail.navigationBar.standardAppearance = appearance
                detail.navigationBar.scrollEdgeAppearance = appearance
                detail.navigationBar.compactAppearance = appearance

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
                detail.reset(to: root)
            }

            /// Steps back one page in the selected pane; false at its root.
            func popDetail() -> Bool {
                guard detail.presentedViewController == nil,
                      detail.viewControllers.count > 1
                else { return false }
                detail.goBack()
                return true
            }

            func forwardDetail() {
                guard detail.presentedViewController == nil else { return }
                detail.goForward()
            }
        }

        /// The pane's page stack, with back and forward arrows in place of
        /// the titled back button, as in a Mac settings window.
        class DetailNavigationController: UINavigationController, UINavigationControllerDelegate {
            /// Pages left with Back, newest last, so Forward can return.
            private var forwardStack: [UIViewController] = []
            private var isGoingForward = false

            init() {
                super.init(nibName: nil, bundle: nil)
                delegate = self
            }

            @available(*, unavailable)
            required init?(coder _: NSCoder) {
                fatalError()
            }

            func reset(to root: UIViewController) {
                forwardStack.removeAll()
                setViewControllers([root], animated: false)
                updateArrows()
            }

            func goBack() {
                guard viewControllers.count > 1 else { return }
                popViewController(animated: true)
            }

            func goForward() {
                guard let next = forwardStack.popLast() else { return }
                isGoingForward = true
                pushViewController(next, animated: true)
                isGoingForward = false
            }

            override func pushViewController(_ viewController: UIViewController, animated: Bool) {
                // Opening a new page ends the forward history, as in a browser.
                if !isGoingForward { forwardStack.removeAll() }
                super.pushViewController(viewController, animated: animated)
                updateArrows()
            }

            @discardableResult
            override func popViewController(animated: Bool) -> UIViewController? {
                let popped = super.popViewController(animated: animated)
                if let popped { forwardStack.append(popped) }
                updateArrows()
                return popped
            }

            func navigationController(_: UINavigationController, willShow viewController: UIViewController, animated _: Bool) {
                updateArrows(on: viewController)
                // Group each section's rows into a card, as Mac settings do.
                if let page = viewController as? StackScrollController, !page.arrangesSectionsInCards {
                    page.arrangesSectionsInCards = true
                    page.view.setNeedsLayout()
                }
            }

            func navigationController(_: UINavigationController, didShow _: UIViewController, animated _: Bool) {
                // A cancelled interactive pop leaves its page on the stack.
                forwardStack.removeAll { viewControllers.contains($0) }
                updateArrows()
            }

            private func updateArrows(on page: UIViewController? = nil) {
                guard let page = page ?? topViewController else { return }
                let item = page.navigationItem
                // Pages that hide Back (an editor saved only by Done) or put
                // their own control there keep it.
                let ownsLeadingItems = item.leftBarButtonItems?.contains { $0.tag == Self.arrowTag } ?? true
                guard ownsLeadingItems, !(item.hidesBackButton && item.leftBarButtonItems == nil) else { return }

                let canGoBack = (viewControllers.firstIndex(of: page) ?? 0) > 0
                let back = UIBarButtonItem(
                    image: UIImage(systemName: "chevron.left"),
                    primaryAction: UIAction { [weak self] _ in self?.goBack() },
                )
                back.isEnabled = canGoBack
                back.accessibilityLabel = String(localized: "Back")
                let forward = UIBarButtonItem(
                    image: UIImage(systemName: "chevron.right"),
                    primaryAction: UIAction { [weak self] _ in self?.goForward() },
                )
                forward.isEnabled = page === topViewController && !forwardStack.isEmpty
                forward.accessibilityLabel = String(localized: "Forward")
                for arrow in [back, forward] {
                    arrow.tag = Self.arrowTag
                    arrow.tintColor = .label
                }
                item.hidesBackButton = true
                item.leftItemsSupplementBackButton = false
                item.leftBarButtonItems = [back, forward]
                item.style = .browser
            }

            private static let arrowTag = 0x46_44_4E_56
        }
    }
    extension SettingController: UIGestureRecognizerDelegate {
        func gestureRecognizer(_: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            // The top band drags, and so does the sidebar's empty space, but
            // never from a button.
            let sidebar = content.sidebar
            let inSidebar = sidebar.isViewLoaded
                && sidebar.view.bounds.contains(touch.location(in: sidebar.view))
            if inSidebar {
                guard touch.location(in: contentView).y < Self.dragBandHeight
                    || sidebar.isEmptySpace(at: touch.location(in: sidebar.view))
                else { return false }
            } else {
                guard touch.location(in: contentView).y < Self.dragBandHeight else { return false }
            }
            var view = touch.view
            while let current = view, current !== contentView {
                if current is UIControl { return false }
                view = current.superview
            }
            return true
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
