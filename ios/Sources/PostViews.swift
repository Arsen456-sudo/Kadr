import AVFoundation
import PhotosUI
import UIKit
import Symbols
import UniformTypeIdentifiers

final class CommentsController: UIViewController, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate {
    private let store: LocalStore
    private let clip: Clip
    private let table = UITableView()
    private let field = UITextField()
    private let send = GlyphButton(symbol: "arrow.up", label: "Надіслати коментар")
    private var comments: [Comment] = []
    private var replyTo: UUID?
    private var sort = "new"
    var onAccount: (() -> Void)?
    var onComment: (() -> Void)?

    init(store: LocalStore, clip: Clip) {
        self.store = store
        self.clip = clip
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Use init(store:clip:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Коментарі"
        view.backgroundColor = .systemBackground
        table.dataSource = self
        table.delegate = self
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Порядок", menu: UIMenu(children: [
            UIAction(title: "Нові") { [weak self] _ in self?.sort = "new"; self?.refreshComments() },
            UIAction(title: "Популярні") { [weak self] _ in self?.sort = "popular"; self?.refreshComments() },
            UIAction(title: "Від автора") { [weak self] _ in self?.sort = "author"; self?.refreshComments() }
        ]))
        table.rowHeight = UITableView.automaticDimension; table.estimatedRowHeight = 80
        table.keyboardDismissMode = .interactive
        table.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(table)

        let composer: UIView
        if store.active == nil {
            composer = textButton("Увійти, щоб коментувати", prominent: true) { [weak self] in self?.onAccount?() }
        } else {
            field.borderStyle = .none
            field.placeholder = "Написати коментар"
            field.returnKeyType = .send
            field.delegate = self
            field.font = .preferredFont(forTextStyle: .body)
            field.adjustsFontForContentSizeCategory = true
            field.addAction(UIAction { [weak self] _ in self?.updateSendButton() }, for: .editingChanged)
            send.addAction(UIAction { [weak self] _ in self?.sendComment() }, for: .primaryActionTriggered)
            let fieldIsland = glassIsland()
            field.pin(to: fieldIsland.contentView, insets: .init(top: 0, leading: 16, bottom: 0, trailing: 16))
            fieldIsland.heightAnchor.constraint(equalToConstant: 48).isActive = true
            let row = UIStackView(arrangedSubviews: [fieldIsland, send])
            row.alignment = .center
            row.spacing = 8
            let group = glassGroup()
            row.pin(to: group.contentView)
            composer = group
        }
        composer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(composer)
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            table.topAnchor.constraint(equalTo: safe.topAnchor),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: composer.topAnchor, constant: -8),
            composer.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 16),
            composer.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),
            composer.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -8),
            composer.heightAnchor.constraint(greaterThanOrEqualToConstant: 48)
        ])
        updateSendButton()
        refreshComments()
    }

    private var draft: String { (field.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }

    private func updateSendButton() {
        send.isEnabled = !draft.isEmpty && draft.count <= 500
        if let text = field.text, let at = text.lastIndex(of: "@") {
            let term = String(text[text.index(after: at)...])
            let toolbar = UIToolbar(); toolbar.sizeToFit()
            toolbar.items = store.searchProfiles(term).prefix(4).map { profile in
                UIBarButtonItem(title: "@" + profile.handle, primaryAction: UIAction { [weak self] _ in
                    self?.field.text = String(text[..<at]) + "@" + profile.handle + " "
                    self?.field.inputAccessoryView = nil; self?.field.reloadInputViews()
                })
            }
            field.inputAccessoryView = toolbar
        } else { field.inputAccessoryView = nil }
        if field.isFirstResponder { field.reloadInputViews() }
    }

    private func sendComment() {
        guard send.isEnabled else { return }
        guard store.addComment(draft, to: clip, parentID: replyTo) else {
            showMessage(store.errorMessage ?? "Не вдалося зберегти коментар.")
            store.errorMessage = nil
            return
        }
        field.text = nil
        replyTo = nil
        field.placeholder = "Написати коментар"
        updateSendButton()
        refreshComments()
        table.scrollToRow(at: IndexPath(row: comments.count - 1, section: 0), at: .bottom,
                          animated: !UIAccessibility.isReduceMotionEnabled)
        if store.studio.preferences.haptics { UISelectionFeedbackGenerator().selectionChanged() }
        onComment?()
    }

    private func refreshComments() {
        let all = store.comments(clip)
        let sorted = all.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned == true }
            if sort == "popular", (a.likes?.count ?? 0) != (b.likes?.count ?? 0) { return (a.likes?.count ?? 0) > (b.likes?.count ?? 0) }
            if sort == "author", (a.authorID == clip.authorID) != (b.authorID == clip.authorID) { return a.authorID == clip.authorID }
            return (a.createdAt ?? .distantPast) > (b.createdAt ?? .distantPast)
        }
        var ordered: [Comment] = []
        var visited = Set<UUID>()
        func append(_ comment: Comment) {
            guard visited.insert(comment.id).inserted else { return }
            ordered.append(comment)
            for reply in sorted where reply.parentID == comment.id { append(reply) }
        }
        for comment in sorted where comment.parentID == nil { append(comment) }
        for comment in sorted { append(comment) }
        comments = ordered
        if comments.isEmpty {
            var empty = UIContentUnavailableConfiguration.empty()
            empty.text = "Коментарів ще немає"
            empty.image = AppSymbol.image( "bubble")
            contentUnavailableConfiguration = nil
            table.backgroundView = UIContentUnavailableView(configuration: empty)
            table.backgroundView?.isUserInteractionEnabled = false
        } else {
            table.backgroundView = nil
        }
        table.reloadData()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        sendComment()
        return false
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { comments.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let comment = comments[indexPath.row]
        let profile = store.profile(comment.authorID)
        let cell = tableView.dequeueReusableCell(withIdentifier: "comment") ??
            UITableViewCell(style: .default, reuseIdentifier: "comment")
        var configuration = cell.defaultContentConfiguration()
        configuration.text = profile.map { "@\($0.handle)" + ($0.id == clip.authorID ? " · Автор" : "") }
        if comment.pinned == true { configuration.text = "📌 " + (configuration.text ?? "") }
        configuration.secondaryText = comment.text + ((comment.likes?.isEmpty == false) ? "  ♥ \(comment.likes?.count ?? 0)" : "")
        cell.indentationLevel = comment.parentID == nil ? 0 : 1
        configuration.textProperties.color = .kadrPeach
        configuration.secondaryTextProperties.color = .label
        configuration.image = profile?.avatar.flatMap { UIImage(data: $0) } ?? AppSymbol.image( "person.crop.circle.fill")
        configuration.imageProperties.maximumSize = CGSize(width: 34, height: 34)
        configuration.imageProperties.cornerRadius = 17
        configuration.imageProperties.tintColor = .kadrPeach
        cell.contentConfiguration = configuration
        cell.selectionStyle = .none
        return cell
    }
    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let comment = comments[indexPath.row]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            var actions = [UIAction(title: "Відповісти", image: AppSymbol.image("arrowshape.turn.up.left")) { [weak self] _ in
                self?.replyTo = comment.id; self?.field.placeholder = "Відповідь @" + (self?.store.profile(comment.authorID)?.handle ?? "")
                self?.field.becomeFirstResponder()
            }, UIAction(title: "Подобається", image: AppSymbol.image("heart")) { [weak self] _ in
                guard let self else { return }; self.store.toggleCommentLike(comment, clip: self.clip); self.refreshComments()
            }]
            if self.clip.authorID == self.store.active?.id {
                actions.append(UIAction(title: "Закріпити / відкріпити", image: AppSymbol.image("pin")) { [weak self] _ in
                    guard let self else { return }; self.store.pinComment(comment, clip: self.clip); self.refreshComments()
                })
            }
            if comment.authorID == self.store.active?.id {
                actions.append(UIAction(title: "Редагувати", image: AppSymbol.image("pencil")) { [weak self] _ in
                    guard let self else { return }
                    let alert = UIAlertController(title: "Коментар", message: nil, preferredStyle: .alert)
                    alert.addTextField { $0.text = comment.text }
                    alert.addAction(UIAlertAction(title: "Зберегти", style: .default) { [weak self] _ in
                        guard let self else { return }; self.store.updateComment(comment, clip: self.clip, text: alert.textFields?.first?.text ?? ""); self.refreshComments()
                    })
                    alert.addAction(UIAlertAction(title: "Скасувати", style: .cancel)); self.present(alert, animated: true)
                })
            }
            if comment.authorID == self.store.active?.id || self.clip.authorID == self.store.active?.id {
                actions.append(UIAction(title: "Видалити", image: AppSymbol.image("trash"), attributes: .destructive) { [weak self] _ in
                    guard let self else { return }; self.store.deleteComment(comment, clip: self.clip); self.refreshComments()
                })
            }
            return UIMenu(children: actions)
        }
    }

}

