import UIKit

struct ProfileDashboardRow {
    enum Destination { case statistics, community, library, settings, appearance, about }
    let title: String
    let detail: String
    let symbol: String
    let destination: Destination
    var value: String? = nil

    @MainActor static func rows(profile: Profile, store: LocalStore, own: Bool) -> [ProfileDashboardRow] {
        let posts = store.allClips.filter { $0.authorID == profile.id && (own || !$0.settings.onlyMe) }
        var rows = [
            ProfileDashboardRow(title: "Публікації", detail: "\(posts.reduce(0) { $0 + store.likes($1) }) уподобань", symbol: "chart.bar.xaxis", destination: .statistics, value: "\(posts.count)"),
            ProfileDashboardRow(title: "Підписники", detail: "\(store.people(followedBy: profile.id).count) підписок", symbol: "person.2", destination: .community, value: "\(store.people(followersOf: profile.id).count)")
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
    private let material = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let title = makeLabel(.headline)
    private let detail = makeLabel(.subheadline, color: .secondaryLabel)
    private let icon = UIImageView()
    private let value = makeLabel(.largeTitle)
    private let arrow = UIImageView(image: AppSymbol.image("chevron.right"))
    private let separator = UIView()
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear; contentView.backgroundColor = .clear
        material.layer.cornerCurve = .continuous; material.clipsToBounds = true
        material.contentView.backgroundColor = UIColor.white.withAlphaComponent(0.035)
        material.isUserInteractionEnabled = false
        material.pin(to: contentView)
        icon.contentMode = .scaleAspectFit; icon.tintColor = .label
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 19, weight: .medium)
        let iconBackground = UIView(); iconBackground.backgroundColor = UIColor.white.withAlphaComponent(0.055)
        iconBackground.layer.cornerRadius = 12
        iconBackground.widthAnchor.constraint(equalToConstant: 40).isActive = true
        iconBackground.heightAnchor.constraint(equalToConstant: 40).isActive = true
        icon.pin(to: iconBackground, insets: .init(top: 10, leading: 10, bottom: 10, trailing: 10))
        title.font = .preferredFont(forTextStyle: .subheadline).withTraits(.traitBold)
        value.font = .preferredFont(forTextStyle: .title2).withTraits(.traitBold)
        value.setContentHuggingPriority(.required, for: .horizontal)
        value.setContentCompressionResistancePriority(.required, for: .horizontal)
        arrow.tintColor = .tertiaryLabel
        arrow.setContentHuggingPriority(.required, for: .horizontal)
        let labels = UIStackView(arrangedSubviews: [title, detail]); labels.axis = .vertical; labels.spacing = 5
        detail.font = .preferredFont(forTextStyle: .footnote)
        let row = UIStackView(arrangedSubviews: [iconBackground, labels, value, arrow]); row.alignment = .center; row.spacing = 14
        row.isUserInteractionEnabled = false
        row.pin(to: contentView, insets: .init(top: 18, leading: 18, bottom: 18, trailing: 18))
        separator.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        separator.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview(separator)
        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 72),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5)
        ])
        isAccessibilityElement = true; accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
    func show(_ row: ProfileDashboardRow, first: Bool, last: Bool) {
        title.text = row.title; detail.text = row.detail; icon.image = AppSymbol.image(row.symbol)
        value.text = row.value; value.isHidden = row.value == nil; arrow.isHidden = false
        var corners: CACornerMask = []
        if first { corners.formUnion([.layerMinXMinYCorner, .layerMaxXMinYCorner]) }
        if last { corners.formUnion([.layerMinXMaxYCorner, .layerMaxXMaxYCorner]) }
        material.layer.maskedCorners = corners; material.layer.cornerRadius = 22
        separator.isHidden = last
        accessibilityLabel = row.title + (row.value.map { ", " + $0 } ?? "") + ", " + row.detail
    }
    override var isHighlighted: Bool {
        didSet { material.contentView.backgroundColor = UIColor.white.withAlphaComponent(isHighlighted ? 0.08 : 0.035) }
    }
}
