import AVFoundation
import PhotosUI
import UIKit
import UniformTypeIdentifiers

final class ProfileController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate,
                               PHPickerViewControllerDelegate {
    private let store: LocalStore
    private let profileID: UUID?
    private var selectedSection = ProfileSection.posts
    private let sectionIsland = ProfileSectionPicker()
    var sectionInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16) { didSet { updateSectionPosition() } }
    var sectionPinTop: CGFloat? { didSet { updateSectionPosition() } }
    private enum PhotoDestination { case banner, avatar }
    private var pickerDestination = PhotoDestination.banner
    private lazy var layout = UICollectionViewCompositionalLayout { [weak self] _, environment in
        let width = environment.container.effectiveContentSize.width
        let side = (width - 4) / 3
        let size = NSCollectionLayoutSize(widthDimension: .absolute(side), heightDimension: .absolute(side * 1.27))
        let item = NSCollectionLayoutItem(layoutSize: size)
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(side * 1.27)),
            subitems: [item, item, item])
        group.interItemSpacing = .fixed(2)
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 2
        if let self, let profile = self.visibleProfile {
            let height = ProfileHero.height(for: profile, width: width, top: self.view.safeAreaInsets.top,
                                            showsFollow: self.followState != nil)
            section.boundarySupplementaryItems = [NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(height)),
                elementKind: UICollectionView.elementKindSectionHeader, alignment: .top)]
        }
        return section
    }
    private let backdrop = ProfileBackdrop()
    private var backdropHeight: NSLayoutConstraint!
    private lazy var grid = UICollectionView(frame: .zero, collectionViewLayout: layout)
    private var visibleProfile: Profile?
    private var clips: [Clip] = []
    private var guestView: EmptyStateView?
    private var followState: Bool?
    private var lastSize: CGSize = .zero
    private var lastSafeTop: CGFloat = -1
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
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backdrop)
        backdropHeight = backdrop.heightAnchor.constraint(equalToConstant: 260)
        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: view.topAnchor),
            backdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backdropHeight
        ])
        grid.backgroundColor = .clear
        grid.alwaysBounceVertical = true
        grid.contentInsetAdjustmentBehavior = .never
        grid.topEdgeEffect.style = .soft
        grid.topEdgeEffect.isHidden = false
        grid.accessibilityIdentifier = "profile.screen"
        grid.dataSource = self
        grid.delegate = self
        grid.register(ClipThumbnailCell.self, forCellWithReuseIdentifier: "clip")
        grid.register(ProfileHero.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                      withReuseIdentifier: "hero")
        grid.pin(to: view)
        if let profileID, store.active?.id == profileID {
            let button = UIBarButtonItem(primaryAction: UIAction(image: UIImage(systemName: "photo.on.rectangle")) { [weak self] _ in
                self?.editBanner(from: self?.navigationItem.leftBarButtonItem)
            })
            button.accessibilityLabel = "Змінити банер"
            navigationItem.leftItemsSupplementBackButton = true
            navigationItem.leftBarButtonItem = button
        }
        sectionIsland.translatesAutoresizingMaskIntoConstraints = true
        sectionIsland.onSelection = { [weak self] section in self?.select(section) }
        view.addSubview(sectionIsland)
        refresh()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateBackdropPosition()
        updateSectionPosition()
    }

    private func updateBackdropPosition() {
        guard let profile = visibleProfile else { return }
        let height = ProfileHero.coverSize(for: profile, width: view.bounds.width, top: view.safeAreaInsets.top) + 100
        let offset = grid.contentOffset.y
        backdropHeight.constant = max(0, height - offset)
        backdrop.setScroll(offset: offset, mediaHeight: height)
    }

    private func updateSectionPosition() {
        guard isViewLoaded, let profile = visibleProfile else {
            sectionIsland.isHidden = true
            return
        }
        sectionIsland.isHidden = false
        let headerHeight = ProfileHero.height(for: profile, width: view.bounds.width, top: view.safeAreaInsets.top,
                                              showsFollow: followState != nil)
        let naturalY = headerHeight - 50 - grid.contentOffset.y
        let pin = sectionPinTop ?? (navigationController == nil ? view.safeAreaInsets.top + 46 : view.safeAreaInsets.top + 2)
        let leading = max(view.safeAreaInsets.left, sectionInsets.leading)
        let trailing = max(view.safeAreaInsets.right, sectionInsets.trailing)
        sectionIsland.frame = CGRect(x: leading, y: max(pin, naturalY),
                                     width: max(0, view.bounds.width - leading - trailing), height: 44)
        view.bringSubviewToFront(sectionIsland)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if lastSize != view.bounds.size || lastSafeTop != view.safeAreaInsets.top {
            lastSafeTop = view.safeAreaInsets.top
            lastSize = view.bounds.size
            if let visibleProfile {
                hero?.setCover(for: visibleProfile, width: lastSize.width, top: lastSafeTop)
                updateBackdropPosition()
            }
            layout.invalidateLayout()
        }
        grid.contentInset.bottom = view.safeAreaInsets.bottom
        grid.verticalScrollIndicatorInsets = view.safeAreaInsets
        updateSectionPosition()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        visible = true
        backdrop.setPlaying(true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        visible = false
        backdrop.setPlaying(false)
    }

    func refresh() {
        guard isViewLoaded else { return }
        let profile = profileID.flatMap { store.profile($0) } ?? (profileID == nil ? store.active : nil)
        let resetScroll = visibleProfile?.id != profile?.id
        let changedBanner = visibleProfile?.bannerFile != profile?.bannerFile
        let changedAvatar = visibleProfile?.avatar != profile?.avatar
        visibleProfile = profile
        if resetScroll || changedBanner {
            backdrop.show(profile)
            backdrop.setPlaying(visible)
        }
        if resetScroll { selectedSection = .posts }
        updateBackdropPosition()
        backdrop.isHidden = profile == nil
        sectionIsland.select(selectedSection)
        updateSectionPosition()
        if let profile {
            guestView?.removeFromSuperview()
            guestView = nil
            grid.isHidden = false
            title = profileID == nil ? "Профіль" : "@\(profile.handle)"
            let newClips = posts(for: profile)
            let state: Bool? = store.active != nil && store.active?.id != profile.id ? store.follows(profile) : nil
            if resetScroll || changedBanner || changedAvatar || state != followState || clips.map(\.id) != newClips.map(\.id) {
                clips = newClips
                followState = state
                layout.invalidateLayout()
                grid.reloadData()
                if resetScroll { grid.setContentOffset(.zero, animated: false) }
            }
        } else {
            backdrop.setPlaying(false)
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

    private func posts(for profile: Profile) -> [Clip] {
        if selectedSection == .posts { return store.allClips.filter { $0.authorID == profile.id } }
        guard store.active?.id == profile.id else { return [] }
        switch selectedSection {
        case .posts: return []
        case .saved: return store.feed(.saved)
        case .liked: return store.allClips.filter { store.liked($0) }
        case .comments: return store.allClips.filter { clip in store.comments(clip).contains { $0.authorID == profile.id } }
        }
    }

    private func select(_ section: ProfileSection) {
        guard section != selectedSection, let profile = visibleProfile else { return }
        selectedSection = section
        clips = posts(for: profile)
        sectionIsland.select(section)
        grid.reloadSections(IndexSet(integer: 0))
        updateSectionPosition()
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView {
        let view = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "hero",
                                                                   for: indexPath) as! ProfileHero
        guard let profile = visibleProfile else { return view }
        let follow = followState
        view.setCover(for: profile, width: collectionView.bounds.width, top: self.view.safeAreaInsets.top)
        view.show(profile, hasPosts: !clips.isEmpty, following: follow, onAvatar: { [weak self] in self?.openAvatar() }) { [weak self] in
            guard let self else { return }
            self.store.toggleFollow(profile)
            self.showStorageErrorIfNeeded()
            self.refresh()
            self.onChange?()
        }
        return view
    }

    func editBanner(from button: UIBarButtonItem?) {
        guard let profile = store.active, profileID == nil || profile.id == profileID else { return }
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
            if let button {
                menu.popoverPresentationController?.barButtonItem = button
            } else {
                menu.popoverPresentationController?.sourceView = view
            }
            present(menu, animated: true)
        }
    }

    private func openBannerPicker(for id: UUID) {
        pickerOwner = id
        pickerDestination = .banner
        var configuration = PHPickerConfiguration()
        configuration.filter = .any(of: [.images, .videos])
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func openAvatar() {
        guard let profile = visibleProfile else { return }
        let menu = AvatarMenuController(data: profile.avatar, editable: store.active?.id == profile.id)
        menu.onChoose = { [weak self] in
            guard let self, self.store.active?.id == profile.id else { return }
            self.pickerOwner = profile.id
            self.pickerDestination = .avatar
            var configuration = PHPickerConfiguration()
            configuration.filter = .images
            configuration.preferredAssetRepresentationMode = .current
            let picker = PHPickerViewController(configuration: configuration)
            picker.delegate = self
            self.present(picker, animated: true)
        }
        let navigation = UINavigationController(rootViewController: menu)
        navigation.modalPresentationStyle = .fullScreen
        present(navigation, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        let owner = pickerOwner
        let destination = pickerDestination
        pickerOwner = nil
        picker.dismiss(animated: true) { [weak self] in
            guard let owner, let provider = results.first?.itemProvider else { return }
            self?.importMedia(provider, owner: owner, destination: destination)
        }
    }

    private func importMedia(_ provider: NSItemProvider, owner id: UUID, destination: PhotoDestination) {
        if destination == .banner, let format = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .movie) == true }) {
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
                        self?.showMessage("Не вдалося відкрити фотографію.")
                        return
                    }
                    let height = ProfileHero.bannerSize(width: self.view.bounds.width, top: self.view.safeAreaInsets.top) + 100
                    let shape: PhotoCropController.Shape = destination == .avatar ? .avatar : .banner(self.view.bounds.width / height)
                    let crop = PhotoCropController(image: image, shape: shape)
                    crop.onCrop = { [weak self] image in
                        guard let self, self.store.active?.id == id,
                              let data = image.jpegData(compressionQuality: 0.97) else { return }
                        if destination == .avatar {
                            if self.store.setAvatar(data, for: id) {
                                self.refresh()
                                self.onChange?()
                            } else { self.showStorageErrorIfNeeded() }
                        } else {
                            let temporary = FileManager.default.temporaryDirectory
                                .appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
                            defer { try? FileManager.default.removeItem(at: temporary) }
                            do {
                                try data.write(to: temporary, options: .atomic)
                                self.saveBanner(temporary, suffix: "jpg", owner: id)
                            } catch { self.showMessage("Не вдалося записати фото для банера.") }
                        }
                    }
                    let navigation = UINavigationController(rootViewController: crop)
                    navigation.modalPresentationStyle = .fullScreen
                    self.present(navigation, animated: true)
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
    private var coverHeight: NSLayoutConstraint!
    private static let avatarSide: CGFloat = 96
    private static let identityHeight: CGFloat = 64
    private static let margin: CGFloat = 20
    private static let gap: CGFloat = 14
    private static let verticalPadding: CGFloat = 16
    private static let followHeight: CGFloat = 44
    private static let footerHeight: CGFloat = 60

    private let banner = UIView()
    private let identity = UIStackView()
    private let followActions = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        banner.backgroundColor = .clear
        identity.alignment = .center
        identity.spacing = Self.gap
        followActions.axis = .vertical
        let details = UIStackView(arrangedSubviews: [identity, followActions])
        details.axis = .vertical
        details.spacing = Self.verticalPadding
        let insetDetails = UIView()
        details.pin(to: insetDetails, insets: .init(top: Self.verticalPadding, leading: Self.margin,
                                                   bottom: Self.verticalPadding + 16, trailing: Self.margin))

        let footerContainer = UIView()
        footerContainer.heightAnchor.constraint(equalToConstant: Self.footerHeight).isActive = true

        banner.isUserInteractionEnabled = false
        banner.translatesAutoresizingMaskIntoConstraints = false
        let contentStack = UIStackView(arrangedSubviews: [banner, insetDetails, footerContainer])
        contentStack.axis = .vertical
        contentStack.pin(to: self)
        coverHeight = banner.heightAnchor.constraint(equalToConstant: 0)
        coverHeight.isActive = true
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    static func coverSize(for profile: Profile, width: CGFloat, top: CGFloat) -> CGFloat {
        let navigationBottom = top + 50
        guard profile.bannerURL != nil else { return navigationBottom }
        return bannerSize(width: width, top: top)
    }

    static func bannerSize(width: CGFloat, top: CGFloat) -> CGFloat {
        max(top + 78, min(180, width * 0.40))
    }

    func setCover(for profile: Profile, width: CGFloat, top: CGFloat) {
        coverHeight.constant = Self.coverSize(for: profile, width: width, top: top)

    }

    static func height(for profile: Profile, width: CGFloat, top: CGFloat, showsFollow: Bool) -> CGFloat {
        let textWidth = max(1, width - 2 * margin - avatarSide - gap)
        let labels = makeDetails(profile)
        let measured = labels.systemLayoutSizeFitting(CGSize(width: textWidth, height: 0),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        let actionHeight = showsFollow ? followHeight + verticalPadding : 0
        return ceil(coverSize(for: profile, width: width, top: top) + max(identityHeight, measured) + 2 * verticalPadding + 16 + actionHeight + footerHeight)
    }

    func show(_ profile: Profile, hasPosts: Bool, following: Bool?, onAvatar: @escaping () -> Void, onFollow: @escaping () -> Void) {
        identity.arrangedSubviews.forEach { $0.removeFromSuperview() }
        followActions.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let avatar = avatarView(profile.avatar)
        avatar.layer.cornerRadius = Self.avatarSide / 2
        avatar.backgroundColor = .systemBackground
        avatar.widthAnchor.constraint(equalToConstant: Self.avatarSide).isActive = true
        avatar.heightAnchor.constraint(equalToConstant: Self.avatarSide).isActive = true
        let avatarContainer = UIButton(type: .custom)
        avatarContainer.accessibilityLabel = "Фото профілю"
        avatarContainer.addAction(UIAction { _ in onAvatar() }, for: .primaryActionTriggered)
        avatarContainer.translatesAutoresizingMaskIntoConstraints = false
        avatarContainer.addSubview(avatar)
        avatar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            avatarContainer.widthAnchor.constraint(equalToConstant: Self.avatarSide),
            avatarContainer.heightAnchor.constraint(equalToConstant: Self.identityHeight),
            avatar.centerXAnchor.constraint(equalTo: avatarContainer.centerXAnchor),
            avatar.centerYAnchor.constraint(equalTo: avatarContainer.centerYAnchor)
        ])
        identity.addArrangedSubview(avatarContainer)
        identity.addArrangedSubview(Self.makeDetails(profile))

        if let following {
            let button = textButton(following ? "Відписатися" : "Підписатися", prominent: !following, action: onFollow)
            button.heightAnchor.constraint(equalToConstant: Self.followHeight).isActive = true
            followActions.addArrangedSubview(button)
        }
        followActions.isHidden = following == nil



    }

    private static func makeDetails(_ profile: Profile) -> UIStackView {
        let name = makeLabel(.title2, text: profile.name)
        name.font = name.font.withTraits(.traitBold)
        let handle = makeLabel(.body, text: "@\(profile.handle)", color: .secondaryLabel)
        let details = UIStackView(arrangedSubviews: [name, handle])
        details.axis = .vertical
        details.spacing = 3
        name.textAlignment = .right
        handle.textAlignment = .right
        if !profile.bio.isEmpty {
            details.setCustomSpacing(7, after: handle)
            let bio = makeLabel(.subheadline, text: profile.bio, color: .secondaryLabel)
            bio.textAlignment = .right
            details.addArrangedSubview(bio)
        }
        return details
    }

}

