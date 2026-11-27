import UIKit

/// One shared layout for every conversation, including drafts and pinned chats.
final class InboxConversationCell: UITableViewCell {
    private let avatar = UIImageView()
    private let name = makeLabel(.headline)
    private let time = makeLabel(.caption2, color: .secondaryLabel)
    private let handle = makeLabel(.caption1, color: .secondaryLabel)
    private let preview = makeLabel(.subheadline, color: .secondaryLabel)
    private let pin = UIImageView(image: AppSymbol.image("pin"))
    private let tile = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear; backgroundConfiguration = .clear()
        tile.backgroundColor = .secondarySystemGroupedBackground
        tile.layer.cornerRadius = 24; tile.layer.cornerCurve = .continuous
        tile.pin(to: contentView, insets: .init(top: 4, leading: 0, bottom: 4, trailing: 0))
        avatar.contentMode = .scaleAspectFill; avatar.clipsToBounds = true; avatar.layer.cornerRadius = 26
        avatar.tintColor = .secondaryLabel
        NSLayoutConstraint.activate([avatar.widthAnchor.constraint(equalToConstant: 52), avatar.heightAnchor.constraint(equalToConstant: 52)])
        name.numberOfLines = 1; preview.numberOfLines = 2; handle.numberOfLines = 1
        time.numberOfLines = 1; time.setContentCompressionResistancePriority(.required, for: .horizontal)
        time.setContentHuggingPriority(.required, for: .horizontal)
        pin.tintColor = .secondaryLabel; pin.contentMode = .scaleAspectFit
        NSLayoutConstraint.activate([pin.widthAnchor.constraint(equalToConstant: 12), pin.heightAnchor.constraint(equalToConstant: 12)])
        let title = UIStackView(arrangedSubviews: [name, pin, time]); title.alignment = .center; title.spacing = 7
        let labels = UIStackView(arrangedSubviews: [title, handle, preview]); labels.axis = .vertical; labels.spacing = 4
        let row = UIStackView(arrangedSubviews: [avatar, labels]); row.spacing = 14; row.alignment = .center
        row.pin(to: tile, insets: .init(top: 16, leading: 16, bottom: 16, trailing: 16))
        tile.isUserInteractionEnabled = false
        isAccessibilityElement = true; accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError("Use init(style:reuseIdentifier:)") }
    func show(profile: Profile, preview: String, date: Date, pinned: Bool, draft: Bool) {
        name.text = profile.name; handle.text = "@" + profile.handle
        self.preview.text = preview; self.preview.textColor = draft ? .kadrPeach : .secondaryLabel
        time.text = Calendar.current.isDateInToday(date) ? date.formatted(date: .omitted, time: .shortened) : date.formatted(date: .abbreviated, time: .omitted)
        avatar.image = profile.avatar.flatMap { UIImage(data: $0) } ?? AppSymbol.image("person.crop.circle")
        pin.isHidden = !pinned
        accessibilityLabel = profile.name + ", @" + profile.handle + ", " + preview + (pinned ? ", закріплено" : "")
    }
    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        tile.backgroundColor = highlighted ? .tertiarySystemFill : .secondarySystemGroupedBackground
    }
}
