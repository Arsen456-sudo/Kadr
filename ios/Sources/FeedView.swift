import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Symbols

final class FeedController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    enum Reaction { case like, bookmark }

    private let store: LocalStore
    private let pagingLayout: UICollectionViewFlowLayout = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        return layout
    }()
    private lazy var pager = UICollectionView(frame: .zero, collectionViewLayout: pagingLayout)
    private var currentIndex = 0
    private var pages: [String: VideoPage] = [:]
    private var pageSize: CGSize = .zero
    private let author = makeLabel(.headline)
    private let caption = InlineCaptionView()
    private let like = GlyphButton(symbol: "heart", label: "Подобається", compact: true)
    private let comments = GlyphButton(symbol: "bubble", label: "Коментарі", compact: true)
    private let bookmark = GlyphButton(symbol: "bookmark", label: "Зберегти", compact: true)
    private let empty = EmptyStateView(title: "У підписках поки немає відео",
                                       message: "Підпишись на авторів, щоб бачити їхні публікації.",
                                       symbol: "person.2")
    private let reactionIsland = glassIsland(interactive: true)
    private let actionGlass = glassGroup()
    private let actionEdge = UIScrollEdgeElementContainerInteraction()
    private var contentScrollRegistered = false
    private var edgeEffectsHidden: Bool?
    private let sound = UIButton()
    private let authorAvatar = UIButton()
    private let actionStack = UIStackView()
    var edgeScrollView: UIScrollView? { isViewLoaded ? pager : nil }
    private lazy var captionStack = UIStackView(arrangedSubviews: [author, caption])
    private var clips: [Clip] = []
    private weak var playingPage: VideoPage?
    private var page: VideoPage? {
        guard clips.indices.contains(currentIndex) else { return nil }
        return pages[clips[currentIndex].id]
    }
    private(set) var section = FeedSection.recommended
    private var overview = false
    private var overviewMediaHeight: CGFloat {
        min(view.bounds.width * 1.25, max(140, view.bounds.height - view.safeAreaInsets.top - view.safeAreaInsets.bottom - 180))
    }
    private var itemSize: CGSize {
        CGSize(width: pager.bounds.width, height: overview ? overviewMediaHeight + OverviewMetrics.author + OverviewMetrics.actions + OverviewMetrics.caption : pager.bounds.height)
    }
    var onDescription: ((Clip) -> Void)?

    func setOverview(_ enabled: Bool) {
        guard overview != enabled else { return }
        rememberPosition()
        overview = enabled
        guard isViewLoaded else { return }
        playingPage?.setPlaying(false, muted: muted)
        for controller in pages.values { detach(controller) }
        pages.removeAll()
        let key = (overview ? "overview" : "feed") + (section == .following ? ".following" : ".recommended")
        if let id = store.studio.feedPositions[key], let index = clips.firstIndex(where: { $0.id == id }) { currentIndex = index }
        pager.isPagingEnabled = !enabled
        pager.contentInset = enabled ? .init(top: view.safeAreaInsets.top + 48, left: 0, bottom: view.safeAreaInsets.bottom, right: 0) : .zero
        pagingLayout.minimumLineSpacing = enabled ? 20 : 0
        pagingLayout.itemSize = itemSize
        pagingLayout.invalidateLayout()
        pager.reloadData()
        pager.layoutIfNeeded()
        if clips.indices.contains(currentIndex) {
            _ = controller(at: currentIndex)
            pager.scrollToItem(at: IndexPath(item: currentIndex, section: 0), at: .top, animated: false)
        }
        updateCurrent()
    }

    var onAuthor: ((UUID) -> Void)?
    var onReaction: ((Clip, Bool) -> Void)?
    var onComments: ((Clip) -> Void)?
    var immersive = false {
        didSet {
            guard isViewLoaded else { return }
            updateCurrent()
        }
    }
    var playbackEnabled = false { didSet { syncPlayback() } }
    var muted = true {
        didSet {
            if isViewLoaded { updateSound() }
            syncPlayback()
        }
    }

    init(store: LocalStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Use init(store:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        pager.backgroundColor = .clear
        pager.dataSource = self
        pager.delegate = self
        pager.isPagingEnabled = true
        pager.alwaysBounceVertical = true
        pager.showsVerticalScrollIndicator = false
        pager.contentInsetAdjustmentBehavior = .never
        pager.accessibilityIdentifier = "feed.pages"
        pager.register(FeedMediaCell.self, forCellWithReuseIdentifier: "page")
        pager.register(OverviewPostCell.self, forCellWithReuseIdentifier: "overview")
        pager.pin(to: view)
        NotificationCenter.default.addObserver(self, selector: #selector(contentSizeChanged), name: UIContentSizeCategory.didChangeNotification, object: nil)
        empty.pin(to: view)
        author.numberOfLines = 1
        captionStack.axis = .vertical
        captionStack.spacing = 3
        caption.onMore = { [weak self] in
            guard let self, let clip = self.page?.clip else { return }
            self.onDescription?(clip)
        }
        captionStack.isUserInteractionEnabled = true
        captionStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(captionStack)

        like.changesSelectionAsPrimaryAction = true
        bookmark.changesSelectionAsPrimaryAction = true
        like.addAction(UIAction { [weak self] _ in
            guard let self, let clip = self.page?.clip else { return }
            self.onReaction?(clip, false)
            self.like.isSelected = self.store.liked(clip)
        }, for: .primaryActionTriggered)
        comments.addAction(UIAction { [weak self] _ in
            guard let self, let clip = self.page?.clip else { return }
            self.onComments?(clip)
        }, for: .primaryActionTriggered)
        bookmark.addAction(UIAction { [weak self] _ in
            guard let self, let clip = self.page?.clip else { return }
            self.onReaction?(clip, true)
            self.bookmark.isSelected = self.store.bookmarked(clip)
        }, for: .primaryActionTriggered)

        let controls = UIStackView(arrangedSubviews: [like, comments, bookmark])
        controls.axis = .vertical
        controls.spacing = 4
        var soundStyle = UIButton.Configuration.glass()
        soundStyle.cornerStyle = .capsule
        soundStyle.image = AppSymbol.image( "speaker.slash")
        soundStyle.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        soundStyle.symbolContentTransition = UISymbolContentTransition(.replace)
        soundStyle.automaticallyUpdateForSelection = false
        soundStyle.baseForegroundColor = .label
        sound.configuration = soundStyle
        sound.tintColor = .label
        updateSound()
        sound.isPointerInteractionEnabled = true
        authorAvatar.isPointerInteractionEnabled = true
        sound.translatesAutoresizingMaskIntoConstraints = false
        authorAvatar.translatesAutoresizingMaskIntoConstraints = false
        authorAvatar.accessibilityIdentifier = "feed.author"
        authorAvatar.addAction(UIAction { [weak self] _ in
            guard let self, let id = self.page?.clip.authorID, self.store.profile(id) != nil else { return }
            self.onAuthor?(id)
        }, for: .primaryActionTriggered)
        actionStack.axis = .vertical
        actionStack.alignment = .center
        actionStack.spacing = 8
        for item in [authorAvatar, reactionIsland, sound] { actionStack.addArrangedSubview(item) }
        actionGlass.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(actionGlass)
        actionStack.pin(to: actionGlass.contentView)
        actionEdge.edge = .bottom
        actionEdge.scrollView = edgeScrollView
        actionGlass.addInteraction(actionEdge)
        NotificationCenter.default.addObserver(self, selector: #selector(profileDidChange(_:)),
                                               name: .kadrProfileDidChange, object: store)
        sound.accessibilityIdentifier = "feed.sound"
        like.accessibilityIdentifier = "feed.like"
        comments.accessibilityIdentifier = "feed.comments"
        bookmark.accessibilityIdentifier = "feed.bookmark"
        sound.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.muted.toggle()
        }, for: .primaryActionTriggered)
        controls.translatesAutoresizingMaskIntoConstraints = false
        reactionIsland.contentView.addSubview(controls)
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            controls.centerXAnchor.constraint(equalTo: reactionIsland.contentView.centerXAnchor),
            controls.centerYAnchor.constraint(equalTo: reactionIsland.contentView.centerYAnchor),
            reactionIsland.widthAnchor.constraint(equalTo: sound.widthAnchor),
            reactionIsland.heightAnchor.constraint(equalTo: controls.heightAnchor, constant: 8),
            sound.widthAnchor.constraint(equalToConstant: 48),
            sound.heightAnchor.constraint(equalTo: sound.widthAnchor),
            authorAvatar.widthAnchor.constraint(equalTo: sound.widthAnchor),
            authorAvatar.heightAnchor.constraint(equalTo: sound.heightAnchor),
            actionGlass.widthAnchor.constraint(equalTo: sound.widthAnchor),
            actionGlass.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),
            actionGlass.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -6),
            captionStack.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 18),
            captionStack.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -130),
            captionStack.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -14)
        ])
        refresh()
    }

    @objc private func contentSizeChanged() {
        pagingLayout.invalidateLayout(); pager.reloadData()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let size = pager.bounds.size
        if size.width > 0, size.height > 0, size != pageSize {
            pageSize = size
            pagingLayout.itemSize = itemSize
            pagingLayout.invalidateLayout()
            pager.layoutIfNeeded()
            if overview {
                pager.contentInset = .init(top: view.safeAreaInsets.top + 48, left: 0, bottom: view.safeAreaInsets.bottom, right: 0)
                if clips.indices.contains(currentIndex) { pager.scrollToItem(at: IndexPath(item: currentIndex, section: 0), at: .top, animated: false) }
            } else {
                pager.setContentOffset(CGPoint(x: 0, y: CGFloat(currentIndex) * size.height), animated: false)
            }
        }
        connectContentScrollView()
    }

    private func connectContentScrollView() {
        guard let scroll = edgeScrollView else { return }
        // This is the feed's own public scroll view, shared by photo and video cells.
        if !contentScrollRegistered {
            contentScrollRegistered = true
            setContentScrollView(scroll, for: .all)
        }
        if edgeEffectsHidden != immersive {
            edgeEffectsHidden = immersive
            scroll.topEdgeEffect.style = .soft
            scroll.bottomEdgeEffect.style = .soft
            scroll.topEdgeEffect.isHidden = immersive
            scroll.bottomEdgeEffect.isHidden = immersive
        }
        if actionEdge.scrollView !== scroll { actionEdge.scrollView = scroll }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if !playbackEnabled { playingPage?.setPlaying(false, muted: muted) }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        muted = !store.studio.preferences.autoSound
        syncPlayback()
    }

    func selectSection(_ section: FeedSection, preferredID: String? = nil) {
        let changed = self.section != section
        if changed { rememberPosition() }
        self.section = section
        guard isViewLoaded else { return }
        refresh(preferredID: preferredID, reset: changed)
    }

    func refresh(preferredID: String? = nil, reset: Bool = false) {
        guard isViewLoaded else { return }
        let current = page?.clip.id
        let updated = store.feed(section)
        let key = (overview ? "overview" : "feed") + (section == .following ? ".following" : ".recommended")
        let target = preferredID ?? (reset ? store.studio.feedPositions[key] : current)
        let nextIndex = updated.firstIndex { $0.id == target } ?? 0
        let changed = clips != updated
        if changed {
            playingPage?.setPlaying(false, muted: muted)
            for controller in pages.values { detach(controller) }
            pages.removeAll()
            clips = updated
        }
        currentIndex = nextIndex
        empty.isHidden = !clips.isEmpty
        pager.isHidden = clips.isEmpty
        if changed { pager.reloadData() }
        if clips.indices.contains(currentIndex) {
            _ = controller(at: currentIndex)
            pager.layoutIfNeeded()
            if (changed || reset || preferredID != nil), pager.bounds.height > 0, !pager.isDragging, !pager.isDecelerating {
                if overview { pager.scrollToItem(at: IndexPath(item: currentIndex, section: 0), at: .top, animated: false) }
                else { pager.setContentOffset(CGPoint(x: 0, y: CGFloat(currentIndex) * pager.bounds.height), animated: false) }
            }
        }
        updateCurrent()
    }

    private func updateCurrent() {
        let active = clips.isEmpty ? nil : page?.clip
        actionGlass.isHidden = active == nil || immersive || overview
        captionStack.isHidden = active == nil || immersive || overview
        empty.isHidden = active != nil || immersive
        page?.setImmersive(immersive)
        connectContentScrollView()
        reactionIsland.isHidden = active == nil
        sound.isHidden = active == nil || active?.isPhoto == true
        if let active {
            author.text = store.profile(active.authorID).map { "@\($0.handle)" } ?? active.credit
            caption.show(active.caption)
            updateReactions()
        }
        refreshAuthorAvatar()
        syncPlayback()
    }

    private func updateSound() {
        var style = sound.configuration
        style?.image = AppSymbol.image( muted ? "speaker.slash" : "speaker.wave.2")
        style?.symbolContentTransition = UIAccessibility.isReduceMotionEnabled ? nil : UISymbolContentTransition(.replace)
        style?.baseForegroundColor = .label
        sound.configuration = style
        sound.accessibilityLabel = muted ? "Увімкнути звук" : "Вимкнути звук"
        sound.accessibilityValue = muted ? "Звук вимкнено" : "Звук увімкнено"
    }

    @objc private func profileDidChange(_ notification: Notification) {
        guard let id = notification.userInfo?["profileID"] as? UUID, page?.clip.authorID == id else { return }
        refreshAuthorAvatar()
    }

    private func refreshAuthorAvatar() {
        let profile = store.profile(page?.clip.authorID)
        var style = UIButton.Configuration.glass()
        style.cornerStyle = .capsule
        style.contentInsets = .init(top: 6, leading: 6, bottom: 6, trailing: 6)
        if let image = profile?.avatar.flatMap({ UIImage(data: $0) }) {
            let thumbnail = UIGraphicsImageRenderer(size: CGSize(width: 36, height: 36)).image { _ in
                image.draw(in: CGRect(x: 0, y: 0, width: 36, height: 36))
            }
            style.image = thumbnail.withRenderingMode(.alwaysOriginal)
        } else {
            style.image = AppSymbol.image( "person.crop.circle.fill",
                                  withConfiguration: UIImage.SymbolConfiguration(pointSize: 32))
        }
        authorAvatar.configuration = style
        authorAvatar.imageView?.layer.cornerRadius = 18
        authorAvatar.imageView?.clipsToBounds = true
        authorAvatar.isEnabled = profile != nil
        authorAvatar.accessibilityLabel = profile.map { "Відкрити профіль @\($0.handle)" } ?? "Автор демонстраційного відео"
    }

    func updateReactions(bounce: Reaction? = nil) {
        if overview {
            for indexPath in pager.indexPathsForVisibleItems {
                if let cell = pager.cellForItem(at: indexPath) as? OverviewPostCell, clips.indices.contains(indexPath.item) {
                    cell.show(clips[indexPath.item], store: store, mediaHeight: overviewMediaHeight, muted: muted)
                }
            }
        }
        guard let clip = page?.clip else { return }
        comments.isHidden = !clip.settings.allowsComments
        let liked = store.liked(clip)
        let saved = store.bookmarked(clip)
        like.update(symbol: liked ? "heart.fill" : "heart", label: liked ? "Прибрати лайк" : "Подобається",
                    color: liked ? .kadrPeach : .label, count: clip.extras?.hideLikes == true ? nil : store.likes(clip), animated: bounce == .like, selected: liked)
        comments.update(symbol: "bubble", label: "Коментарі", count: store.comments(clip).count, animated: false)
        bookmark.update(symbol: saved ? "bookmark.fill" : "bookmark", label: saved ? "Прибрати зі збереженого" : "Зберегти",
                        color: saved ? .kadrPeach : .label, animated: bounce == .bookmark, selected: saved)
        if bounce == .like && liked { like.bounce() }
        if bounce == .bookmark && saved { bookmark.bounce() }
    }

    private func syncPlayback() {
        guard isViewLoaded else { return }
        let current = clips.isEmpty ? nil : page
        if current !== playingPage { playingPage?.setPlaying(false, muted: muted) }
        playingPage = current
        current?.setPlaying(playbackEnabled && view.window != nil, muted: muted)
    }

    private func controller(at index: Int) -> VideoPage {
        let clip = clips[index]
        if let existing = pages[clip.id] { return existing }
        let controller = VideoPage(clip: clip, fitsAllMedia: overview, store: store)
        pages[clip.id] = controller
        return controller
    }

    private func detach(_ controller: VideoPage) {
        controller.setPlaying(false, muted: muted)
        guard controller.parent != nil else { return }
        controller.willMove(toParent: nil)
        controller.view.removeFromSuperview()
        controller.removeFromParent()
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        clips.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: overview ? "overview" : "page", for: indexPath) as! FeedMediaCell
        cell.representedID = clips[indexPath.item].id
        cell.onRelease = { [weak self] cell in self?.releaseMedia(in: cell) }
        if let overviewCell = cell as? OverviewPostCell {
            let clip = clips[indexPath.item]
            overviewCell.show(clip, store: store, mediaHeight: overviewMediaHeight, muted: muted)
            overviewCell.onAuthor = { [weak self] in if let id = clip.authorID { self?.onAuthor?(id) } }
            overviewCell.onLike = { [weak self] in self?.onReaction?(clip, false) }
            overviewCell.onBookmark = { [weak self] in self?.onReaction?(clip, true) }
            overviewCell.onComments = { [weak self] in self?.onComments?(clip) }
            overviewCell.onDescription = { [weak self] in self?.onDescription?(clip) }
            overviewCell.onSound = { [weak self] in
                guard let self else { return }
                self.muted.toggle()
                self.updateReactions()
            }
        }
        mountMedia(in: cell, at: indexPath)
        return cell
    }

    private func mountMedia(in cell: FeedMediaCell, at indexPath: IndexPath) {
        guard clips.indices.contains(indexPath.item) else { return }
        let controller = controller(at: indexPath.item)
        let target = cell.mediaHost
        cell.representedID = clips[indexPath.item].id
        cell.onRelease = { [weak self] cell in self?.releaseMedia(in: cell) }
        if controller.viewIfLoaded?.superview !== target {
            for child in target.subviews { child.removeFromSuperview() }
            let added = controller.parent == nil
            if added { addChild(controller) }
            let content = controller.view!
            content.translatesAutoresizingMaskIntoConstraints = true
            content.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            content.frame = target.bounds
            target.addSubview(content)
            if added { controller.didMove(toParent: self) }
        }
        controller.setImmersive(immersive)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        guard overview, clips.indices.contains(indexPath.item) else { return pager.bounds.size }
        let hasDescription = !clips[indexPath.item].caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return CGSize(width: collectionView.bounds.width, height: overviewMediaHeight + OverviewMetrics.author + OverviewMetrics.actions + (hasDescription ? OverviewMetrics.caption : 0))
    }

    private func releaseMedia(in cell: FeedMediaCell) {
        guard let id = cell.representedID, let controller = pages[id],
              controller.viewIfLoaded?.superview === cell.mediaHost else { return }
        detach(controller)
        pages.removeValue(forKey: id)
        if playingPage === controller { playingPage = nil }
    }

    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell,
                        forItemAt indexPath: IndexPath) {
        if let cell = cell as? FeedMediaCell { releaseMedia(in: cell) }
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell,
                        forItemAt indexPath: IndexPath) {
        if let cell = cell as? FeedMediaCell { mountMedia(in: cell, at: indexPath) }
        if indexPath.item == currentIndex { syncPlayback() }
    }

    private static var lastVisibilityCheck: CFTimeInterval = 0
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard overview, CACurrentMediaTime() - Self.lastVisibilityCheck > 0.12 else { return }
        Self.lastVisibilityCheck = CACurrentMediaTime()
        let viewport = CGRect(origin: pager.contentOffset, size: pager.bounds.size)
        let visible = pager.indexPathsForVisibleItems
        if let best = visible.max(by: {
            (pager.layoutAttributesForItem(at: $0)?.frame.intersection(viewport).height ?? 0) < (pager.layoutAttributesForItem(at: $1)?.frame.intersection(viewport).height ?? 0)
        }), best.item != currentIndex {
            currentIndex = best.item; _ = controller(at: currentIndex); updateCurrent()
        }
    }
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { finishPaging() }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { finishPaging() }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { finishPaging() }
    }

    private func rememberPosition() {
        guard clips.indices.contains(currentIndex) else { return }
        let id = clips[currentIndex].id
        let key = (overview ? "overview" : "feed") + (section == .following ? ".following" : ".recommended")
        store.changeStudio { $0.feedPositions[key] = id }
    }
    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard clips.indices.contains(indexPath.item) else { return nil }
        let clip = clips[indexPath.item]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            return self.postMenu(clip, store: self.store, onChange: { [weak self] in self?.refresh() }, previous: { [weak self] in
                guard let self, self.currentIndex > 0 else { return }; self.currentIndex -= 1
                _ = self.controller(at: self.currentIndex)
                self.pager.scrollToItem(at: IndexPath(item: self.currentIndex, section: 0), at: .top, animated: !UIAccessibility.isReduceMotionEnabled)
                self.updateCurrent()
            })
        }
    }
    private func finishPaging() {
        guard !clips.isEmpty, pager.bounds.height > 0 else { return }
        if overview {
            let center = pager.contentOffset.y + pager.bounds.height / 2
            if let nearest = pager.indexPathsForVisibleItems.min(by: {
                abs((pager.layoutAttributesForItem(at: $0)?.frame.midY ?? 0) - center) < abs((pager.layoutAttributesForItem(at: $1)?.frame.midY ?? 0) - center)
            }) { currentIndex = nearest.item }
        } else {
            currentIndex = min(clips.count - 1, max(0, Int((pager.contentOffset.y / pager.bounds.height).rounded())))
        }
        _ = controller(at: currentIndex)
        rememberPosition()
        updateCurrent()
        // Keep only the current page and its neighbours, so long feeds do not retain players.
        let retained = Set(clips.indices.filter { abs($0 - currentIndex) <= 1 }.map { clips[$0].id })
            .union(pager.indexPathsForVisibleItems.compactMap { clips.indices.contains($0.item) ? clips[$0.item].id : nil })
        for id in Array(pages.keys) where !retained.contains(id) {
            if let controller = pages.removeValue(forKey: id) { detach(controller) }
        }
    }
}