private final class ProfileBackdrop: UIView {
    private let artwork = UIImageView()
    private let video = VideoSurface(frame: .zero)
    private let shade = GradientView()
    private var isVideo = false
    private var scrollOffset: CGFloat = 0
    private var mediaHeight: CGFloat = 260

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true
        artwork.contentMode = .scaleAspectFill
        artwork.clipsToBounds = true
        addSubview(artwork)
        addSubview(video)
        let background = UIColor.systemBackground.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        let alphas: [CGFloat] = [0, 0, 0.03, 0.10, 0.22, 0.38, 0.56, 0.73, 0.87, 0.96, 1]
        shade.gradient.colors = alphas.map { background.withAlphaComponent($0).cgColor }
        shade.gradient.locations = [0, 0.30, 0.40, 0.48, 0.56, 0.64, 0.72, 0.80, 0.88, 0.95, 1]
        addSubview(shade)
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    func setScroll(offset: CGFloat, mediaHeight: CGFloat) {
        scrollOffset = offset
        self.mediaHeight = mediaHeight
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let stretch = max(0, -scrollOffset)
        let height = mediaHeight + stretch
        artwork.frame = CGRect(x: 0, y: 0, width: bounds.width, height: height)
        video.frame = artwork.frame
        shade.frame = CGRect(x: 0, y: -max(0, scrollOffset), width: bounds.width, height: height)
    }

    func show(_ profile: Profile?) {
        let url = profile?.bannerURL
        isVideo = url.flatMap { UTType(filenameExtension: $0.pathExtension) }?.conforms(to: .movie) == true
        artwork.image = isVideo ? nil : url.flatMap { UIImage(contentsOfFile: $0.path) }
        video.isHidden = !isVideo
        video.load(isVideo ? url : nil)
    }

    func setPlaying(_ playing: Bool) { video.setPlaying(playing && isVideo, muted: true) }
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
        play.image = UIImage(systemName: clip.isPhoto ? "square.on.square" : "play.fill")
        guard let url = clip.coverURL else { return }
        if clip.isPhoto {
            task = Task { [weak self] in
                let poster = await PhotoLoader.image(url, maxPixel: 480)
                guard !Task.isCancelled, self?.representedID == clip.id else { return }
                self?.image.image = poster
            }
            return
        }
        task = Task { [weak self] in
            guard let poster = await VideoPoster.image(for: url), !Task.isCancelled,
                  let self, self.representedID == clip.id else { return }
            self.image.image = UIImage(cgImage: poster)
        }
    }
}
