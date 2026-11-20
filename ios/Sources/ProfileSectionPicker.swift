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

// Share the exact native selection implementation used by FeedSectionPicker.
final class ProfileSectionPicker: GlassSectionPicker {
    var onSelection: ((ProfileSection) -> Void)?
    init() {
        super.init(titles: ProfileSection.allCases.map(\.title), symbols: ProfileSection.allCases.map(\.symbol))
        let glass = glassIsland(style: .clear, interactive: false)
        glass.isUserInteractionEnabled = false
        glass.pin(to: self)
        sendSubviewToBack(glass)
        matchSearchHeight(44)
        onIndexSelection = { [weak self] index in
            guard let section = ProfileSection(rawValue: index) else { return }
            self?.onSelection?(section)
        }
    }
    required init?(coder: NSCoder) { fatalError("Use init()") }
    func select(_ section: ProfileSection) { selectIndex(section.rawValue) }
}