private final class VideoPage: UIViewController {
    let clip: Clip
    private let video = VideoSurface(frame: .zero)
    private let playbackButton = makePlaybackButton(symbol: "pause.fill", label: "Призупинити")
    private let tapArea = UIButton(type: .custom)
    private var enabled = false
    private var paused = false
    private var immersive = false
    private var album: PhotoAlbumController?
    private let fitsAllMedia: Bool
    private let store: LocalStore
    private let timeline = UISlider()
    private var controlsTask: Task<Void, Never>?

    init(clip: Clip, fitsAllMedia: Bool = false, store: LocalStore) {
        self.store = store
        self.clip = clip
        self.fitsAllMedia = fitsAllMedia
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Use init(clip:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        if clip.isPhoto {
            let album = PhotoAlbumController(media: clip.media ?? [], compact: fitsAllMedia, extras: clip.extras ?? PostExtras())
            self.album = album
            album.setImmersive(immersive)
            embed(album, in: view)
            return
        }
        video.pin(to: view)
        video.load(clip.url, adaptsLandscape: true, fitsAllMedia: fitsAllMedia, extras: clip.extras)
        if let watch = store.studio.watches[clip.id], !watch.completed { video.seek(to: watch.seconds) }
        tapArea.accessibilityIdentifier = "video.playbackArea"
        tapArea.isAccessibilityElement = true
        tapArea.accessibilityTraits = .button
        tapArea.accessibilityLabel = "Призупинити відео"
        tapArea.pin(to: view)
        tapArea.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.setPaused(!self.paused)
        }, for: .primaryActionTriggered)
        playbackButton.hideAfterContextChange()
        playbackButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.setPaused(self.playbackButton.isSelected)
        }, for: .primaryActionTriggered)
        view.addSubview(playbackButton)
        NSLayoutConstraint.activate([
            playbackButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            playbackButton.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        // Install after the full-surface tap button so it remains touchable.
        installTimeline()
    }

    private func installTimeline() {
        timeline.translatesAutoresizingMaskIntoConstraints = false; timeline.isHidden = true
        timeline.isContinuous = false; timeline.accessibilityLabel = "Позиція відтворення"
        view.addSubview(timeline)
        NSLayoutConstraint.activate([timeline.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18), timeline.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18), timeline.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -4)])
        timeline.addAction(UIAction { [weak self] _ in
            guard let self else { return }; self.video.seek(to: Double(self.timeline.value)); self.showControls()
        }, for: .valueChanged)
        video.onProgress = { [weak self] seconds, duration in
            guard let self, !self.timeline.isHidden, !self.timeline.isTracking else { return }
            self.timeline.maximumValue = Float(max(1, duration)); self.timeline.setValue(Float(seconds), animated: !UIAccessibility.isReduceMotionEnabled)
            self.timeline.accessibilityValue = "\(Int(seconds)) з \(Int(duration)) секунд"
        }
        let single = UITapGestureRecognizer(target: self, action: #selector(surfaceTapped))
        let double = UITapGestureRecognizer(target: self, action: #selector(seekDoubleTapped(_:))); double.numberOfTapsRequired = 2
        single.require(toFail: double); tapArea.addGestureRecognizer(single); tapArea.addGestureRecognizer(double)
    }
    @objc private func surfaceTapped() { setPaused(!paused) }
    @objc private func seekDoubleTapped(_ gesture: UITapGestureRecognizer) {
        let seconds = video.progress.seconds + (gesture.location(in: tapArea).x < tapArea.bounds.midX ? -10 : 10)
        video.seek(to: max(0, seconds)); showControls()
    }
    private func showControls() {
        guard !immersive else { return }
        playbackButton.showForInteraction(); timeline.isHidden = false
        controlsTask?.cancel()
        controlsTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            self?.timeline.isHidden = true
        }
    }

    func setImmersive(_ enabled: Bool) {
        immersive = enabled
        if enabled { playbackButton.hideAfterContextChange(); timeline.isHidden = true; controlsTask?.cancel() }
        album?.setImmersive(enabled)
    }

    func setPlaying(_ enabled: Bool, muted: Bool) {
        guard enabled || isViewLoaded else { self.enabled = false; return }
        loadViewIfNeeded()
        if self.enabled && !enabled {
            let progress = video.progress
            store.recordWatch(clip, seconds: clip.isPhoto ? 1 : progress.seconds, duration: clip.isPhoto ? 1 : progress.duration)
        }
        self.enabled = enabled
        video.preferredRate = store.studio.preferences.playbackRate
        if !enabled { playbackButton.hideAfterContextChange(); timeline.isHidden = true; controlsTask?.cancel() }
        video.setPlaying(enabled && !paused, muted: muted)
    }

    private func setPaused(_ value: Bool) {
        paused = value
        playbackButton.isSelected = value
        tapArea.accessibilityLabel = value ? "Відтворити відео" : "Призупинити відео"
        video.setPlaying(enabled && !value)
        if !immersive { showControls() }
    }
}

