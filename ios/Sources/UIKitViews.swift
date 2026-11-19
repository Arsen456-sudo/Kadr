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
    private let glyph = UIImageView()
    private let counter = makeLabel(.caption2)
    private var symbolName = ""

    init(symbol: String, label: String, compact: Bool = false) {
        super.init(frame: .zero)
        var style = compact ? UIButton.Configuration.plain() : .glass()
        style.cornerStyle = .capsule
        configuration = style
        translatesAutoresizingMaskIntoConstraints = false
        isAccessibilityElement = true
        glyph.contentMode = .scaleAspectFit
        glyph.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: compact ? 22 : 20, weight: .semibold)
        glyph.isAccessibilityElement = false
        counter.textAlignment = .center
        counter.numberOfLines = 1
        let content = UIStackView(arrangedSubviews: [glyph, counter])
        content.axis = .vertical
        content.spacing = 2
        content.alignment = .center
        content.isUserInteractionEnabled = false
        content.accessibilityElementsHidden = true
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: compact ? 42 : 48),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            content.centerXAnchor.constraint(equalTo: centerXAnchor),
            content.centerYAnchor.constraint(equalTo: centerYAnchor),
            content.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 4),
            content.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -4),
            content.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -4)
        ])
        let normalHeight = heightAnchor.constraint(equalToConstant: compact ? 52 : 48)
        normalHeight.priority = compact ? .defaultHigh : .required
        normalHeight.isActive = true
        update(symbol: symbol, label: label, animated: false)
    }

    required init?(coder: NSCoder) { fatalError("Use init(symbol:label:)") }

    func update(symbol: String, label: String, color: UIColor = .label,
                count: Int? = nil, animated: Bool = true) {
        accessibilityLabel = label
        accessibilityValue = count?.formatted()
        counter.text = count?.formatted()
        counter.isHidden = count == nil
        glyph.tintColor = color
        if symbol != symbolName, let image = UIImage(systemName: symbol) {
            symbolName = symbol
            if animated && window != nil && !UIAccessibility.isReduceMotionEnabled {
                glyph.setSymbolImage(image, contentTransition: .replace)
            } else {
                glyph.image = image
            }
        }
    }

    func bounce() {
        if !UIAccessibility.isReduceMotionEnabled { glyph.addSymbolEffect(.bounce) }
    }
}

func glassIsland(style: UIGlassEffect.Style = .regular) -> UIVisualEffectView {
    let view = UIVisualEffectView(effect: UIGlassEffect(style: style))
    view.cornerConfiguration = .capsule()
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
}

final class HeaderActionButton: UIButton {
    static let side: CGFloat = 46
    private lazy var iconWidth = widthAnchor.constraint(equalTo: heightAnchor)

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(greaterThanOrEqualToConstant: Self.side).isActive = true
        heightAnchor.constraint(equalToConstant: Self.side).isActive = true
        setContentHuggingPriority(.defaultHigh, for: .horizontal)
        setLogout(false, animated: false)
    }

    required init?(coder: NSCoder) { fatalError("Use init()") }

    func setLogout(_ logout: Bool, animated: Bool) {
        let update = {
            var style = UIButton.Configuration.glass()
            style.cornerStyle = .capsule
            style.buttonSize = .medium
            style.baseForegroundColor = .label
            style.image = UIImage(systemName: logout ? "rectangle.portrait.and.arrow.right" : "magnifyingglass")
            style.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
                pointSize: logout ? 20 : 18, weight: .semibold)
            style.title = logout ? "Вийти" : nil
            style.imagePadding = 6
            self.configuration = style
            self.iconWidth.isActive = !logout
            self.accessibilityLabel = logout ? "Вийти" : "Пошук"
            self.superview?.layoutIfNeeded()
        }
        if animated && window != nil && !UIAccessibility.isReduceMotionEnabled {
            superview?.layoutIfNeeded()
            UIView.animate(withDuration: 0.21, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction],
                           animations: update)
        } else {
            update()
        }
    }
}

final class FeedSectionPicker: UIView {
    private let island = glassIsland(style: .clear)
    private let recommended = UIButton()
    private let following = UIButton()
    private var selected: FeedSection?
    var onSelection: ((FeedSection) -> Void)?

    init() {
        super.init(frame: .zero)
        island.pin(to: self)
        let choices = UIStackView(arrangedSubviews: [recommended, following])
        choices.spacing = UIStackView.spacingUseSystem
        choices.distribution = .fillEqually
        choices.translatesAutoresizingMaskIntoConstraints = false
        island.contentView.addSubview(choices)

        // The system spacing keeps the inner glass capsules inset from the shared island.
        let inset = island.contentView
        NSLayoutConstraint.activate([
            choices.leadingAnchor.constraint(equalToSystemSpacingAfter: inset.leadingAnchor, multiplier: 0.5),
            inset.trailingAnchor.constraint(equalToSystemSpacingAfter: choices.trailingAnchor, multiplier: 0.5),
            choices.topAnchor.constraint(equalToSystemSpacingBelow: inset.topAnchor, multiplier: 0.5),
            inset.bottomAnchor.constraint(equalToSystemSpacingBelow: choices.bottomAnchor, multiplier: 0.5)
        ])
        recommended.accessibilityIdentifier = "feed.recommended"
        following.accessibilityIdentifier = "feed.following"
        recommended.addAction(UIAction { [weak self] _ in self?.onSelection?(.recommended) }, for: .primaryActionTriggered)
        following.addAction(UIAction { [weak self] _ in self?.onSelection?(.following) }, for: .primaryActionTriggered)
        updateSelection(.recommended)
    }

    required init?(coder: NSCoder) { fatalError("Use init()") }

    func updateSelection(_ section: FeedSection) {
        guard section != selected else { return }
        selected = section
        configure(recommended, title: "Для тебе", selected: section == .recommended)
        configure(following, title: "Підписки", selected: section == .following)
    }

    private func configure(_ button: UIButton, title: String, selected: Bool) {
        var style = selected ? UIButton.Configuration.glass() : .plain()
        style.cornerStyle = .capsule
        style.buttonSize = .small
        style.baseForegroundColor = .label
        style.title = title
        style.titleLineBreakMode = .byTruncatingTail
        style.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var result = attributes
            result.font = .preferredFont(forTextStyle: .footnote)
            return result
        }
        button.configuration = style
        button.titleLabel?.numberOfLines = 1
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.8
        if selected { button.accessibilityTraits.insert(.selected) }
        else { button.accessibilityTraits.remove(.selected) }
    }
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
