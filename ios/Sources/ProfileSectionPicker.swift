import UIKit

enum ProfileSection: Int, CaseIterable {
    case posts, saved, liked, comments, overview

    var title: String {
        switch self {
        case .overview: return "Профіль"
        case .posts: return "Публікації"
        case .saved: return "Збережені"
        case .liked: return "Уподобання"
        case .comments: return "Коментарі"
        }
    }
    var symbol: String {
        switch self {
        case .overview: return "person.text.rectangle"
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
    private let sections: [ProfileSection]
    init(atmosphere: Bool = false) {
        let values: [ProfileSection] = atmosphere ? [.overview, .posts, .saved, .liked, .comments] : [.posts, .saved, .liked, .comments]
        sections = values
        super.init(titles: values.map(\.title), symbols: values.map(\.symbol), toolbarHosted: atmosphere)
        matchSearchHeight(44)
        onIndexSelection = { [weak self] index in
            guard let self, self.sections.indices.contains(index) else { return }
            let section = self.sections[index]
            self.onSelection?(section)
        }
    }
    required init?(coder: NSCoder) { fatalError("Use init()") }
    func select(_ section: ProfileSection) { selectIndex(sections.firstIndex(of: section) ?? 0) }
}
