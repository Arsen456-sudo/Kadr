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
    private let reactionIsland = glassIsland()
    private let sound = GlyphButton(symbol: "speaker.slash", label: "Увімкнути звук")
    var edgeScrollView: UIScrollView? {
        pager.viewIfLoaded?.subviews.compactMap { $0 as? UIScrollView }.first
    }
    private lazy var captionStack = UIStackView(arrangedSubviews: [author, caption])
    private var clips: [Clip] = []
    private weak var playingPage: VideoPage?
    private var page: VideoPage? { pager.viewControllers?.first as? VideoPage }
    private(set) var section = FeedSection.recommended

    var onReaction: ((Clip, Bool) -> Void)?
    var onComments: ((Clip) -> Void)?
    var playbackEnabled = false { didSet { syncPlayback() } }
    var muted = true { didSet { syncPlayback() } }

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

        like.addAction(UIAction { [weak self] _ in
            guard let self, let clip = self.page?.clip else { return }
            self.onReaction?(clip, false)
        }, for: .primaryActionTriggered)
        comments.addAction(UIAction { [weak self] _ in
            guard let self, let clip = self.page?.clip else { return }
            self.onComments?(clip)
        }, for: .primaryActionTriggered)
        bookmark.addAction(UIAction { [weak self] _ in
            guard let self, let clip = self.page?.clip else { return }
            self.onReaction?(clip, true)
        }, for: .primaryActionTriggered)

        let controls = UIStackView(arrangedSubviews: [like, comments, bookmark])
        controls.axis = .vertical
        controls.spacing = 4
        reactionIsland.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(reactionIsland)
        view.addSubview(sound)
        sound.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.muted.toggle()
            self.sound.update(symbol: self.muted ? "speaker.slash" : "speaker.wave.2",
                              label: self.muted ? "Увімкнути звук" : "Вимкнути звук")
        }, for: .primaryActionTriggered)
        controls.translatesAutoresizingMaskIntoConstraints = false
        reactionIsland.contentView.addSubview(controls)
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            controls.centerXAnchor.constraint(equalTo: reactionIsland.contentView.centerXAnchor),
            controls.centerYAnchor.constraint(equalTo: reactionIsland.contentView.centerYAnchor),
            reactionIsland.widthAnchor.constraint(equalTo: controls.widthAnchor, constant: 6),
            reactionIsland.heightAnchor.constraint(equalTo: controls.heightAnchor, constant: 8),
            reactionIsland.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),
            reactionIsland.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -62),
            sound.bottomAnchor.constraint(equalTo: reactionIsland.topAnchor, constant: -8),
            sound.centerXAnchor.constraint(equalTo: reactionIsland.centerXAnchor),
            captionStack.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 18),
            captionStack.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -130),
            captionStack.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -14)
        ])
        refresh()
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
        let updates = { self.refresh(preferredID: preferredID, reset: changed) }
        if changed && view.window != nil && !UIAccessibility.isReduceMotionEnabled {
            UIView.transition(with: view, duration: 0.22, options: [.transitionCrossDissolve, .beginFromCurrentState],
                              animations: updates)
        } else {
            updates()
        }
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
        captionStack.isHidden = active == nil
        reactionIsland.isHidden = active == nil
        sound.isHidden = active == nil
        if let active {
            author.text = store.profile(active.authorID).map { "@\($0.handle)" } ?? active.credit
            caption.text = active.caption
            updateReactions()
        }
        syncPlayback()
    }

    func updateReactions(bounce: Reaction? = nil) {
        guard let clip = page?.clip else { return }
        let liked = store.liked(clip)
        let saved = store.bookmarked(clip)
        like.update(symbol: liked ? "heart.fill" : "heart", label: liked ? "Прибрати лайк" : "Подобається",
                    color: liked ? .kadrPeach : .label, count: store.likes(clip), animated: bounce == .like)
        comments.update(symbol: "bubble", label: "Коментарі", count: store.comments(clip).count, animated: false)
        bookmark.update(symbol: saved ? "bookmark.fill" : "bookmark", label: saved ? "Прибрати зі збереженого" : "Зберегти",
                        color: saved ? .kadrPeach : .label, animated: bounce == .bookmark)
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
    private let resumeButton = makePlaybackButton(symbol: "play.fill", label: "Відтворити")
    private var enabled = false
    private var paused = false

    init(clip: Clip) {
        self.clip = clip
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Use init(clip:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        video.pin(to: view)
        video.load(clip.url, adaptsLandscape: true)
        let shade = GradientView()
        shade.gradient.colors = [UIColor.black.withAlphaComponent(0.44).cgColor,
                                  UIColor.clear.cgColor, UIColor.clear.cgColor,
                                  UIColor.black.withAlphaComponent(0.74).cgColor]
        shade.isUserInteractionEnabled = false
        shade.pin(to: view)
        let tapArea = UIButton(type: .custom)
        tapArea.isAccessibilityElement = true
        tapArea.accessibilityTraits = .button
        tapArea.accessibilityLabel = "Призупинити відео"
        tapArea.pin(to: view)
        tapArea.addAction(UIAction { [weak self, weak tapArea] _ in
            guard let self else { return }
            self.paused.toggle()
            tapArea?.accessibilityLabel = self.paused ? "Відтворити відео" : "Призупинити відео"
            self.updatePauseIndicator()
        }, for: .primaryActionTriggered)
        resumeButton.alpha = 0
        resumeButton.addAction(UIAction { [weak self, weak tapArea] _ in
            self?.paused = false
            tapArea?.accessibilityLabel = "Призупинити відео"
            self?.updatePauseIndicator()
        }, for: .primaryActionTriggered)
        view.addSubview(resumeButton)
        NSLayoutConstraint.activate([
            resumeButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            resumeButton.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    func setPlaying(_ enabled: Bool, muted: Bool) {
        loadViewIfNeeded()
        self.enabled = enabled
        video.setPlaying(enabled && !paused, muted: muted)
    }

    private func updatePauseIndicator() {
        video.setPlaying(enabled && !paused)
        let update = {
            self.resumeButton.alpha = self.paused ? 1 : 0
            self.resumeButton.transform = self.paused ? .identity : CGAffineTransform(scaleX: 0.78, y: 0.78)
        }
        if UIAccessibility.isReduceMotionEnabled { update() }
        else {
            UIView.animate(withDuration: 0.26, delay: 0, usingSpringWithDamping: 0.72,
                           initialSpringVelocity: 0, options: [.beginFromCurrentState, .allowUserInteraction],
                           animations: update)
        }
    }
}

func makePlaybackButton(symbol: String, label: String) -> UIButton {
    var style = UIButton.Configuration.glass()
    style.cornerStyle = .capsule
    style.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 30, weight: .semibold))
    style.baseForegroundColor = .white
    let button = UIButton(configuration: style)
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
    private static let context = CIContext()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var observer: Any?
    private var frameOutput: AVPlayerItemVideoOutput?
    private weak var observedItem: AVPlayerItem?
    private var metadata: Task<Void, Never>?
    private var revision = 0
    private var landscape = false
    private var aspectRatio: CGFloat = 1

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
        stopBackdrop()
        player?.pause()
        looper?.disableLooping()
        looper = nil
        player = nil
        foreground.player = nil
        foreground.videoGravity = adaptsLandscape ? .resizeAspect : .resizeAspectFill
        backdrop.isHidden = true
        backdrop.image = nil
        landscape = false
        setNeedsLayout()
        guard let url else { return }
        let asset = AVURLAsset(url: url)
        let queue = AVQueuePlayer()
        queue.isMuted = true
        looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(asset: asset))
        player = queue
        foreground.player = queue

        guard adaptsLandscape else { return }
        metadata = Task { [weak self] in
            guard let track = try? await asset.loadTracks(withMediaType: .video).first,
                  let size = try? await track.load(.naturalSize),
                  let transform = try? await track.load(.preferredTransform),
                  !Task.isCancelled, let self, self.revision == loadRevision else { return }
            let oriented = CGRect(origin: .zero, size: size).applying(transform).standardized
            self.landscape = oriented.width > oriented.height
            self.aspectRatio = oriented.height > 0 ? oriented.width / oriented.height : 1
            self.foreground.videoGravity = self.landscape ? .resizeAspect : .resizeAspectFill
            self.backdrop.isHidden = !self.landscape
            self.setNeedsLayout()
            if self.landscape {
                self.startBackdrop()
                if let poster = await VideoPoster.image(for: url), self.revision == loadRevision,
                   self.backdrop.image == nil {
                    self.backdrop.image = self.blurred(CIImage(cgImage: poster))
                }
            }
        }
    }

    func setPlaying(_ playing: Bool, muted: Bool? = nil) {
        if let muted { player?.isMuted = muted }
        if playing { player?.play() }
        else { player?.pause() }
    }

    private func startBackdrop() {
        guard observer == nil, let player else { return }
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 8), queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in self?.updateBackdrop(at: time) }
        }
    }

    private func updateBackdrop(at time: CMTime) {
        guard landscape, let current = player?.currentItem else { return }
        if current !== observedItem {
            if let frameOutput { observedItem?.remove(frameOutput) }
            let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ])
            current.add(output)
            observedItem = current
            frameOutput = output
            return
        }
        guard let frameOutput, frameOutput.hasNewPixelBuffer(forItemTime: time),
              let frame = frameOutput.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else { return }
        if let image = blurred(CIImage(cvPixelBuffer: frame)) { backdrop.image = image }
    }

    private func blurred(_ image: CIImage) -> UIImage? {
        let factor = min(1, 192 / max(image.extent.width, image.extent.height))
        let scaled = image.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = scaled.clampedToExtent()
        filter.radius = 16
        guard let filtered = filter.outputImage,
              let cgImage = Self.context.createCGImage(filtered, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func stopBackdrop() {
        if let observer { player?.removeTimeObserver(observer) }
        observer = nil
        if let frameOutput { observedItem?.remove(frameOutput) }
        observedItem = nil
        frameOutput = nil
    }

    deinit {
        metadata?.cancel()
        if let observer { player?.removeTimeObserver(observer) }
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
