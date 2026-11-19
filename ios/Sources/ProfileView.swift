import AVFoundation
import PhotosUI
import UIKit
import UniformTypeIdentifiers

final class ProfileController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout,
                               PHPickerViewControllerDelegate {
    private let store: LocalStore
    private let profileID: UUID?
    private let layout = UICollectionViewFlowLayout()
    private lazy var grid = UICollectionView(frame: .zero, collectionViewLayout: layout)
    private var visibleProfile: Profile?
    private var clips: [Clip] = []
    private var guestView: EmptyStateView?
    private var followState: Bool?
    private var lastSize: CGSize = .zero
    private var visible = false
    private var pickerOwner: UUID?
    var edgeScrollView: UIScrollView { grid }
    var onClip: ((Clip) -> Void)?
    var onAccount: (() -> Void)?
    var onChange: (() -> Void)?

    init(store: LocalStore, profileID: UUID?) {
        self.store = store
        self.profileID = profileID
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Use init(store:profileID:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        layout.minimumInteritemSpacing = 2
        layout.minimumLineSpacing = 2
        grid.backgroundColor = .systemBackground
        grid.contentInsetAdjustmentBehavior = .never
        grid.accessibilityIdentifier = "profile.screen"
        grid.dataSource = self
        grid.delegate = self
        grid.register(ClipThumbnailCell.self, forCellWithReuseIdentifier: "clip")
        grid.register(ProfileHero.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                      withReuseIdentifier: "hero")
        grid.pin(to: view)
        refresh()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if lastSize != view.bounds.size {
            lastSize = view.bounds.size
            layout.invalidateLayout()
        }
        grid.contentInset.bottom = view.safeAreaInsets.bottom
        grid.verticalScrollIndicatorInsets = view.safeAreaInsets
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        visible = true
        hero?.setPlaying(true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        visible = false
        hero?.setPlaying(false)
    }

    func refresh() {
        guard isViewLoaded else { return }
        let profile = profileID.flatMap { store.profile($0) } ?? (profileID == nil ? store.active : nil)
        let resetScroll = visibleProfile?.id != profile?.id
        let changedBanner = visibleProfile?.bannerFile != profile?.bannerFile
        visibleProfile = profile
        if let profile {
            guestView?.removeFromSuperview()
            guestView = nil
            grid.isHidden = false
            title = profileID == nil ? "Профіль" : "@\(profile.handle)"
            let newClips = store.allClips.filter { $0.authorID == profile.id }
            let state: Bool? = store.active != nil && store.active?.id != profile.id ? store.follows(profile) : nil
            if resetScroll || changedBanner || state != followState || clips.map(\.id) != newClips.map(\.id) {
                clips = newClips
                followState = state
                grid.reloadData()
                if resetScroll { grid.setContentOffset(.zero, animated: false) }
            }
        } else {
            hero?.setPlaying(false)
            grid.isHidden = true
            clips = []
            followState = nil
            if guestView == nil {
                let action = textButton("Увійти або створити акаунт") { [weak self] in self?.onAccount?() }
                let empty = EmptyStateView(title: "Твій профіль", message: "Створи акаунт, щоб додати фото, нікнейм і власні відео.",
                                           symbol: "person.crop.circle", action: action)
                empty.pin(to: view)
                guestView = empty
            }
            grid.reloadData()
        }
    }

    private var hero: ProfileHero? {
        grid.supplementaryView(forElementKind: UICollectionView.elementKindSectionHeader,
                               at: IndexPath(item: 0, section: 0)) as? ProfileHero
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { clips.count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "clip", for: indexPath) as! ClipThumbnailCell
        cell.show(clips[indexPath.item])
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        onClip?(clips[indexPath.item])
    }

    func collectionView(_ collectionView: UICollectionView, layout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = floor((collectionView.bounds.width - 4) / 3)
        return CGSize(width: max(width, 1), height: max(width * 1.27, 1))
    }

    func collectionView(_ collectionView: UICollectionView, layout: UICollectionViewLayout,
                        referenceSizeForHeaderInSection section: Int) -> CGSize {
        guard visibleProfile != nil else { return .zero }
        let height = max(360, view.bounds.height - view.safeAreaInsets.bottom)
        return CGSize(width: collectionView.bounds.width, height: height + 52)
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView {
        let view = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "hero",
                                                                   for: indexPath) as! ProfileHero
        guard let profile = visibleProfile else { return view }
        let change: (() -> Void)? = store.active?.id == profile.id ? { [weak self] in self?.chooseBanner(for: profile) } : nil
        let follow = followState
        view.show(profile, hasPosts: !clips.isEmpty, edit: change, following: follow) { [weak self] in
            guard let self else { return }
            self.store.toggleFollow(profile)
            self.showStorageErrorIfNeeded()
            self.refresh()
            self.onChange?()
        }
        return view
    }

    func collectionView(_ collectionView: UICollectionView, willDisplaySupplementaryView view: UICollectionReusableView,
                        forElementKind elementKind: String, at indexPath: IndexPath) {
        (view as? ProfileHero)?.setPlaying(visible)
    }

    func collectionView(_ collectionView: UICollectionView, didEndDisplayingSupplementaryView view: UICollectionReusableView,
                        forElementOfKind elementKind: String, at indexPath: IndexPath) {
        (view as? ProfileHero)?.setPlaying(false)
    }

    private func chooseBanner(for profile: Profile) {
        if profile.bannerURL == nil {
            openBannerPicker(for: profile.id)
        } else {
            let menu = UIAlertController(title: "Банер профілю", message: nil, preferredStyle: .actionSheet)
            menu.addAction(UIAlertAction(title: "Вибрати фото або відео", style: .default) { [weak self] _ in
                self?.openBannerPicker(for: profile.id)
            })
            menu.addAction(UIAlertAction(title: "Прибрати банер", style: .destructive) { [weak self] _ in
                guard let self else { return }
                self.store.setBanner(nil, extension: "", for: profile.id)
                self.showStorageErrorIfNeeded()
                self.refresh()
            })
            menu.addAction(UIAlertAction(title: "Скасувати", style: .cancel))
            menu.popoverPresentationController?.sourceView = hero?.editButton ?? view
            present(menu, animated: true)
        }
    }

    private func openBannerPicker(for id: UUID) {
        pickerOwner = id
        var configuration = PHPickerConfiguration()
        configuration.filter = .any(of: [.images, .videos])
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let id = pickerOwner, let provider = results.first?.itemProvider else {
            pickerOwner = nil
            return
        }
        pickerOwner = nil
        if let format = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .movie) == true }) {
            provider.loadFileRepresentation(forTypeIdentifier: format) { [weak self] url, _ in
                guard let url else {
                    DispatchQueue.main.async { self?.showMessage("Не вдалося відкрити відео для банера.") }
                    return
                }
                let suffix = UTType(format)?.preferredFilenameExtension ?? "mov"
                let temporary = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).appendingPathExtension(suffix)
                do {
                    try FileManager.default.copyItem(at: url, to: temporary)
                } catch {
                    DispatchQueue.main.async { self?.showMessage("Не вдалося відкрити відео для банера.") }
                    return
                }
                Task { @MainActor [weak self] in
                    defer { try? FileManager.default.removeItem(at: temporary) }
                    let asset = AVURLAsset(url: temporary)
                    guard (try? await asset.load(.isPlayable)) == true,
                          let tracks = try? await asset.loadTracks(withMediaType: .video), !tracks.isEmpty else {
                        self?.showMessage("Це відео не можна відтворити.")
                        return
                    }
                    self?.saveBanner(temporary, suffix: suffix, owner: id)
                }
            }
        } else {
            provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                DispatchQueue.main.async {
                    guard let self, let image = object as? UIImage, image.size.width > 0, image.size.height > 0 else {
                        self?.showMessage("Не вдалося відкрити фото для банера.")
                        return
                    }
                    let scale = min(1, 1600 / max(image.size.width, image.size.height))
                    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                    let format = UIGraphicsImageRendererFormat()
                    format.scale = 1
                    let data = UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 0.88) { _ in
                        image.draw(in: CGRect(origin: .zero, size: size))
                    }
                    let temporary = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
                    defer { try? FileManager.default.removeItem(at: temporary) }
                    do {
                        try data.write(to: temporary, options: .atomic)
                        self.saveBanner(temporary, suffix: "jpg", owner: id)
                    } catch {
                        self.showMessage("Не вдалося записати фото для банера.")
                    }
                }
            }
        }
    }

    private func saveBanner(_ url: URL, suffix: String, owner: UUID) {
        guard store.active?.id == owner else { return }
        if store.setBanner(url, extension: suffix, for: owner) {
            refresh()
        } else {
            showStorageErrorIfNeeded()
        }
    }

    private func showStorageErrorIfNeeded() {
        if let error = store.errorMessage {
            store.errorMessage = nil
            showMessage(error)
        }
    }
}

