import UIKit

/// Preview cards embed the same profile controller as the real screen.
final class ProfileStyleController: FormController {
    private let store: LocalStore
    private var cards: [ProfileStylePreview] = []
    init(store: LocalStore) { self.store = store; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("Use init(store:)") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Стиль профілю"
        content.spacing = 24
        content.addArrangedSubview(makeLabel(.body, text: "Справжній вигляд твого профілю. Обери стиль — він застосовується одразу.", color: .secondaryLabel))
        guard let profile = store.active else { content.addArrangedSubview(makeLabel(.body, text: "Увійди, щоб налаштувати оформлення.")); return }
        for theme in ["minimal", "cinema", "vivid", "atmosphere"] {
            var appearance = store.studio.appearance; appearance.theme = theme
            let card = ProfileStylePreview(theme: theme)
            let controller = ProfileController(store: store, profileID: profile.id, preview: true, appearanceOverride: appearance)
            addChild(controller); card.install(controller.view); controller.didMove(toParent: self)
            controller.view.isUserInteractionEnabled = false
            card.onSelect = { [weak self] in
                guard let self else { return }
                self.store.changeStudio { $0.appearance.theme = theme }
                self.cards.forEach { $0.setSelected($0.theme == theme) }
            }
            card.setSelected(theme == store.studio.appearance.theme)
            content.addArrangedSubview(card); cards.append(card)
        }
    }
}

private final class ProfileStylePreview: UIView {
    let theme: String
    var onSelect: (() -> Void)?
    private let viewport = UIView()
    private let button = UIButton(configuration: .glass())
    private weak var preview: UIView?
    init(theme: String) {
        self.theme = theme; super.init(frame: .zero)
        layer.cornerRadius = 28; layer.cornerCurve = .continuous; clipsToBounds = true
        backgroundColor = .secondarySystemBackground
        let label = makeLabel(.headline, text: StudioLabels.title(theme))
        button.configuration?.cornerStyle = .capsule; button.configuration?.baseForegroundColor = .kadrPeach
        button.addAction(UIAction { [weak self] _ in self?.onSelect?() }, for: .primaryActionTriggered)
        let title = UIStackView(arrangedSubviews: [label, button]); title.alignment = .center; title.spacing = 12
        button.setContentHuggingPriority(.required, for: .horizontal)
        let header = UIView(); title.pin(to: header, insets: .init(top: 16, leading: 20, bottom: 16, trailing: 16))
        let stack = UIStackView(arrangedSubviews: [viewport, header]); stack.axis = .vertical; stack.spacing = 0
        stack.pin(to: self)
        viewport.clipsToBounds = true; viewport.heightAnchor.constraint(equalTo: viewport.widthAnchor, multiplier: 1.9).isActive = true
        isAccessibilityElement = false
    }
    required init?(coder: NSCoder) { fatalError("Use init(theme:)") }
    func install(_ view: UIView) { preview = view; viewport.addSubview(view); setNeedsLayout() }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard let preview else { return }
        let sourceWidth: CGFloat = 390
        let scale = viewport.bounds.width / sourceWidth
        preview.transform = .identity
        preview.bounds = CGRect(x: 0, y: 0, width: sourceWidth, height: viewport.bounds.height / max(0.1, scale))
        preview.center = CGPoint(x: viewport.bounds.midX, y: viewport.bounds.midY)
        preview.transform = CGAffineTransform(scaleX: scale, y: scale)
    }
    func setSelected(_ selected: Bool) {
        button.configuration?.title = selected ? "Обрано" : "Обрати"
        button.configuration?.image = selected ? AppSymbol.image("checkmark") : nil
        button.configuration?.imagePadding = 6
        button.accessibilityLabel = (selected ? "Обрано: " : "Обрати: ") + StudioLabels.title(theme)
    }
}
