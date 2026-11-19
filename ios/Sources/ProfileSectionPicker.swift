import UIKit

enum ProfileSection: Int, CaseIterable {
    case posts, saved, liked, comments

    var title: String {
        switch self {
        case .posts: return "Публікації"
        case .saved: return "Збережені"
        case .liked: return "Уподобання"
        case .comments: return "Коментарі"
        }
    }
    var symbol: String {
        switch self {
        case .posts: return "square.grid.3x3"
        case .saved: return "bookmark"
        case .liked: return "heart"
        case .comments: return "bubble.left"
        }
    }
}

// Native glass buttons provide a material-backed selected capsule at rest.
// UISegmentedControl only supplies its Liquid Glass thumb during interaction.
final class ProfileSectionPicker: UIView {
    var onSelection: ((ProfileSection) -> Void)?
    private let container = glassGroup()
    private let surface = glassIsland(style: .clear, interactive: false)
    private let stack = UIStackView()
    private var buttons: [UIButton] = []

    override var intrinsicContentSize: CGSize { CGSize(width: 184, height: 44) }

    init() {
        super.init(frame: .zero)
        accessibilityIdentifier = "profile.sections"
        container.pin(to: self)
        surface.pin(to: container.contentView)
        surface.isUserInteractionEnabled = false
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 0
        stack.pin(to: container.contentView, insets: .init(top: 4, leading: 4, bottom: 4, trailing: 4))
        for section in ProfileSection.allCases {
            let button = UIButton(type: .system)
            button.isPointerInteractionEnabled = true
            button.accessibilityLabel = section.title
            button.accessibilityIdentifier = "profile.section.\(section.rawValue)"
            button.configurationUpdateHandler = { button in
                var style = button.isSelected ? UIButton.Configuration.glass() : .plain()
                style.cornerStyle = .capsule
                style.automaticallyUpdateForSelection = false
                style.image = UIImage(systemName: section.symbol)
                style.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
                style.baseForegroundColor = .label
                style.contentInsets = .zero
                button.configuration = style
            }
            button.addAction(UIAction { [weak self] _ in
                self?.select(section)
                self?.onSelection?(section)
            }, for: .primaryActionTriggered)
            stack.addArrangedSubview(button)
            buttons.append(button)
        }
        select(.posts)
    }

    required init?(coder: NSCoder) { fatalError("Use init()") }

    func select(_ section: ProfileSection) {
        for (index, button) in buttons.enumerated() {
            button.isSelected = index == section.rawValue
            button.setNeedsUpdateConfiguration()
        }
        accessibilityValue = section.title
    }
}