final class PlaybackButton: UIButton {
    private var hideTask: Task<Void, Never>?

    func showForInteraction() {
        hideTask?.cancel()
        isHidden = false
        hideTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) }
            catch { return }
            guard !Task.isCancelled else { return }
            self?.isHidden = true
        }
    }

    func hideAfterContextChange() {
        hideTask?.cancel()
        hideTask = nil
        isHidden = true
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { hideAfterContextChange() }
    }

    deinit { hideTask?.cancel() }
}

func makePlaybackButton(symbol: String, label: String) -> PlaybackButton {
    var style = UIButton.Configuration.glass()
    style.cornerStyle = .capsule
    style.symbolContentTransition = UIAccessibility.isReduceMotionEnabled ? nil : UISymbolContentTransition(.replace)
    style.image = AppSymbol.image( symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 30, weight: .semibold))
    style.baseForegroundColor = .label
    style.baseBackgroundColor = .clear
    style.automaticallyUpdateForSelection = false
    let button = PlaybackButton(configuration: style)
    button.changesSelectionAsPrimaryAction = true
    button.isSelected = symbol == "play.fill"
    button.isPointerInteractionEnabled = true
    button.configurationUpdateHandler = { button in
        var configuration = button.configuration
        configuration?.baseForegroundColor = .label
        configuration?.baseBackgroundColor = .clear
        configuration?.image = AppSymbol.image( button.isSelected ? "play.fill" : "pause.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 30, weight: .semibold))
        configuration?.symbolContentTransition = UIAccessibility.isReduceMotionEnabled ? nil : UISymbolContentTransition(.replace)
        button.configuration = configuration
        button.accessibilityLabel = button.isSelected ? "Відтворити" : "Призупинити"
    }
    button.accessibilityLabel = label
    button.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
        button.widthAnchor.constraint(equalToConstant: 72),
        button.heightAnchor.constraint(equalTo: button.widthAnchor)
    ])
    return button
}