final class ClipPreviewController: UIViewController {
    private let clip: Clip
    private let store: LocalStore?
    private let video = VideoSurface(frame: .zero)
    private var paused = false
    private let playbackButton = makePlaybackButton(symbol: "pause.fill", label: "Призупинити")
    private let tapArea = UIButton(type: .custom)

    init(clip: Clip, store: LocalStore? = nil) {
        self.store = store
        self.clip = clip
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Use init(clip:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = clip.caption
        view.backgroundColor = .black
        if clip.isPhoto {
            embed(PhotoAlbumController(media: clip.media ?? [], extras: clip.extras ?? PostExtras()), in: view)
            return
        }
        video.pin(to: view)
        video.load(clip.url, adaptsLandscape: true, extras: clip.extras)
        if let watch = store?.studio.watches[clip.id], !watch.completed { video.seek(to: watch.seconds) }
        video.preferredRate = store?.studio.preferences.playbackRate ?? 1
        tapArea.accessibilityIdentifier = "video.playbackArea"
        tapArea.accessibilityLabel = "Призупинити відео"
        tapArea.pin(to: view)
        tapArea.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.setPaused(!self.paused)
        }, for: .primaryActionTriggered)
        let control = playbackButton
        view.addSubview(control)
        NSLayoutConstraint.activate([
            control.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            control.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -14)
        ])
        control.addAction(UIAction { [weak self, weak control] _ in
            guard let self, let control else { return }
            self.setPaused(control.isSelected)
        }, for: .primaryActionTriggered)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        video.setPlaying(!paused, muted: false)
        if !clip.isPhoto { playbackButton.showForInteraction() }
    }

    private func setPaused(_ value: Bool) {
        paused = value
        playbackButton.isSelected = value
        tapArea.accessibilityLabel = value ? "Відтворити відео" : "Призупинити відео"
        video.setPlaying(!value)
        playbackButton.showForInteraction()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        let progress = video.progress
        store?.recordWatch(clip, seconds: clip.isPhoto ? 1 : progress.seconds, duration: clip.isPhoto ? 1 : progress.duration)
        video.setPlaying(false)
        playbackButton.hideAfterContextChange()
    }
}
