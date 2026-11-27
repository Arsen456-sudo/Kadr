import UIKit

/// Three intentionally different compositions; Atmosphere retains its own renderer.
enum LegacyProfileDesign {
    static func header(_ profile: Profile, width: CGFloat, top: CGFloat, appearance: CreatorAppearance, own: Bool,
                       following: Bool?, counts: (Int, Int, Int), onAvatar: @escaping () -> Void,
                       onPeople: @escaping (Bool) -> Void, onStudio: @escaping () -> Void,
                       onMessage: @escaping () -> Void, onFollow: @escaping () -> Void,
                       onShare: @escaping () -> Void) -> UIStackView {
        let cinema = appearance.theme == "cinema", vivid = appearance.theme == "vivid"
        let color = UIColor.kadrPeach
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = cinema ? 24 : 18
        let spacer = UIView()
        spacer.heightAnchor.constraint(equalToConstant: max(0, ProfileHero.coverSize(for: profile, width: width, top: top, theme: appearance.theme) - (cinema ? 70 : 48))).isActive = true
        stack.addArrangedSubview(spacer)
        let avatar = VideoAvatarView(frame: .zero); avatar.show(profile)
        let side: CGFloat = cinema ? 124 : vivid ? 96 : 88
        avatar.layer.cornerRadius = cinema ? 62 : vivid ? 30 : 44
        let photo = UIButton(type: .custom); avatar.pin(to: photo)
        NSLayoutConstraint.activate([photo.widthAnchor.constraint(equalToConstant: side), photo.heightAnchor.constraint(equalToConstant: side)])
        photo.accessibilityLabel = "Фото @" + profile.handle
        photo.addAction(UIAction { _ in onAvatar() }, for: .primaryActionTriggered)
        let labels = UIStackView(); labels.axis = .vertical; labels.spacing = 6
        let name = makeLabel(cinema ? .largeTitle : .title1, text: profile.name)
        let serifBase = UIFont.systemFont(ofSize: 32, weight: .bold)
        let serif = UIFont(descriptor: serifBase.fontDescriptor.withDesign(.serif) ?? serifBase.fontDescriptor, size: 32)
        name.font = cinema ? UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: serif) : name.font.withTraits(.traitBold)
        let handle = makeLabel(.subheadline, text: "@" + profile.handle, color: vivid ? color : .secondaryLabel)
        if cinema {
            let eyebrow = makeLabel(.caption2, text: "ПРОСТІР АВТОРА", color: color); eyebrow.textAlignment = .center; labels.addArrangedSubview(eyebrow)
        }
        labels.addArrangedSubview(name); labels.addArrangedSubview(handle)
        if !profile.bio.isEmpty { labels.addArrangedSubview(makeLabel(.body, text: profile.bio, color: .secondaryLabel)) }
        let identity = UIStackView(arrangedSubviews: vivid ? [labels, photo] : [photo, labels])
        identity.axis = cinema ? .vertical : .horizontal; identity.alignment = .center; identity.spacing = cinema ? 16 : 18
        if cinema { labels.arrangedSubviews.compactMap { $0 as? UILabel }.forEach { $0.textAlignment = .center } }
        let identityHost = UIView(); identity.pin(to: identityHost, insets: .init(top: 0, leading: 24, bottom: 0, trailing: 24)); stack.addArrangedSubview(identityHost)
        let metrics = UIStackView(); metrics.distribution = .fillEqually; metrics.spacing = 8
        for (index, title) in ["Публікації", "Підписники", "Підписки"].enumerated() {
            var configuration = vivid ? UIButton.Configuration.prominentGlass() : .plain()
            configuration.title = String([counts.0, counts.1, counts.2][index]); configuration.subtitle = title
            configuration.titleAlignment = .center; configuration.baseForegroundColor = .label
            if vivid { configuration.baseBackgroundColor = color; configuration.cornerStyle = .large }
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { original in var value = original; value.font = .preferredFont(forTextStyle: .title2).withTraits(.traitBold); return value }
            configuration.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { original in var value = original; value.font = .preferredFont(forTextStyle: .caption1); return value }
            let button = UIButton(configuration: configuration); button.heightAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true
            button.addAction(UIAction { [weak button] _ in
                if index > 0 { onPeople(index == 1) }
                else {
                    var next: UIResponder? = button
                    while let responder = next { if let controller = responder as? ProfileController { controller.scrollToPublications(); break }; next = responder.next }
                }
            }, for: .primaryActionTriggered)
            metrics.addArrangedSubview(button)
        }
        let metricHost = UIView(); metrics.pin(to: metricHost, insets: .init(top: 0, leading: 20, bottom: 0, trailing: 20)); stack.addArrangedSubview(metricHost)
        if !appearance.introduction.isEmpty {
            let introduction = makeLabel(.body, text: appearance.introduction)
            if cinema { introduction.textAlignment = .center }
            let host = UIView(); introduction.pin(to: host, insets: .init(top: 8, leading: 24, bottom: 8, trailing: 24)); stack.addArrangedSubview(host)
        }
        let actions = UIStackView(); actions.distribution = .fillEqually; actions.spacing = 10
        if let following {
            actions.addArrangedSubview(textButton(following ? "Стежу" : "Стежити", symbol: "person.badge.plus", prominent: !following, action: onFollow))
            if following { actions.addArrangedSubview(textButton("Написати", symbol: "bubble.left", action: onMessage)) }
        }
        if own { actions.addArrangedSubview(textButton("Студія", symbol: "slider.horizontal.3", action: onStudio)) }
        actions.addArrangedSubview(textButton("Поділитися", symbol: "square.and.arrow.up", action: onShare))
        let actionHost = UIView(); actions.pin(to: actionHost, insets: .init(top: 0, leading: 20, bottom: 0, trailing: 20)); stack.addArrangedSubview(actionHost)
        for link in appearance.links {
            let host = UIView(); textButton(link, symbol: "link") { if let url = URL(string: link), url.scheme == "https" { UIApplication.shared.open(url) } }.pin(to: host, insets: .init(top: 0, leading: 20, bottom: 0, trailing: 20)); stack.addArrangedSubview(host)
        }
        let footer = UIView(); footer.heightAnchor.constraint(equalToConstant: 54).isActive = true; stack.addArrangedSubview(footer)
        return stack
    }
}
