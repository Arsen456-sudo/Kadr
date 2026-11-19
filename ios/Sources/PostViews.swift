import AVFoundation
import PhotosUI
import UIKit
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
            composer = row
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
            empty.image = UIImage(systemName: "bubble")
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
        configuration.image = profile?.avatar.flatMap { UIImage(data: $0) } ?? UIImage(systemName: "person.crop.circle.fill")
        configuration.imageProperties.maximumSize = CGSize(width: 34, height: 34)
        configuration.imageProperties.cornerRadius = 17
        configuration.imageProperties.tintColor = .kadrPeach
        cell.contentConfiguration = configuration
        cell.selectionStyle = .none
        return cell
    }
}

final class PublishController: FormController, PHPickerViewControllerDelegate {
    private let store: LocalStore
    private let preview = VideoSurface(frame: .zero)
    private let caption = UITextField()
    private let busy = UIActivityIndicatorView(style: .medium)
    private lazy var submit = textButton("Опублікувати на пристрої", prominent: true) { [weak self] in self?.publish() }
    private var movie: URL?
    private var generation = 0
    var onPublish: ((Clip) -> Void)?

    init(store: LocalStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Use init(store:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Нове відео"
        content.addArrangedSubview(textButton("Вибрати відео", symbol: "film") { [weak self] in self?.pickVideo() })
        content.addArrangedSubview(busy)
        let previewHeight = preview.heightAnchor.constraint(equalToConstant: 205)
        previewHeight.priority = .defaultHigh
        previewHeight.isActive = true
        preview.layer.cornerRadius = 18
        preview.clipsToBounds = true
        preview.isHidden = true
        content.addArrangedSubview(preview)
        caption.placeholder = "Опис відео"
        caption.borderStyle = .roundedRect
        caption.font = .preferredFont(forTextStyle: .body)
        caption.adjustsFontForContentSizeCategory = true
        content.addArrangedSubview(caption)
        submit.isEnabled = false
        content.addArrangedSubview(submit)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        preview.setPlaying(false)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        preview.setPlaying(movie != nil)
    }

    private func pickVideo() {
        var configuration = PHPickerConfiguration()
        configuration.filter = .videos
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else { return }
        guard let format = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .movie) == true }) else {
            reportImportError()
            return
        }
        generation += 1
        let request = generation
        busy.startAnimating()
        submit.isEnabled = false
        provider.loadFileRepresentation(forTypeIdentifier: format) { [weak self] url, _ in
            guard let url else {
                DispatchQueue.main.async {
                    if self?.generation == request { self?.reportImportError() }
                }
                return
            }
            let suffix = url.pathExtension.isEmpty ? "mov" : url.pathExtension
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(suffix)
            do {
                try FileManager.default.copyItem(at: url, to: temporary)
            } catch {
                DispatchQueue.main.async {
                    if self?.generation == request { self?.reportImportError() }
                }
                return
            }
            Task { @MainActor [weak self] in
                let asset = AVURLAsset(url: temporary)
                let playable = (try? await asset.load(.isPlayable)) == true
                let tracks = playable ? (try? await asset.loadTracks(withMediaType: .video)) : nil
                let hasVideo = tracks?.isEmpty == false
                guard let self, self.generation == request, hasVideo else {
                    try? FileManager.default.removeItem(at: temporary)
                    if self?.generation == request { self?.reportImportError() }
                    return
                }
                self.preview.load(temporary, adaptsLandscape: true)
                if let old = self.movie { try? FileManager.default.removeItem(at: old) }
                self.movie = temporary
                self.preview.isHidden = false
                self.preview.setPlaying(true)
                self.busy.stopAnimating()
                self.submit.isEnabled = true
            }
        }
    }

    private func reportImportError() {
        busy.stopAnimating()
        submit.isEnabled = movie != nil
        showMessage("Не вдалося імпортувати відео.")
    }

    private func publish() {
        guard let movie else { return }
        let text = (caption.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let clip = store.publish(movie, caption: text.isEmpty ? "Нове відео" : String(text.prefix(200))) else {
            showMessage(store.errorMessage ?? "Не вдалося опублікувати відео.")
            store.errorMessage = nil
            return
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onPublish?(clip)
    }

    deinit {
        if let movie { try? FileManager.default.removeItem(at: movie) }
    }
}

final class ClipPreviewController: UIViewController {
    private let clip: Clip
    private let video = VideoSurface(frame: .zero)
    private var paused = false

    init(clip: Clip) {
        self.clip = clip
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Use init(clip:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = clip.caption
        view.backgroundColor = .black
        video.pin(to: view)
        video.load(clip.url, adaptsLandscape: true)
        let control = makePlaybackButton(symbol: "pause.fill", label: "Призупинити")
        view.addSubview(control)
        NSLayoutConstraint.activate([
            control.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            control.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -14)
        ])
        control.addAction(UIAction { [weak self, weak control] _ in
            guard let self else { return }
            self.paused.toggle()
            self.video.setPlaying(!self.paused)
            if let control {
                var configuration = control.configuration
                configuration?.image = UIImage(systemName: self.paused ? "play.fill" : "pause.fill",
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 30, weight: .semibold))
                control.accessibilityLabel = self.paused ? "Відтворити" : "Призупинити"
                if UIAccessibility.isReduceMotionEnabled { control.configuration = configuration }
                else {
                    UIView.transition(with: control, duration: 0.18, options: [.transitionCrossDissolve, .allowUserInteraction],
                                      animations: { control.configuration = configuration })
                }
            }
        }, for: .primaryActionTriggered)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        video.setPlaying(!paused, muted: false)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        video.setPlaying(false)
    }
}