final class VideoSurface: UIView {
    private let foreground = AVPlayerLayer()
    private let backdrop = UIImageView()
    private var player: AVQueuePlayer?
    private var trimStart: Double = 0
    private var trimEnd: Double?
    var preferredRate: Float = 1 { didSet { if playing { player?.rate = preferredRate } } }
    var onProgress: ((Double, Double) -> Void)?
    private var progressObserver: Any?
    var progress: (seconds: Double, duration: Double) {
        let seconds = player?.currentTime().seconds ?? 0, duration = player?.currentItem?.duration.seconds ?? 0
        let end = trimEnd ?? duration
        return (seconds.isFinite ? max(0, seconds - trimStart) : 0, end.isFinite ? max(0, end - trimStart) : 0)
    }
    func seek(to seconds: Double) {
        guard seconds.isFinite, seconds >= 0 else { return }
        player?.seek(to: CMTime(seconds: min(seconds + trimStart, trimEnd ?? .greatestFiniteMagnitude), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }
    private var looper: AVPlayerLooper?
    private var backdropLink: CADisplayLink?
    private var renderingBackdrop = false
    private var playing = false
    private var frameOutput: AVPlayerItemVideoOutput?
    private weak var observedItem: AVPlayerItem?
    private var metadata: Task<Void, Never>?
    private var itemObservation: NSKeyValueObservation?
    private var sizeObservation: NSKeyValueObservation?
    private var revision = 0
    private var landscape = false
    private var fitsAllMedia = false
    private var usesBackdrop: Bool { landscape || fitsAllMedia }
    private var aspectRatio: CGFloat = 1
    private var frameTransform: CGAffineTransform = .identity

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true
        backdrop.contentMode = .scaleAspectFill
        backdrop.clipsToBounds = true
        backdrop.isHidden = true
        addSubview(backdrop)
        layer.addSublayer(foreground)
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    override func layoutSubviews() {
        super.layoutSubviews()
        backdrop.frame = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if landscape {
            let width = min(bounds.width, bounds.height * aspectRatio)
            let height = width / aspectRatio
            foreground.frame = CGRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2,
                                      width: width, height: height)
        } else {
            foreground.frame = bounds
        }
        CATransaction.commit()
    }

    func load(_ url: URL?, adaptsLandscape: Bool = false, fitsAllMedia: Bool = false, extras: PostExtras? = nil) {
        if let progressObserver { player?.removeTimeObserver(progressObserver); self.progressObserver = nil }
        self.fitsAllMedia = fitsAllMedia
        trimStart = extras?.trimStart ?? 0; trimEnd = extras?.trimEnd
        revision += 1
        let loadRevision = revision
        metadata?.cancel()
        itemObservation = nil
        sizeObservation = nil
        stopBackdrop()
        playing = false
        player?.pause()
        looper?.disableLooping()
        looper = nil
        player = nil
        foreground.player = nil
        foreground.videoGravity = adaptsLandscape ? .resizeAspect : .resizeAspectFill
        backdrop.isHidden = true
        backdrop.image = nil
        landscape = false
        aspectRatio = 0
        frameTransform = .identity
        setNeedsLayout()
        guard let url else { return }
        let asset = AVURLAsset(url: url)
        let queue = AVQueuePlayer()
        queue.isMuted = true
        let range: CMTimeRange
        if let end = extras?.trimEnd, end.isFinite, let start = extras?.trimStart, start.isFinite, end > start {
            range = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), duration: CMTime(seconds: end - start, preferredTimescale: 600))
        } else { range = .invalid }
        looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(asset: asset), timeRange: range)
        player = queue
        foreground.player = queue
        progressObserver = queue.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] _ in
            guard let self else { return }; let progress = self.progress
            self.onProgress?(progress.seconds, progress.duration)
        }

        guard adaptsLandscape else { return }
        itemObservation = queue.observe(\.currentItem, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self, self.revision == loadRevision else { return }
                self.observePresentationSize(player.currentItem, revision: loadRevision)
            }
        }
        metadata = Task { [weak self] in
            if let track = try? await asset.loadTracks(withMediaType: .video).first,
               let size = try? await track.load(.naturalSize),
               let transform = try? await track.load(.preferredTransform),
               !Task.isCancelled, let self, self.revision == loadRevision {
                self.frameTransform = transform
                let presented = queue.currentItem?.presentationSize ?? .zero
                if presented.width > 0, presented.height > 0 {
                    self.applyPresentationSize(presented)
                } else {
                    self.applyPresentationSize(CGRect(origin: .zero, size: size).applying(transform).standardized.size)
                }
            }
            guard let self, self.revision == loadRevision, self.usesBackdrop,
                  let poster = await VideoPoster.image(for: url), !Task.isCancelled,
                  self.revision == loadRevision, self.backdrop.image == nil else { return }
            MediaBackdropRenderer.render(CIImage(cgImage: poster)) { [weak self] image in
                guard let self, self.revision == loadRevision, self.usesBackdrop,
                      self.backdrop.image == nil, let image else { return }
                self.backdrop.image = UIImage(cgImage: image)
            }
        }
    }

    private func observePresentationSize(_ item: AVPlayerItem?, revision: Int) {
        sizeObservation = item?.observe(\.presentationSize, options: [.initial, .new]) { [weak self] item, _ in
            let size = item.presentationSize
            Task { @MainActor [weak self] in
                guard let self, self.revision == revision, self.player?.currentItem === item else { return }
                self.applyPresentationSize(size)
            }
        }
        if usesBackdrop { attachBackdrop(to: item) }
    }

    private func applyPresentationSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let wide = size.width > size.height
        let ratio = size.width / size.height
        guard wide != landscape || ratio != aspectRatio else { return }
        landscape = wide
        aspectRatio = ratio
        foreground.videoGravity = wide || fitsAllMedia ? .resizeAspect : .resizeAspectFill
        backdrop.isHidden = !usesBackdrop
        setNeedsLayout()
        if usesBackdrop { startBackdrop() }
        else { stopBackdrop() }
    }

    func setPlaying(_ playing: Bool, muted: Bool? = nil) {
        if let muted, player?.isMuted != muted { player?.isMuted = muted }
        guard self.playing != playing else { updateBackdropClock(); return }
        self.playing = playing
        if playing { player?.playImmediately(atRate: preferredRate) }
        else { player?.pause() }
        updateBackdropClock()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateBackdropClock()
    }

    private func startBackdrop() {
        guard backdropLink == nil else { return }
        attachBackdrop(to: player?.currentItem)
        let target = BackdropClock(surface: self)
        let link = CADisplayLink(target: target, selector: #selector(BackdropClock.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        backdropLink = link
        link.add(to: .main, forMode: .common)
        updateBackdropClock()
    }

    private func updateBackdropClock() {
        backdropLink?.isPaused = !playing || window == nil
    }

    private func attachBackdrop(to item: AVPlayerItem?) {
        guard item !== observedItem else { return }
        if let frameOutput { observedItem?.remove(frameOutput) }
        frameOutput = nil
        observedItem = item
        if let item {
            let output = AVPlayerItemVideoOutput(pixelBufferAttributes: nil)
            item.add(output)
            frameOutput = output
        }
    }

    fileprivate func updateBackdrop(at hostTime: CFTimeInterval) {
        guard !renderingBackdrop, let frameOutput, let item = observedItem,
              item === player?.currentItem else { return }
        let time = frameOutput.itemTime(forHostTime: hostTime)
        guard frameOutput.hasNewPixelBuffer(forItemTime: time),
              let frame = frameOutput.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else { return }
        renderingBackdrop = true
        let request = revision
        let source = CIImage(cvPixelBuffer: frame).transformed(by: frameTransform)
        MediaBackdropRenderer.render(source) { [weak self, weak item] image in
            guard let self else { return }
            self.renderingBackdrop = false
            guard request == self.revision, self.usesBackdrop, item === self.observedItem, let image else { return }
            self.backdrop.image = UIImage(cgImage: image)
        }
    }

    private func stopBackdrop() {
        backdropLink?.invalidate()
        backdropLink = nil
        attachBackdrop(to: nil)
    }

    deinit {
        if let progressObserver { player?.removeTimeObserver(progressObserver) }
        metadata?.cancel()
        backdropLink?.invalidate()
    }
}

