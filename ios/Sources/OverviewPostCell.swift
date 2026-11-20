import UIKit

final class OverviewPostCell: UICollectionViewCell {
    let mediaContainer = UIView()
    private let author = UIButton(configuration: .plain())
    private let like = UIButton(configuration: .plain())
    private let comments = UIButton(configuration: .plain())
    private let bookmark = UIButton(configuration: .plain())
    private let sound = UIButton(configuration: .plain())
    private let descriptionButton = UIButton(configuration: .plain())
    var onAuthor: (() -> Void)?
    var onLike: (() -> Void)?
    var onComments: (() -> Void)?
    var onBookmark: (() -> Void)?
    var onSound: (() -> Void)?
    var onDescription: (() -> Void)?
    private var mediaHeight: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .systemBackground
        let spacer = UIView()
        let actions = UIStackView(arrangedSubviews: [like, comments, spacer, sound, bookmark])
        actions.spacing = 8
        let stack = UIStackView(arrangedSubviews: [author, mediaContainer, actions, descriptionButton])
        stack.axis = .vertical
        stack.spacing = 0
        stack.pin(to: contentView)
        mediaHeight = mediaContainer.heightAnchor.constraint(equalToConstant: 300)
        mediaHeight.isActive = true
        author.heightAnchor.constraint(equalToConstant: 48).isActive = true
        actions.heightAnchor.constraint(equalToConstant: 44).isActive = true
        descriptionButton.heightAnchor.constraint(equalToConstant: 56).isActive = true
        author.contentHorizontalAlignment = .leading
        descriptionButton.contentHorizontalAlignment = .leading
        author.addAction(UIAction { [weak self] _ in self?.onAuthor?() }, for: .primaryActionTriggered)
        like.addAction(UIAction { [weak self] _ in self?.onLike?() }, for: .primaryActionTriggered)
        comments.addAction(UIAction { [weak self] _ in self?.onComments?() }, for: .primaryActionTriggered)
        sound.addAction(UIAction { [weak self] _ in self?.onSound?() }, for: .primaryActionTriggered)
        bookmark.addAction(UIAction { [weak self] _ in self?.onBookmark?() }, for: .primaryActionTriggered)
        descriptionButton.addAction(UIAction { [weak self] _ in self?.onDescription?() }, for: .primaryActionTriggered)
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    func show(_ clip: Clip, store: LocalStore, mediaHeight height: CGFloat, muted: Bool) {
        mediaHeight.constant = height
        var heading = author.configuration!
        heading.title = store.profile(clip.authorID).map { "@\($0.handle)" } ?? clip.credit
        heading.image = store.profile(clip.authorID)?.avatar.flatMap { UIImage(data: $0) } ?? UIImage(systemName: "person.crop.circle")
        // Avoid full-size avatar data determining the button's intrinsic width.
        if let image = heading.image {
            heading.image = image.preparingThumbnail(of: CGSize(width: 30, height: 30))
        }
        heading.imagePadding = 8
        heading.baseForegroundColor = .label
        author.configuration = heading
        author.imageView?.layer.cornerRadius = 15
        author.imageView?.clipsToBounds = true
        author.isEnabled = clip.authorID != nil
        like.configuration?.image = UIImage(systemName: store.liked(clip) ? "heart.fill" : "heart")
        like.configuration?.title = String(store.likes(clip))
        like.configuration?.baseForegroundColor = store.liked(clip) ? .kadrPeach : .label
        like.accessibilityLabel = "Подобається"
        like.accessibilityValue = String(store.likes(clip))
        comments.configuration?.image = UIImage(systemName: "bubble")
        comments.configuration?.title = String(store.comments(clip).count)
        comments.isHidden = !clip.settings.allowsComments
        comments.accessibilityLabel = "Коментарі"
        bookmark.configuration?.image = UIImage(systemName: store.bookmarked(clip) ? "bookmark.fill" : "bookmark")
        bookmark.accessibilityLabel = "Зберегти"
        sound.isHidden = clip.isPhoto
        sound.configuration?.image = UIImage(systemName: muted ? "speaker.slash" : "speaker.wave.2")
        sound.accessibilityLabel = muted ? "Увімкнути звук" : "Вимкнути звук"
        var description = descriptionButton.configuration!
        description.title = clip.caption.isEmpty ? "Відкрити опис" : clip.caption
        description.subtitle = "Повний опис ›"
        description.titleLineBreakMode = .byTruncatingTail
        description.baseForegroundColor = .label
        descriptionButton.configuration = description
        descriptionButton.titleLabel?.numberOfLines = 1
        descriptionButton.accessibilityLabel = "Відкрити повний опис"
    }
}

final class PostDescriptionController: UIViewController {
    private let clip: Clip
    private let store: LocalStore
    init(clip: Clip, store: LocalStore) {
        self.clip = clip
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(clip:store:)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Опис публікації"
        view.backgroundColor = .systemBackground
        let scroll = UIScrollView()
        scroll.pin(to: view)
        let author = makeLabel(.headline, text: store.profile(clip.authorID).map { "@\($0.handle)" } ?? clip.credit)
        let text = makeLabel(.body, text: clip.caption.isEmpty ? "Без опису" : clip.caption)
        let tags = makeLabel(.subheadline, text: clip.settings.tags, color: .kadrPeach)
        let location = makeLabel(.subheadline, text: clip.settings.location, color: .secondaryLabel)
        let stack = UIStackView(arrangedSubviews: [author, text, tags, location])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40)
        ])
    }
}
