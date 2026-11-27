import UIKit

enum AtmosphereProfile {
    static func actionOuterInset(width: CGFloat) -> CGFloat {
        // Three equal columns, 24pt row margins, 10pt gaps and 56pt buttons.
        let column = max(56, (width - 48 - 20) / 3)
        return 24 + (column - 56) / 2
    }
    static func photoHeight(_ profile: Profile, width: CGFloat, top: CGFloat) -> CGFloat {
        return max(top + 280, min(548, width * 1.16))
    }

    static func header(_ profile: Profile, width: CGFloat, top: CGFloat, appearance: CreatorAppearance, own: Bool,
                       following: Bool?, counts: (Int, Int, Int), onPhoto: @escaping () -> Void,
                       onPeople: @escaping (Bool) -> Void, onStudio: @escaping () -> Void,
                       onMessage: @escaping () -> Void, onFollow: @escaping () -> Void,
                       onShare: @escaping () -> Void) -> UIStackView {
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 12
        let space = UIView()
        space.heightAnchor.constraint(equalToConstant: max(top + 52, photoHeight(profile, width: width, top: top) - 100)).isActive = true
        stack.addArrangedSubview(space)

        let identity = UIStackView(); identity.axis = .vertical; identity.spacing = 6
        let name = makeLabel(.largeTitle, text: profile.name)
        name.font = name.font.withTraits(.traitBold); name.textAlignment = .center
        let handle = makeLabel(.title2, text: "@" + profile.handle)
        handle.font = handle.font.withTraits(.traitBold); handle.textAlignment = .center
        identity.addArrangedSubview(name); identity.addArrangedSubview(handle)
        if !profile.bio.isEmpty {
            let bio = makeLabel(.body, text: profile.bio, color: .secondaryLabel)
            bio.textAlignment = .center; identity.addArrangedSubview(bio)
        }
        let identityInset = UIView()
        identity.pin(to: identityInset, insets: .init(top: 0, leading: 24, bottom: 0, trailing: 24))
        stack.addArrangedSubview(identityInset)

        let metrics = UIStackView(); metrics.distribution = .fillEqually; metrics.spacing = 12
        for (index, title) in ["Публікації", "Підписники", "Підписки"].enumerated() {
            var style = UIButton.Configuration.plain()
            style.titleAlignment = .center
            style.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var result = attributes; result.font = .preferredFont(forTextStyle: .title3).withTraits(.traitBold); return result
            }
            style.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var result = attributes; result.font = .preferredFont(forTextStyle: .caption1); result.foregroundColor = UIColor.secondaryLabel; return result
            }
            style.title = String([counts.0, counts.1, counts.2][index]); style.subtitle = title
            style.baseForegroundColor = .label
            let button = UIButton(configuration: style)
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
            button.addAction(UIAction { [weak button] _ in
                if index > 0 { onPeople(index == 1) }
                else { (presenter(from: button) as? ProfileController)?.scrollToPublications() }
            }, for: .primaryActionTriggered)
            metrics.addArrangedSubview(button)
        }
        let metricInset = UIView()
        metrics.pin(to: metricInset, insets: .init(top: 0, leading: 20, bottom: 0, trailing: 20))
        stack.addArrangedSubview(metricInset)

        let actions = UIStackView(); actions.distribution = .fillEqually; actions.alignment = .top; actions.spacing = 10
        if let following {
            actions.addArrangedSubview(action(following ? "Стежу" : "Стежити", symbol: following ? "person.badge.checkmark" : "person.badge.plus", onTap: onFollow))
            if following { actions.addArrangedSubview(action("Написати", symbol: "bubble.left.fill", onTap: onMessage)) }
        }
        if own { actions.addArrangedSubview(action("Студія", symbol: "slider.horizontal.3", onTap: onStudio)) }
        actions.addArrangedSubview(action("Поділитися", symbol: "square.and.arrow.up", onTap: onShare))
        let more = action("Ще", symbol: "ellipsis", onTap: nil)
        if let button = more.arrangedSubviews.first as? UIButton {
            let items: [UIAction]
            if own {
                items = [UIAction(title: "Вийти з акаунта", image: AppSymbol.image("rectangle.portrait.and.arrow.right"), attributes: .destructive) { [weak button] _ in
                    (presenter(from: button) as? ProfileController)?.signOutFromProfile()
                }]
            } else {
                items = [UIAction(title: "Про автора", image: AppSymbol.image("person.text.rectangle")) { [weak button] _ in
                guard let parent = presenter(from: button) else { return }
                parent.showMessage(profile.bio.isEmpty ? "@" + profile.handle : profile.bio)
                }]
            }
            button.menu = UIMenu(children: items); button.showsMenuAsPrimaryAction = true
        }
        actions.addArrangedSubview(more)
        let actionInset = UIView()
        actions.pin(to: actionInset, insets: .init(top: 6, leading: 24, bottom: 4, trailing: 24))
        stack.addArrangedSubview(actionInset)

        if !appearance.introduction.isEmpty {
            let text = makeLabel(.body, text: appearance.introduction)
            let card = UIView()
            text.pin(to: card, insets: .init(top: 18, leading: 20, bottom: 18, trailing: 20))
            let inset = UIView(); card.pin(to: inset, insets: .init(top: 0, leading: 16, bottom: 0, trailing: 16))
            stack.addArrangedSubview(inset)
        }
        for link in appearance.links {
            stack.addArrangedSubview(textButton(link, symbol: "link") {
                if let url = URL(string: link), url.scheme == "https" { UIApplication.shared.open(url) }
            })
        }
        let footer = UIView(); footer.heightAnchor.constraint(equalToConstant: 12).isActive = true; stack.addArrangedSubview(footer)
        return stack
    }

    private static func action(_ title: String, symbol: String, onTap: (() -> Void)?) -> UIStackView {
        var style = UIButton.Configuration.glass()
        style.cornerStyle = .capsule; style.baseForegroundColor = .label
        style.image = AppSymbol.image(symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 21, weight: .semibold))
        let button = UIButton(configuration: style)
        button.accessibilityLabel = title; button.isPointerInteractionEnabled = true
        button.widthAnchor.constraint(equalToConstant: 56).isActive = true
        button.heightAnchor.constraint(equalTo: button.widthAnchor).isActive = true
        if let onTap { button.addAction(UIAction { _ in onTap() }, for: .primaryActionTriggered) }
        let label = makeLabel(.caption1, text: title); label.textAlignment = .center
        let stack = UIStackView(arrangedSubviews: [button, label]); stack.axis = .vertical; stack.alignment = .center; stack.spacing = 8
        return stack
    }
    private static func presenter(from view: UIView?) -> UIViewController? {
        var responder: UIResponder? = view
        while let next = responder?.next { if let controller = next as? UIViewController { return controller }; responder = next }
        return nil
    }
}