private final class ProfileHero: UICollectionReusableView {
    private let artwork = UIImageView()
    private let video = VideoSurface(frame: .zero)
    private let shade = GradientView()
    private let footer = makeLabel(.headline)
    private let identity = UIStackView()
    private var isVideo = false
    private(set) var editButton: UIButton?

    override init(frame: CGRect) {
        super.init(frame: frame)
        let banner = UIView()
        banner.clipsToBounds = true
        banner.backgroundColor = UIColor(red: 0.19, green: 0.13, blue: 0.29, alpha: 1)
        artwork.contentMode = .scaleAspectFill
        artwork.clipsToBounds = true
        artwork.pin(to: banner)
        video.pin(to: banner)
        shade.gradient.startPoint = CGPoint(x: 0.5, y: 0)
        shade.gradient.endPoint = CGPoint(x: 0.5, y: 1)
        shade.gradient.colors = [UIColor.black.withAlphaComponent(0.2).cgColor, UIColor.clear.cgColor,
                                 UIColor.black.withAlphaComponent(0.56).cgColor,
                                 UIColor.systemBackground.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)).cgColor]
        shade.gradient.locations = [0, 0.34, 0.75, 1]
        shade.pin(to: banner)
        shade.isUserInteractionEnabled = false
        identity.axis = .vertical
        identity.alignment = .leading
        identity.spacing = 7
        identity.translatesAutoresizingMaskIntoConstraints = false
        banner.addSubview(identity)
        let contents = UIStackView(arrangedSubviews: [banner, footer])
        contents.axis = .vertical
        contents.pin(to: self)
        footer.heightAnchor.constraint(equalToConstant: 52).isActive = true
        footer.textAlignment = .center
        NSLayoutConstraint.activate([
            identity.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 20),
            identity.trailingAnchor.constraint(lessThanOrEqualTo: banner.trailingAnchor, constant: -20),
            identity.bottomAnchor.constraint(equalTo: banner.bottomAnchor, constant: -22)
        ])
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    override func prepareForReuse() {
        super.prepareForReuse()
        video.load(nil)
    }

    func show(_ profile: Profile, hasPosts: Bool, edit: (() -> Void)?, following: Bool?, onFollow: @escaping () -> Void) {
        identity.arrangedSubviews.forEach { $0.removeFromSuperview() }
        editButton = nil
        let avatar = avatarView(profile.avatar)
        avatar.layer.cornerRadius = 35
        avatar.backgroundColor = .systemBackground
        avatar.widthAnchor.constraint(equalToConstant: 70).isActive = true
        avatar.heightAnchor.constraint(equalToConstant: 70).isActive = true
        identity.addArrangedSubview(avatar)
        let name = makeLabel(.title1, text: profile.name)
        name.font = name.font.withTraits(.traitBold)
        identity.addArrangedSubview(name)
        identity.addArrangedSubview(makeLabel(.subheadline, text: "@\(profile.handle)", color: .secondaryLabel))
        if !profile.bio.isEmpty { identity.addArrangedSubview(makeLabel(.body, text: profile.bio)) }
        if let edit {
            let button = textButton("Змінити банер", symbol: "photo.on.rectangle", action: edit)
            editButton = button
            identity.addArrangedSubview(button)
        } else if let following {
            identity.addArrangedSubview(textButton(following ? "Відписатися" : "Підписатися",
                                                   prominent: !following, action: onFollow))
        }
        footer.text = hasPosts ? "Публікації" : "Поки немає відео"
        let url = profile.bannerURL
        isVideo = url.flatMap { UTType(filenameExtension: $0.pathExtension) }?.conforms(to: .movie) == true
        artwork.image = isVideo ? nil : url.flatMap { UIImage(contentsOfFile: $0.path) }
        video.isHidden = !isVideo
        video.load(isVideo ? url : nil)
    }

    func setPlaying(_ playing: Bool) {
        video.setPlaying(playing && isVideo, muted: true)
    }
}

private final class ClipThumbnailCell: UICollectionViewCell {
    private let image = UIImageView()
    private let play = UIImageView(image: UIImage(systemName: "play.fill"))
    private var task: Task<Void, Never>?
    private var representedID: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        contentView.backgroundColor = .secondarySystemBackground
        image.contentMode = .scaleAspectFill
        image.clipsToBounds = true
        image.pin(to: contentView)
        play.contentMode = .scaleAspectFit
        play.tintColor = .white
        play.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        play.layer.shadowColor = UIColor.black.cgColor
        play.layer.shadowOpacity = 0.8
        play.layer.shadowRadius = 3
        play.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(play)
        NSLayoutConstraint.activate([
            play.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            play.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8)
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    override func prepareForReuse() {
        super.prepareForReuse()
        task?.cancel()
        representedID = nil
        image.image = nil
    }

    func show(_ clip: Clip) {
        task?.cancel()
        representedID = clip.id
        accessibilityLabel = clip.caption
        image.image = nil
        guard let url = clip.url else { return }
        task = Task { [weak self] in
            guard let poster = await VideoPoster.image(for: url), !Task.isCancelled,
                  let self, self.representedID == clip.id else { return }
            self.image.image = UIImage(cgImage: poster)
        }
    }
}