@MainActor
private final class BackdropClock: NSObject {
    private weak var surface: VideoSurface?

    init(surface: VideoSurface) { self.surface = surface }

    @objc func tick(_ link: CADisplayLink) {
        surface?.updateBackdrop(at: link.targetTimestamp)
    }
}

enum MediaBackdropRenderer {
    private static let queue = DispatchQueue(label: "kadr.video-backdrop", qos: .userInitiated)
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func render(_ source: CIImage, completion: @escaping @MainActor (CGImage?) -> Void) {
        queue.async {
            let factor = min(1, 192 / max(source.extent.width, source.extent.height))
            let scaled = source.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
            let filter = CIFilter.gaussianBlur()
            filter.inputImage = scaled.clampedToExtent()
            filter.radius = 13
            let image = filter.outputImage.flatMap { context.createCGImage($0, from: scaled.extent) }
            DispatchQueue.main.async { completion(image) }
        }
    }
}

@MainActor
enum VideoPoster {
    private static let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 96
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()

    static func clearCache() { cache.removeAllObjects() }
    private static var requests: [URL: Task<CGImage?, Never>] = [:]

    static func image(for url: URL, at seconds: Double = 0.5) async -> CGImage? {
        let key = URL(string: url.absoluteString + "#frame=" + String(seconds)) ?? url
        if let cached = cache.object(forKey: key as NSURL) { return cached.cgImage }
        if let request = requests[key] { return await request.value }
        let request = Task { await generate(for: url, at: seconds, key: key) }
        requests[key] = request
        defer { requests.removeValue(forKey: key) }
        return await request.value
    }

    private static func generate(for url: URL, at seconds: Double, key: URL) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 640)
        var poster = try? await generator.image(at: CMTime(seconds: max(0, seconds), preferredTimescale: 600))
        if poster == nil { poster = try? await generator.image(at: .zero) }
        guard let result = poster else { return nil }
        cache.setObject(UIImage(cgImage: result.image), forKey: key as NSURL,
                        cost: result.image.width * result.image.height * 4)
        return result.image
    }
}
