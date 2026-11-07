//
//  SettingController+TrafficLights.swift
//  FlowDown
//

#if targetEnvironment(macCatalyst)

    import UIKit

    extension SettingController {
        /// The close, minimize and zoom buttons of a Mac window. Settings can
        /// only be closed, so the other two keep their color but take no
        /// clicks and show no glyph.
        final class TrafficLightsView: UIView {
            var onClose: (() -> Void)?

            private let close = Light(kind: .close)
            private let minimize = Light(kind: .minimize)
            private let zoom = Light(kind: .zoom)

            // A native window's 12 pt buttons 8 pt apart, scaled up by the
            // 0.77 the iPad idiom renders at on Mac so they match on screen.
            static let diameter: CGFloat = 16
            static let spacing: CGFloat = 10

            override init(frame: CGRect) {
                super.init(frame: frame)
                close.addAction(UIAction { [weak self] _ in self?.onClose?() }, for: .touchUpInside)
                close.accessibilityLabel = String(localized: "Close")
                minimize.isUserInteractionEnabled = false
                zoom.isUserInteractionEnabled = false

                let stack = UIStackView(arrangedSubviews: [close, minimize, zoom])
                stack.axis = .horizontal
                stack.spacing = Self.spacing
                addSubview(stack)
                stack.snp.makeConstraints { make in
                    make.edges.equalToSuperview()
                }
                for light in [close, minimize, zoom] {
                    light.snp.makeConstraints { make in
                        make.width.height.equalTo(Self.diameter)
                    }
                }

                // Hovering anywhere over the group shows every glyph, as on Mac.
                addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hovered(_:))))
            }

            @available(*, unavailable)
            required init?(coder _: NSCoder) {
                fatalError()
            }

            @objc private func hovered(_ recognizer: UIHoverGestureRecognizer) {
                let showsGlyphs = recognizer.state == .began || recognizer.state == .changed
                close.showsGlyph = showsGlyphs
            }
        }
    }

    private extension SettingController.TrafficLightsView {
        final class Light: UIControl {
            enum Kind {
                case close
                case minimize
                case zoom

                var fill: UIColor {
                    switch self {
                    case .close: .init(red: 1.00, green: 0.37, blue: 0.34, alpha: 1)
                    case .minimize: .init(red: 1.00, green: 0.74, blue: 0.18, alpha: 1)
                    case .zoom: .init(red: 0.16, green: 0.78, blue: 0.25, alpha: 1)
                    }
                }

                var glyph: String {
                    switch self {
                    case .close: "xmark"
                    case .minimize: "minus"
                    case .zoom: "arrow.up.left.and.arrow.down.right"
                    }
                }
            }

            private let kind: Kind
            private let glyphView = UIImageView()

            var showsGlyph = false {
                didSet { updateAppearance() }
            }

            override var isEnabled: Bool {
                didSet { updateAppearance() }
            }

            override var isHighlighted: Bool {
                didSet { updateAppearance() }
            }

            init(kind: Kind) {
                self.kind = kind
                super.init(frame: .zero)
                layer.cornerRadius = SettingController.TrafficLightsView.diameter / 2
                layer.borderWidth = 0.5
                glyphView.image = UIImage(
                    systemName: kind.glyph,
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .bold),
                )
                glyphView.contentMode = .center
                glyphView.tintColor = UIColor.black.withAlphaComponent(0.55)
                glyphView.isUserInteractionEnabled = false
                addSubview(glyphView)
                glyphView.snp.makeConstraints { make in
                    make.edges.equalToSuperview()
                }
                updateAppearance()
            }

            @available(*, unavailable)
            required init?(coder _: NSCoder) {
                fatalError()
            }

            override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
                super.traitCollectionDidChange(previousTraitCollection)
                updateAppearance()
            }

            private func updateAppearance() {
                let disabled = UIColor { traits in
                    traits.userInterfaceStyle == .dark
                        ? .white.withAlphaComponent(0.18)
                        : .black.withAlphaComponent(0.12)
                }
                var fill = isEnabled ? kind.fill : disabled
                if isHighlighted {
                    fill = fill.resolvedColor(with: traitCollection).withAlphaComponent(0.75)
                }
                backgroundColor = fill
                layer.borderColor = (isEnabled
                    ? UIColor.black.withAlphaComponent(0.12)
                    : UIColor.clear).resolvedColor(with: traitCollection).cgColor
                glyphView.isHidden = !(showsGlyph && isEnabled)
            }
        }
    }

#endif
