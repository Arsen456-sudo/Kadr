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
            widthAnchor.constraint(equalToConstant: compact ? 52 : 48),
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

final class GradientView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }
    var gradient: CAGradientLayer { layer as! CAGradientLayer }
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
