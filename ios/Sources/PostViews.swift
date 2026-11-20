import AVFoundation
import PhotosUI
import UIKit
import Symbols
import UniformTypeIdentifiers

final class CommentsController: UIViewController, UITableViewDataSource, UITextFieldDelegate {
    private let store: LocalStore
    private let clip: Clip
    private let table = UITableView()
    private let field = UITextField()
    private let send = GlyphButton(symbol: "arrow.up", label: "Надіслати коментар")
    private var comments: [Comment] = []
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
    }

    private func sendComment() {
        guard send.isEnabled else { return }
        guard store.addComment(draft, to: clip) else {
            showMessage(store.errorMessage ?? "Не вдалося зберегти коментар.")
            store.errorMessage = nil
            return
        }
        field.text = nil
        updateSendButton()
        refreshComments()
        table.scrollToRow(at: IndexPath(row: comments.count - 1, section: 0), at: .bottom,
                          animated: !UIAccessibility.isReduceMotionEnabled)
        UISelectionFeedbackGenerator().selectionChanged()
        onComment?()
    }

    private func refreshComments() {
        comments = store.comments(clip)
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
        configuration.text = profile.map { "@\($0.handle)" }
        configuration.textProperties.color = .kadrPeach
        configuration.secondaryText = comment.text
        configuration.secondaryTextProperties.color = .label
        configuration.image = profile?.avatar.flatMap { UIImage(data: $0) } ?? AppSymbol.image( "person.crop.circle.fill")
        configuration.imageProperties.maximumSize = CGSize(width: 34, height: 34)
        configuration.imageProperties.cornerRadius = 17
        configuration.imageProperties.tintColor = .kadrPeach
        cell.contentConfiguration = configuration
        cell.selectionStyle = .none
        return cell
    }
}

final class ClipPreviewController: UIViewController {
    private let clip: Clip
    private let video = VideoSurface(frame: .zero)
    private var paused = false
    private let playbackButton = makePlaybackButton(symbol: "pause.fill", label: "Призупинити")
    private let tapArea = UIButton(type: .custom)

    init(clip: Clip) {
        self.clip = clip
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Use init(clip:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = clip.caption
        view.backgroundColor = .black
        if clip.isPhoto {
            embed(PhotoAlbumController(media: clip.media ?? []), in: view)
            return
        }
        video.pin(to: view)
        video.load(clip.url, adaptsLandscape: true)
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
        video.setPlaying(false)
        playbackButton.hideAfterContextChange()
    }
}
