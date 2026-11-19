import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Symbols

final class FeedController: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    enum Reaction { case like, bookmark }

    private let store: LocalStore
    private let pager = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .vertical)
    private let author = makeLabel(.headline)
    private let caption = makeLabel(.subheadline)
    private let like = GlyphButton(symbol: "heart", label: "Подобається", compact: true)
    private let comments = GlyphButton(symbol: "bubble", label: "Коментарі", compact: true)
    private let bookmark = GlyphButton(symbol: "bookmark", label: "Зберегти", compact: true)
    private let empty = EmptyStateView(title: "У підписках поки немає відео",
                                       message: "Підпишись на авторів, щоб бачити їхні публікації.",
                                       symbol: "person.2")
    private let reactionIsland = glassIsland(interactive: true)
    private let actionGlass = glassGroup()
    private let actionEdge = UIScrollEdgeElementContainerInteraction()
    private let sound = UIButton()
    private let authorAvatar = UIButton()
    private let actionStack = UIStackView()
    var edgeScrollView: UIScrollView? {
        guard let root = pager.viewIfLoaded else { return nil }
        var level = [root]
        while !level.isEmpty {
            if let scroll = level.compactMap({ $0 as? UIScrollView }).first { return scroll }
            level = level.flatMap(\.subviews)
        }
        return nil
    }
    private lazy var captionStack = UIStackView(arrangedSubviews: [author, caption])
    private var clips: [Clip] = []
    private weak var playingPage: VideoPage?
    private var page: VideoPage? { pager.viewControllers?.first as? VideoPage }
    private(set) var section = FeedSection.recommended

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
        pager.dataSource = self
        pager.delegate = self
        embed(pager, in: view)
        empty.pin(to: view)
        author.numberOfLines = 1
        caption.numberOfLines = 2
        captionStack.axis = .vertical
        captionStack.spacing = 3
        captionStack.isUserInteractionEnabled = false
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
        soundStyle.image = UIImage(systemName: "speaker.slash")
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

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let scroll = edgeScrollView
        if actionEdge.scrollView !== scroll { actionEdge.scrollView = scroll }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if !playbackEnabled { playingPage?.setPlaying(false, muted: muted) }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        syncPlayback()
    }

    func selectSection(_ section: FeedSection, preferredID: String? = nil) {
        let changed = self.section != section
        self.section = section
        guard isViewLoaded else { return }
        refresh(preferredID: preferredID, reset: changed)
    }

    func refresh(preferredID: String? = nil, reset: Bool = false) {
        guard isViewLoaded else { return }
        let current = page?.clip.id
        clips = store.feed(section)
        let target = preferredID ?? (reset ? nil : current)
        let next = clips.first { $0.id == target } ?? clips.first
        empty.isHidden = next != nil
        pager.view.isHidden = next == nil
        if let next, next.id != current || playingPage == nil {
            playingPage?.setPlaying(false, muted: muted)
            pager.setViewControllers([VideoPage(clip: next)], direction: .forward, animated: false)
        }
        updateCurrent()
    }

    private func updateCurrent() {
        let active = clips.isEmpty ? nil : page?.clip
        actionGlass.isHidden = active == nil || immersive
        captionStack.isHidden = active == nil || immersive
        empty.isHidden = active != nil || immersive
        page?.setImmersive(immersive)
        edgeScrollView?.topEdgeEffect.style = .soft
        edgeScrollView?.topEdgeEffect.isHidden = immersive
        edgeScrollView?.bottomEdgeEffect.style = .soft
        edgeScrollView?.bottomEdgeEffect.isHidden = immersive
        reactionIsland.isHidden = active == nil
        sound.isHidden = active == nil || active?.isPhoto == true
        if let active {
            author.text = store.profile(active.authorID).map { "@\($0.handle)" } ?? active.credit
            caption.text = [active.caption, active.settings.tags, active.settings.location].filter { !$0.isEmpty }.joined(separator: "\n")
            updateReactions()
        }
        refreshAuthorAvatar()
        syncPlayback()
    }

    private func updateSound() {
        var style = sound.configuration
        style?.image = UIImage(systemName: muted ? "speaker.slash" : "speaker.wave.2")
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
            style.image = UIImage(systemName: "person.crop.circle.fill",
                                  withConfiguration: UIImage.SymbolConfiguration(pointSize: 32))
        }
        authorAvatar.configuration = style
        authorAvatar.imageView?.layer.cornerRadius = 18
        authorAvatar.imageView?.clipsToBounds = true
        authorAvatar.isEnabled = profile != nil
        authorAvatar.accessibilityLabel = profile.map { "Відкрити профіль @\($0.handle)" } ?? "Автор демонстраційного відео"
    }

    func updateReactions(bounce: Reaction? = nil) {
        guard let clip = page?.clip else { return }
        comments.isHidden = !clip.settings.allowsComments
        let liked = store.liked(clip)
        let saved = store.bookmarked(clip)
        like.update(symbol: liked ? "heart.fill" : "heart", label: liked ? "Прибрати лайк" : "Подобається",
                    color: liked ? .kadrPeach : .label, count: store.likes(clip), animated: bounce == .like, selected: liked)
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

    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerBefore viewController: UIViewController) -> UIViewController? {
        adjacentPage(to: viewController, offset: -1)
    }

    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerAfter viewController: UIViewController) -> UIViewController? {
        adjacentPage(to: viewController, offset: 1)
    }

    private func adjacentPage(to controller: UIViewController, offset: Int) -> VideoPage? {
        guard let current = controller as? VideoPage,
              let index = clips.firstIndex(where: { $0.id == current.clip.id }),
              clips.indices.contains(index + offset) else { return nil }
        return VideoPage(clip: clips[index + offset])
    }

    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool,
                            previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        if completed {
            (previousViewControllers.first as? VideoPage)?.setPlaying(false, muted: muted)
            updateCurrent()
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

    init(clip: Clip) {
        self.clip = clip
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Use init(clip:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        if clip.isPhoto {
            let album = PhotoAlbumController(media: clip.media ?? [])
            self.album = album
            album.setImmersive(immersive)
            embed(album, in: view)
            return
        }
        video.pin(to: view)
        video.load(clip.url, adaptsLandscape: true)
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
    }

    func setImmersive(_ enabled: Bool) {
        immersive = enabled
        if enabled { playbackButton.hideAfterContextChange() }
        album?.setImmersive(enabled)
    }

    func setPlaying(_ enabled: Bool, muted: Bool) {
        loadViewIfNeeded()
        self.enabled = enabled
        if !enabled { playbackButton.hideAfterContextChange() }
        video.setPlaying(enabled && !paused, muted: muted)
    }

    private func setPaused(_ value: Bool) {
        paused = value
        playbackButton.isSelected = value
        tapArea.accessibilityLabel = value ? "Відтворити відео" : "Призупинити відео"
        video.setPlaying(enabled && !value)
        if !immersive { playbackButton.showForInteraction() }
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
    style.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 30, weight: .semibold))
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
        configuration?.image = UIImage(systemName: button.isSelected ? "play.fill" : "pause.fill",
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

    func load(_ url: URL?, adaptsLandscape: Bool = false) {
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
        looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(asset: asset))
        player = queue
        foreground.player = queue

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
            guard let self, self.revision == loadRevision, self.landscape,
                  let poster = await VideoPoster.image(for: url), !Task.isCancelled,
                  self.revision == loadRevision, self.backdrop.image == nil else { return }
            BackdropRenderer.render(CIImage(cgImage: poster)) { [weak self] image in
                guard let self, self.revision == loadRevision, self.landscape,
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
        if landscape { attachBackdrop(to: item) }
    }

    private func applyPresentationSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let wide = size.width > size.height
        let ratio = size.width / size.height
        guard wide != landscape || ratio != aspectRatio else { return }
        landscape = wide
        aspectRatio = ratio
        foreground.videoGravity = wide ? .resizeAspect : .resizeAspectFill
        backdrop.isHidden = !wide
        setNeedsLayout()
        if wide { startBackdrop() }
        else { stopBackdrop() }
    }

    func setPlaying(_ playing: Bool, muted: Bool? = nil) {
        self.playing = playing
        if let muted { player?.isMuted = muted }
        if playing { player?.play() }
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
        BackdropRenderer.render(source) { [weak self, weak item] image in
            guard let self else { return }
            self.renderingBackdrop = false
            guard request == self.revision, self.landscape, item === self.observedItem, let image else { return }
            self.backdrop.image = UIImage(cgImage: image)
        }
    }

    private func stopBackdrop() {
        backdropLink?.invalidate()
        backdropLink = nil
        attachBackdrop(to: nil)
    }

    deinit {
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

private enum BackdropRenderer {
    private static let queue = DispatchQueue(label: "kadr.video-backdrop", qos: .userInitiated)
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func render(_ source: CIImage, completion: @escaping @MainActor (CGImage?) -> Void) {
        queue.async {
            let factor = min(1, 192 / max(source.extent.width, source.extent.height))
            let scaled = source.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
            let filter = CIFilter.gaussianBlur()
            filter.inputImage = scaled.clampedToExtent()
            filter.radius = 16
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
        return cache
    }()

    static func image(for url: URL) async -> CGImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached.cgImage }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 640)
        var poster = try? await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600))
        if poster == nil { poster = try? await generator.image(at: .zero) }
        guard let result = poster else { return nil }
        cache.setObject(UIImage(cgImage: result.image), forKey: url as NSURL)
        return result.image
    }
}
