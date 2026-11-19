import UIKit
import Symbols

func makeLabel(_ style: UIFont.TextStyle, text: String? = nil, color: UIColor = .label) -> UILabel {
    let label = UILabel()
    label.font = .preferredFont(forTextStyle: style)
    label.adjustsFontForContentSizeCategory = true
    label.text = text
    label.textColor = color
    label.numberOfLines = 0
    return label
}

func textButton(_ title: String, symbol: String? = nil, prominent: Bool = false,
                action: @escaping () -> Void) -> UIButton {
    var configuration = prominent ? UIButton.Configuration.prominentGlass() : .glass()
    configuration.title = title
    configuration.image = symbol.flatMap { UIImage(systemName: $0) }
    configuration.imagePadding = 8
    configuration.buttonSize = .large
    return UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
}

extension UIView {
    func pin(to parent: UIView, insets: NSDirectionalEdgeInsets = .zero) {
        translatesAutoresizingMaskIntoConstraints = false
        if superview !== parent { parent.addSubview(self) }
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: parent.topAnchor, constant: insets.top),
            bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -insets.bottom),
            leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: insets.leading),
            trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -insets.trailing)
        ])
    }
}

extension UIViewController {
    func embed(_ child: UIViewController, in parent: UIView) {
        addChild(child)
        child.view.pin(to: parent)
        child.didMove(toParent: self)
    }

    func showMessage(_ message: String, title: String = "Кадр") {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Гаразд", style: .default))
        present(alert, animated: true)
    }
}

extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        fontDescriptor.withSymbolicTraits(traits).map { UIFont(descriptor: $0, size: 0) } ?? self
    }
}

final class GlyphButton: UIButton {
    init(symbol: String, label: String, compact: Bool = false) {
        super.init(frame: .zero)
        var style = compact ? UIButton.Configuration.plain() : .glass()
        style.cornerStyle = .capsule
        style.automaticallyUpdateForSelection = false
        style.imagePlacement = .top
        style.imagePadding = 2
        style.contentInsets = .init(top: 4, leading: 2, bottom: 4, trailing: 2)
        style.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: compact ? 22 : 20, weight: .semibold)
        style.titleLineBreakMode = .byTruncatingTail
        style.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var result = attributes
            result.font = .preferredFont(forTextStyle: .caption2)
            result.foregroundColor = UIColor.label
            return result
        }
        configuration = style
        translatesAutoresizingMaskIntoConstraints = false
        isAccessibilityElement = true
        isPointerInteractionEnabled = true
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: compact ? 42 : 48),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 48)
        ])
        let normalHeight = heightAnchor.constraint(equalToConstant: compact ? 52 : 48)
        normalHeight.priority = compact ? .defaultHigh : .required
        normalHeight.isActive = true
        update(symbol: symbol, label: label, animated: false)
    }

    required init?(coder: NSCoder) { fatalError("Use init(symbol:label:)") }

    func update(symbol: String, label: String, color: UIColor = .label,
                count: Int? = nil, animated: Bool = true, selected: Bool = false) {
        isSelected = selected
        accessibilityLabel = label
        accessibilityValue = count?.formatted()
        var style = configuration
        style?.image = UIImage(systemName: symbol)
        style?.title = count?.formatted()
        style?.baseForegroundColor = color
        style?.symbolContentTransition = animated && !UIAccessibility.isReduceMotionEnabled ? UISymbolContentTransition(.replace) : nil
        configuration = style
    }

    func bounce() {
        if !UIAccessibility.isReduceMotionEnabled { imageView?.addSymbolEffect(.bounce) }
    }
}

func glassIsland(style: UIGlassEffect.Style = .regular, interactive: Bool = true) -> UIVisualEffectView {
    let effect = UIGlassEffect(style: style)
    effect.isInteractive = interactive
    let view = UIVisualEffectView(effect: effect)
    view.cornerConfiguration = .capsule()
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
}

func glassGroup(spacing: CGFloat = 12) -> UIVisualEffectView {
    let effect = UIGlassContainerEffect()
    effect.spacing = spacing
    let container = UIVisualEffectView(effect: effect)
    container.translatesAutoresizingMaskIntoConstraints = false
    return container
}

