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

final class ProfileSectionPicker: UIView {
    private let scroll = UIScrollView()
    private let control = UISegmentedControl(items: ProfileSection.allCases.map(\.title))
    private var lastWidth: CGFloat = 0
    var onSelection: ((ProfileSection) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        scroll.pin(to: self)
        scroll.showsHorizontalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.layer.cornerRadius = 20
        scroll.clipsToBounds = true
        scroll.addSubview(control)
        control.apportionsSegmentWidthsByContent = true
        control.selectedSegmentIndex = 0
        control.addAction(UIAction { [weak self] _ in
            guard let self, let section = ProfileSection(rawValue: self.control.selectedSegmentIndex) else { return }
            self.onSelection?(section)
        }, for: .valueChanged)
        control.accessibilityLabel = "Розділи профілю"
        control.accessibilityCustomActions = ProfileSection.allCases.map { section in
            UIAccessibilityCustomAction(name: section.title) { [weak self] _ in
                self?.select(section)
                self?.onSelection?(section)
                return true
            }
        }
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self, UITraitUserInterfaceStyle.self]) {
            (picker: ProfileSectionPicker, _: UITraitCollection) in
            picker.lastWidth = 0
            picker.setNeedsLayout()
        }
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if lastWidth != bounds.width {
            lastWidth = bounds.width
            let font = UIFont.preferredFont(forTextStyle: .caption2)
            let color = UIColor.label.resolvedColor(with: traitCollection)
            var total: CGFloat = 8
            for section in ProfileSection.allCases {
                let textSize = (section.title as NSString).size(withAttributes: [.font: font])
                let iconSide = font.pointSize
                let size = CGSize(width: ceil(iconSide + 5 + textSize.width), height: ceil(max(iconSide, textSize.height)))
                let image = UIGraphicsImageRenderer(size: size).image { _ in
                    let icon = UIImage(systemName: section.symbol,
                                       withConfiguration: UIImage.SymbolConfiguration(pointSize: iconSide, weight: .medium))
                    icon?.withTintColor(color, renderingMode: .alwaysOriginal)
                        .draw(in: CGRect(x: 0, y: (size.height - iconSide) / 2, width: iconSide, height: iconSide))
                    (section.title as NSString).draw(
                        at: CGPoint(x: iconSide + 5, y: (size.height - textSize.height) / 2),
                        withAttributes: [.font: font, .foregroundColor: color])
                }.withRenderingMode(.alwaysOriginal)
                control.setImage(image, forSegmentAt: section.rawValue)
                control.setWidth(size.width + 12, forSegmentAt: section.rawValue)
                total += size.width + 12
            }
            control.frame = CGRect(x: 0, y: 0, width: max(bounds.width, total), height: bounds.height)
            scroll.contentSize = control.bounds.size
        }
    }

    func select(_ section: ProfileSection) {
        control.selectedSegmentIndex = section.rawValue
        control.accessibilityValue = section.title
    }
}
