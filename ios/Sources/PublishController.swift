import AVFoundation
import AVKit
import PhotosUI
import UIKit
import UniformTypeIdentifiers

final class PublishController: UITableViewController, PHPickerViewControllerDelegate {
    private let store: LocalStore
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private var media: [(URL, MediaKind)] = []
    private var options = PostOptions()
    private let caption = UITextView()
    private let tags = UITextField()
    private let location = UITextField()
    private let comments = UISwitch()
    private let privacy = UISwitch()
    private var coverTask: Task<Void, Never>?
    private var importing = false
    private var importTask: Task<Void, Never>?
    var onPublish: ((Clip) -> Void)?
    var onClose: (() -> Void)?

    init(store: LocalStore) {
        self.store = store
        super.init(style: .insetGrouped)
    }
    required init?(coder: NSCoder) { fatalError("Use init(store:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Нова публікація"
        tableView.keyboardDismissMode = .interactive
        tableView.register(MediaEditCell.self, forCellReuseIdentifier: "media")
        tableView.allowsSelectionDuringEditing = true
        caption.font = .preferredFont(forTextStyle: .body)
        caption.backgroundColor = .clear
        caption.accessibilityLabel = "Опис публікації"
        tags.placeholder = "#подорожі #натхнення"
        location.placeholder = "Додати місце"
        for field in [tags, location] {
            field.font = .preferredFont(forTextStyle: .body)
            field.autocorrectionType = .no
        }
        comments.isOn = true
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.close() })
        navigationItem.rightBarButtonItem = editButtonItem
        if let draft = store.draft {
            media = (draft.media ?? []).map { ($0.url, $0.kind) }
            options = draft.settings
            caption.text = draft.caption
            tags.text = options.tags
            location.text = options.location
            comments.isOn = options.allowsComments
            privacy.isOn = options.onlyMe
        }
        isModalInPresentation = !media.isEmpty
        navigationController?.isModalInPresentation = isModalInPresentation
        reloadEditor()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 5 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 2
        case 1: return media.count
        case 2: return 3
        case 3: return 2
        default: return 2
        }
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "Створи свою історію"
        case 1: return media.isEmpty ? nil : "Медіа · \(media.count)"
        case 2: return "Про публікацію"
        case 3: return "Налаштування"
        default: return nil
        }
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 1 && !media.isEmpty {
            return "Натисни, щоб переглянути. Змахни рядок ліворуч для вибору обкладинки або видалення. «Редагувати» змінює порядок фото."
        }
        if section == 3 { return "Публікації та чернетки поки зберігаються на цьому iPhone." }
        return nil
    }
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath.section == 1 { return 92 }
        if indexPath.section == 2 && indexPath.row == 0 { return 140 }
        return 56
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 1 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "media", for: indexPath) as! MediaEditCell
            cell.show(media[indexPath.row], number: indexPath.row + 1, cover: indexPath.row == options.coverIndex)
            return cell
        }
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        var content = cell.defaultContentConfiguration()
        cell.selectionStyle = .none
        switch indexPath.section {
        case 0:
            content.text = importing ? "Завантаження…" : indexPath.row == 0 ? "Додати фотографії" : "Вибрати відео"
            content.image = AppSymbol.image( indexPath.row == 0 ? "photo.on.rectangle.angled" : "video")
            content.textProperties.font = .preferredFont(forTextStyle: .headline)
            content.imageProperties.tintColor = .kadrPeach
            cell.accessoryType = .disclosureIndicator
        case 2:
            let field: UIView = indexPath.row == 0 ? caption : indexPath.row == 1 ? tags : location
            field.pin(to: cell.contentView, insets: .init(top: 10, leading: 16, bottom: 10, trailing: 16))
            if indexPath.row == 0 && caption.text.isEmpty { caption.accessibilityHint = "Додай опис своєї публікації" }
            return cell
        case 3:
            content.text = indexPath.row == 0 ? "Дозволити коментарі" : "Бачу тільки я"
            content.image = AppSymbol.image( indexPath.row == 0 ? "bubble.left" : "lock")
            cell.accessoryView = indexPath.row == 0 ? comments : privacy
        default:
            content.text = indexPath.row == 0 ? "Опублікувати" : "Зберегти чернетку"
            content.image = AppSymbol.image( indexPath.row == 0 ? "arrow.up.circle.fill" : "square.and.pencil")
            content.textProperties.font = .preferredFont(forTextStyle: .headline)
            content.textProperties.color = media.isEmpty || importing ? .tertiaryLabel : .kadrPeach
        }
        cell.contentConfiguration = content
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard !importing else { return }
        view.endEditing(true)
        switch indexPath.section {
        case 0: pick(photos: indexPath.row == 0)
        case 1: preview(indexPath.row)
        case 4: save(draft: indexPath.row == 1)
        default: break
        }
    }

    private func reloadEditor() {
        coverTask?.cancel()
        let container = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 248))
        let artwork = UIImageView()
        artwork.contentMode = .scaleAspectFill
        artwork.clipsToBounds = true
        artwork.layer.cornerRadius = 24
        artwork.backgroundColor = .secondarySystemGroupedBackground
        artwork.pin(to: container, insets: .init(top: 16, leading: 20, bottom: 8, trailing: 20))
        let button = textButton(media.isEmpty ? "Обрати фотографії" : "Переглянути",
                                symbol: media.isEmpty ? "photo.badge.plus" : "arrow.up.left.and.arrow.down.right") { [weak self] in
            guard let self, !self.importing else { return }
            if self.media.isEmpty { self.pick(photos: true) }
            else { self.preview(self.options.coverIndex) }
        }
        button.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        tableView.tableHeaderView = container
        if media.indices.contains(options.coverIndex) {
            let item = media[options.coverIndex]
            coverTask = Task { [weak artwork] in
                let image: UIImage?
                if item.1 == .photo { image = await PhotoLoader.image(item.0, maxPixel: 1200) }
                else { image = await VideoPoster.image(for: item.0).map { UIImage(cgImage: $0) } }
                guard !Task.isCancelled else { return }
                artwork?.image = image
            }
        }
        tableView.reloadData()
    }

    private func pick(photos: Bool) {
        var configuration = PHPickerConfiguration()
        configuration.filter = photos ? .images : .videos
        configuration.selectionLimit = photos ? 0 : 1
        configuration.selection = .ordered
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard !results.isEmpty else { return }
        importing = true
        isModalInPresentation = true
        navigationController?.isModalInPresentation = true
        reloadEditor()
        importTask = Task { [weak self] in
            guard let self else { return }
            var imported: [(URL, MediaKind)] = []
            var failed = 0
            for result in results {
                do {
                    let item = try await Self.importMedia(result.itemProvider, into: self.directory)
                    if item.1 == .video {
                        let asset = AVURLAsset(url: item.0)
                        guard (try? await asset.load(.isPlayable)) == true else {
                            try? FileManager.default.removeItem(at: item.0)
                            failed += 1
                            continue
                        }
                    }
                    imported.append(item)
                } catch { failed += 1 }
            }
            if let first = imported.first {
                if first.1 == .video || self.media.first?.1 == .video {
                    self.media = imported
                    self.options.coverIndex = 0
                } else { self.media.append(contentsOf: imported) }
            }
            self.importing = false
            self.isModalInPresentation = !self.media.isEmpty
            self.navigationController?.isModalInPresentation = self.isModalInPresentation
            self.reloadEditor()
            if failed > 0 { self.showMessage("Не вдалося імпортувати файлів: \(failed). Решту додано.") }
        }
    }

    private static func importMedia(_ provider: NSItemProvider, into directory: URL) async throws -> (URL, MediaKind) {
        let types = provider.registeredTypeIdentifiers.compactMap { UTType($0) }
        guard let type = types.first(where: { $0.conforms(to: .movie) || $0.conforms(to: .image) }) else {
            throw CocoaError(.fileReadUnknown)
        }
        let kind: MediaKind = type.conforms(to: .movie) ? .video : .photo
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, error in
                guard let url else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                    return
                }
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let suffix = url.pathExtension.isEmpty ? (type.preferredFilenameExtension ?? "dat") : url.pathExtension
                    let target = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(suffix)
                    try FileManager.default.copyItem(at: url, to: target)
                    continuation.resume(returning: (target, kind))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func preview(_ index: Int) {
        let post = Clip(id: UUID().uuidString, authorID: store.active?.id, caption: "Перегляд",
                        file: media[index].0.lastPathComponent, credit: "",
                        media: media.map { PostMedia(id: UUID(), kind: $0.1, file: "", remoteURL: $0.0) })
        if post.isPhoto {
            let album = PhotoAlbumController(media: post.media ?? [], index: index)
            navigationController?.pushViewController(album, animated: true)
        } else {
            let player = AVPlayerViewController()
            player.player = AVPlayer(url: media[index].0)
            present(player, animated: true) { player.player?.play() }
        }
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool { indexPath.section == 1 && !importing }
    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool { indexPath.section == 1 && media.count > 1 && !importing }
    override func tableView(_ tableView: UITableView, targetIndexPathForMoveFromRowAt source: IndexPath,
                            toProposedIndexPath proposed: IndexPath) -> IndexPath {
        proposed.section == 1 ? proposed : source
    }
    override func tableView(_ tableView: UITableView, moveRowAt source: IndexPath, to destination: IndexPath) {
        let cover = media[options.coverIndex].0
        let item = media.remove(at: source.row)
        media.insert(item, at: destination.row)
        options.coverIndex = media.firstIndex { $0.0 == cover } ?? 0
        reloadEditor()
    }
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        remove(indexPath.row)
    }
    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard indexPath.section == 1, !importing else { return nil }
        let delete = UIContextualAction(style: .destructive, title: "Видалити") { [weak self] _, _, done in
            self?.remove(indexPath.row)
            done(true)
        }
        let cover = UIContextualAction(style: .normal, title: "Обкладинка") { [weak self] _, _, done in
            self?.options.coverIndex = indexPath.row
            self?.reloadEditor()
            done(true)
        }
        return UISwipeActionsConfiguration(actions: media.first?.1 == .photo ? [delete, cover] : [delete])
    }
    private func remove(_ index: Int) {
        let cover = media.indices.contains(options.coverIndex) ? media[options.coverIndex].0 : nil
        media.remove(at: index)
        options.coverIndex = media.firstIndex { $0.0 == cover } ?? 0
        isModalInPresentation = !media.isEmpty
        navigationController?.isModalInPresentation = isModalInPresentation
        reloadEditor()
    }

    private func save(draft: Bool) {
        guard !media.isEmpty, !importing else { return }
        let text = caption.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count <= 2200 else { showMessage("Опис може містити до 2200 символів."); return }
        options.tags = tags.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        options.location = location.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        options.allowsComments = comments.isOn
        options.onlyMe = privacy.isOn
        guard let post = store.savePost(sources: media, caption: text, options: options, asDraft: draft) else {
            showMessage(store.errorMessage ?? "Не вдалося зберегти публікацію.")
            store.errorMessage = nil
            return
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if draft { onClose?() } else { onPublish?(post) }
    }
    private func close() {
        guard !importing else { return }
        guard !media.isEmpty else { onClose?(); return }
        let alert = UIAlertController(title: "Зберегти публікацію?", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Зберегти чернетку", style: .default) { [weak self] _ in self?.save(draft: true) })
        alert.addAction(UIAlertAction(title: "Закрити редактор", style: .destructive) { [weak self] _ in self?.onClose?() })
        alert.addAction(UIAlertAction(title: "Продовжити", style: .cancel))
        alert.popoverPresentationController?.barButtonItem = navigationItem.leftBarButtonItem
        present(alert, animated: true)
    }
    deinit {
        coverTask?.cancel()
        importTask?.cancel()
        try? FileManager.default.removeItem(at: directory)
    }
}

private final class MediaEditCell: UITableViewCell {
    private var task: Task<Void, Never>?
    override func prepareForReuse() {
        super.prepareForReuse()
        task?.cancel()
    }
    func show(_ media: (URL, MediaKind), number: Int, cover: Bool) {
        task?.cancel()
        var configuration = defaultContentConfiguration()
        configuration.text = media.1 == .photo ? "Фото \(number)" : "Відео"
        configuration.secondaryText = cover ? "Обкладинка" : nil
        configuration.image = AppSymbol.image( media.1 == .photo ? "photo" : "video")
        configuration.imageProperties.maximumSize = CGSize(width: 64, height: 72)
        configuration.imageProperties.cornerRadius = 10
        contentConfiguration = configuration
        accessoryType = .disclosureIndicator
        task = Task { [weak self] in
            let image: UIImage?
            if media.1 == .photo { image = await PhotoLoader.image(media.0, maxPixel: 240) }
            else { image = await VideoPoster.image(for: media.0).map { UIImage(cgImage: $0) } }
            guard !Task.isCancelled else { return }
            configuration.image = image ?? configuration.image
            self?.contentConfiguration = configuration
        }
    }
}
