import UIKit

struct ProfileDashboardRow {
    enum Destination { case statistics, community, library, settings, appearance, about }
    let title: String
    let detail: String
    let symbol: String
    let destination: Destination

    @MainActor static func rows(profile: Profile, store: LocalStore, own: Bool) -> [ProfileDashboardRow] {
        let posts = store.allClips.filter { $0.authorID == profile.id && (own || !$0.settings.onlyMe) }
        var rows = [
            ProfileDashboardRow(title: "Статистика публікацій", detail: "\(posts.count) публікацій · \(posts.reduce(0) { $0 + store.likes($1) }) уподобань", symbol: "chart.bar.xaxis", destination: .statistics),
            ProfileDashboardRow(title: "Спільнота", detail: "\(store.people(followersOf: profile.id).count) підписників · \(store.people(followedBy: profile.id).count) підписок", symbol: "person.2", destination: .community)
        ]
        if own {
            rows += [
                ProfileDashboardRow(title: "Твоя бібліотека", detail: "\(store.feed(.saved).count) збережених · \(store.drafts.count) чернеток", symbol: "square.stack", destination: .library),
                ProfileDashboardRow(title: "Налаштування", detail: "Приватність, відтворення та повідомлення", symbol: "gearshape", destination: .settings),
                ProfileDashboardRow(title: "Оформлення", detail: "Стиль профілю та твої акценти", symbol: "paintpalette", destination: .appearance)
            ]
        } else {
            rows.append(ProfileDashboardRow(title: "Про автора", detail: profile.bio.isEmpty ? "@" + profile.handle : profile.bio, symbol: "person.text.rectangle", destination: .about))
        }
        return rows
    }
}

final class ProfileDashboardCell: UICollectionViewCell {
    private let material = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
    private let title = makeLabel(.headline)
    private let detail = makeLabel(.subheadline, color: .secondaryLabel)
    private let icon = UIImageView()
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear; contentView.backgroundColor = .clear
        material.layer.cornerRadius = 24; material.layer.cornerCurve = .continuous; material.clipsToBounds = true
        material.contentView.backgroundColor = UIColor.white.withAlphaComponent(0.045)
        material.isUserInteractionEnabled = false
        material.pin(to: contentView)
        icon.contentMode = .scaleAspectFit; icon.tintColor = .label
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 23, weight: .medium)
        icon.widthAnchor.constraint(equalToConstant: 30).isActive = true
        let labels = UIStackView(arrangedSubviews: [title, detail]); labels.axis = .vertical; labels.spacing = 6
        let arrow = UIImageView(image: AppSymbol.image("chevron.right")); arrow.tintColor = .tertiaryLabel
        arrow.setContentHuggingPriority(.required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [icon, labels, arrow]); row.alignment = .center; row.spacing = 14
        row.isUserInteractionEnabled = false
        row.pin(to: contentView, insets: .init(top: 22, leading: 20, bottom: 22, trailing: 20))
        isAccessibilityElement = true; accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
    func show(_ row: ProfileDashboardRow) {
        title.text = row.title; detail.text = row.detail; icon.image = AppSymbol.image(row.symbol)
        accessibilityLabel = row.title + ", " + row.detail
    }
    override var isHighlighted: Bool {
        didSet { material.contentView.backgroundColor = UIColor.white.withAlphaComponent(isHighlighted ? 0.10 : 0.045) }
    }
}