class GlassSectionPicker: UIView {
    private var control = UISegmentedControl()
    private let titles: [String]
    private var controlHeight: NSLayoutConstraint!
    var onIndexSelection: ((Int) -> Void)?

    override var intrinsicContentSize: CGSize { CGSize(width: 184, height: 44) }

    init(titles: [String], symbols: [String] = []) {
        self.titles = titles
        super.init(frame: .zero)
        if symbols.isEmpty {
            control = UISegmentedControl(items: titles)
            control.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                self.onIndexSelection?(self.control.selectedSegmentIndex)
            }, for: .valueChanged)
        } else {
            let actions = titles.indices.map { index in
                UIAction(title: titles[index],
                         image: UIImage(systemName: symbols[index],
                                        withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium))) { [weak self] _ in
                    self?.onIndexSelection?(index)
                }
            }
            control = UISegmentedControl(frame: .zero, actions: actions)
        }
        control.translatesAutoresizingMaskIntoConstraints = false
        addSubview(control)
        controlHeight = control.heightAnchor.constraint(equalToConstant: 44)
        NSLayoutConstraint.activate([
            control.centerYAnchor.constraint(equalTo: centerYAnchor),
            control.leadingAnchor.constraint(equalTo: leadingAnchor),
            control.trailingAnchor.constraint(equalTo: trailingAnchor), controlHeight
        ])
        let font = UIFont.preferredFont(forTextStyle: .footnote)
        control.setTitleTextAttributes([.font: font], for: .normal)
        control.setTitleTextAttributes([.font: font], for: .selected)
        control.accessibilityIdentifier = symbols.isEmpty ? "feed.sections" : "profile.sections"
        control.apportionsSegmentWidthsByContent = false
        control.selectedSegmentIndex = 0
        control.accessibilityValue = titles.first
    }

    required init?(coder: NSCoder) { fatalError("Use init(titles:)") }

    func matchSearchHeight(_ height: CGFloat) {
        guard height.isFinite, height >= 28, height <= 60 else { return }
        if abs(controlHeight.constant - height) > 0.25 { controlHeight.constant = height }
    }

    func selectIndex(_ index: Int) {
        control.selectedSegmentIndex = index
        control.accessibilityValue = titles[index]
    }
}

final class FeedSectionPicker: GlassSectionPicker {
    var onSelection: ((FeedSection) -> Void)?
    init() {
        super.init(titles: ["Для тебе", "Підписки"])
        onIndexSelection = { [weak self] index in self?.onSelection?(index == 1 ? .following : .recommended) }
    }
    required init?(coder: NSCoder) { fatalError("Use init()") }
    func updateSelection(_ section: FeedSection) { selectIndex(section == .following ? 1 : 0) }
}

final class GradientView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }
    var gradient: CAGradientLayer { layer as! CAGradientLayer }
}

final class EmptyStateView: UIView {
    init(title: String, message: String, symbol: String, action: UIButton? = nil) {
        super.init(frame: .zero)
        let image = UIImageView(image: UIImage(systemName: symbol))
        image.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 42, weight: .regular)
        image.tintColor = .secondaryLabel
        image.isAccessibilityElement = false
        let heading = makeLabel(.headline, text: title)
        heading.accessibilityTraits.insert(.header)
        let description = makeLabel(.subheadline, text: message, color: .secondaryLabel)
        heading.textAlignment = .center
        description.textAlignment = .center
        let stack = UIStackView(arrangedSubviews: [image, heading, description])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10
        if let action {
            stack.setCustomSpacing(20, after: description)
            stack.addArrangedSubview(action)
        }
        let safe = safeAreaLayoutGuide
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: safe.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: safe.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: safe.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: safe.trailingAnchor, constant: -24),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 420)
        ])
    }

    required init?(coder: NSCoder) { fatalError("Use init(title:message:symbol:action:)") }
}

class FormController: UIViewController {
    let content = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let scroll = UIScrollView()
        scroll.keyboardDismissMode = .interactive
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        content.axis = .vertical
        content.spacing = 16
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 22),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -22),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -44)
        ])
    }
}
