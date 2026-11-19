import AVFoundation
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
    private let reactionIsland = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
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
        reactionIsland.cornerConfiguration = .capsule()
        reactionIsland.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(reactionIsland)
        controls.translatesAutoresizingMaskIntoConstraints = false
        reactionIsland.contentView.addSubview(controls)
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            controls.centerXAnchor.constraint(equalTo: reactionIsland.contentView.centerXAnchor),
            controls.centerYAnchor.constraint(equalTo: reactionIsland.contentView.centerYAnchor),
            reactionIsland.widthAnchor.constraint(equalTo: controls.widthAnchor, constant: 6),
            reactionIsland.heightAnchor.constraint(equalTo: controls.heightAnchor, constant: 8),
            reactionIsland.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),
            reactionIsland.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -70),
            captionStack.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 18),
            captionStack.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -130),
            captionStack.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -14)
        ])
        refresh()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        playingPage?.setPlaying(false, muted: muted)
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
    private let video = VideoSurface()
    private let resumeButton = GlyphButton(symbol: "play.fill", label: "Відтворити")
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
        video.load(clip.url)
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
        resumeButton.isUserInteractionEnabled = false
        resumeButton.isAccessibilityElement = false
        resumeButton.alpha = 0
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
        let update = { self.resumeButton.alpha = self.paused ? 1 : 0 }
        if UIAccessibility.isReduceMotionEnabled { update() }
        else { UIView.animate(withDuration: 0.18, animations: update) }
    }
}

final class VideoSurface: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    private var looper: AVPlayerLooper?

    func load(_ url: URL?) {
        playerLayer.player?.pause()
        looper?.disableLooping()
        looper = nil
        playerLayer.player = nil
        guard let url else { return }
        let player = AVQueuePlayer()
        player.isMuted = true
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.player = player
    }

    func setPlaying(_ playing: Bool, muted: Bool? = nil) {
        if let muted { playerLayer.player?.isMuted = muted }
        if playing { playerLayer.player?.play() }
        else { playerLayer.player?.pause() }
    }
}
