import UIKit
import Symbols

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.overrideUserInterfaceStyle = .dark
        window.tintColor = .kadrPeach
        window.rootViewController = KadrTabs()
        self.window = window
        window.makeKeyAndVisible()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        (window?.rootViewController as? KadrTabs)?.sceneActive = true
    }

    func sceneWillResignActive(_ scene: UIScene) {
        (window?.rootViewController as? KadrTabs)?.sceneActive = false
    }
}

extension UIColor {
    static let kadrPeach = UIColor(red: 1, green: 0.69, blue: 0.51, alpha: 1)
}

final class KadrTabs: UITabBarController, UITabBarControllerDelegate, UIAdaptivePresentationControllerDelegate {
    private let store = LocalStore()
    private lazy var feed = FeedController(store: store)
    private lazy var saved = SavedController(store: store)
    private lazy var profile = ProfileController(store: store, profileID: nil)
    private let segments = UISegmentedControl(items: ["Для тебе", "Підписки"])
    private let sectionTitle = UILabel()
    private let headerAction = GlyphButton(symbol: "magnifyingglass", label: "Пошук")
    private let publishButton = GlyphButton(symbol: "plus", label: "Додати відео")
    private let soundButton = GlyphButton(symbol: "speaker.slash", label: "Увімкнути звук")
    private lazy var feedTools = UIStackView(arrangedSubviews: [soundButton, publishButton])
    private var showingProfileAction = false
    private weak var selectedScreen: UIViewController?
    private var welcomePresented = false
    var sceneActive = false { didSet { updatePlayback() } }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        delegate = self
        tabBar.tintColor = .kadrPeach
        feed.tabBarItem = UITabBarItem(title: "Стрічка", image: UIImage(systemName: "house"),
                                       selectedImage: UIImage(systemName: "house.fill"))
        saved.tabBarItem = UITabBarItem(title: "Збережене", image: UIImage(systemName: "bookmark"),
                                        selectedImage: UIImage(systemName: "bookmark.fill"))
        profile.tabBarItem = UITabBarItem(title: "Профіль", image: UIImage(systemName: "person.crop.circle"),
                                          selectedImage: UIImage(systemName: "person.crop.circle.fill"))
        saved.additionalSafeAreaInsets.top = 60
        profile.additionalSafeAreaInsets.top = 60
        setViewControllers([feed, saved, profile], animated: false)
        selectedScreen = feed
        configureActions()
        configureChrome()
        refresh(animated: false)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updatePlayback()
        guard !welcomePresented else { return }
        welcomePresented = true
        if store.active == nil && !UserDefaults.standard.bool(forKey: "hasSeenWelcome") {
            UserDefaults.standard.set(true, forKey: "hasSeenWelcome")
            openAccount()
        } else {
            showStoreError()
        }
    }

    private func configureActions() {
        feed.onReaction = { [weak self] clip, bookmark in self?.react(to: clip, bookmark: bookmark) }
        feed.onComments = { [weak self] clip in self?.openComments(clip) }
        saved.onClip = { [weak self] clip in self?.openClip(clip) }
        saved.onAccount = { [weak self] in self?.openAccount() }
        profile.onClip = { [weak self] clip in self?.openClip(clip) }
        profile.onAccount = { [weak self] in self?.openAccount() }

        segments.selectedSegmentIndex = 0
        segments.accessibilityIdentifier = "feed.sections"
        headerAction.accessibilityIdentifier = "header.action"
        segments.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            if self.segments.selectedSegmentIndex == 1 && self.store.active == nil {
                self.segments.selectedSegmentIndex = 0
                self.openAccount()
                return
            }
            self.feed.selectSection(self.segments.selectedSegmentIndex == 0 ? .recommended : .following)
        }, for: .valueChanged)

        headerAction.addAction(UIAction { [weak self] _ in self?.performHeaderAction() }, for: .primaryActionTriggered)
        publishButton.addAction(UIAction { [weak self] _ in self?.openPublisher() }, for: .primaryActionTriggered)
        soundButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.feed.muted.toggle()
            self.soundButton.update(symbol: self.feed.muted ? "speaker.slash" : "speaker.wave.2",
                                    label: self.feed.muted ? "Увімкнути звук" : "Вимкнути звук")
        }, for: .primaryActionTriggered)
    }

    private func configureChrome() {
        let header = UIView()
        let safe = view.safeAreaLayoutGuide
        sectionTitle.font = .preferredFont(forTextStyle: .title2).withTraits(.traitBold)
        sectionTitle.adjustsFontForContentSizeCategory = true
        sectionTitle.accessibilityTraits.insert(.header)
        sectionTitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        feedTools.spacing = 8
        feedTools.alignment = .center
        for item in [header, headerAction, feedTools] {
            item.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(item)
        }
        for item in [segments, sectionTitle] {
            item.translatesAutoresizingMaskIntoConstraints = false
            header.addSubview(item)
            NSLayoutConstraint.activate([
                item.leadingAnchor.constraint(equalTo: header.leadingAnchor),
                item.centerYAnchor.constraint(equalTo: header.centerYAnchor),
                item.trailingAnchor.constraint(lessThanOrEqualTo: header.trailingAnchor)
            ])
        }
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: headerAction.leadingAnchor, constant: -10),
            header.topAnchor.constraint(equalTo: headerAction.topAnchor),
            header.bottomAnchor.constraint(equalTo: headerAction.bottomAnchor),
            headerAction.topAnchor.constraint(equalTo: safe.topAnchor, constant: 5),
            headerAction.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),
            feedTools.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),
            feedTools.bottomAnchor.constraint(equalTo: tabBar.topAnchor, constant: -8)
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let header = headerAction.superview {
            header.bringSubviewToFront(headerAction)
            header.bringSubviewToFront(feedTools)
            if let headerContent = segments.superview { header.bringSubviewToFront(headerContent) }
        }
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        let changed = viewController !== selectedScreen
        selectedScreen = viewController
        refresh(animated: changed)
        if changed { UIAccessibility.post(notification: .screenChanged, argument: nil) }
    }

    func tabBarController(_ tabBarController: UITabBarController,
                          animationControllerForTransitionFrom fromVC: UIViewController,
                          to toVC: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
        guard !UIAccessibility.isReduceMotionEnabled else { return nil }
        if fromVC === feed { feed.playbackEnabled = false }
        return TabTransition { [weak self, weak toVC] in self?.updateChrome(for: toVC, animated: true) }
    }

    private func refresh(animated: Bool = true) {
        saved.refresh()
        profile.refresh()
        feed.refresh()
        updateChrome(for: selectedViewController, animated: animated)
        updatePlayback()
    }

    private func updateChrome(for controller: UIViewController?, animated: Bool) {
        let isFeed = controller === feed
        let isProfile = controller === profile
        segments.selectedSegmentIndex = feed.section == .following ? 1 : 0
        sectionTitle.text = isProfile ? "Профіль" : "Збережене"
        let canSignOut = isProfile && store.active != nil
        if canSignOut != showingProfileAction {
            showingProfileAction = canSignOut
            headerAction.update(symbol: canSignOut ? "rectangle.portrait.and.arrow.right" : "magnifyingglass",
                                label: canSignOut ? "Вийти" : "Пошук", animated: animated)
        }
        segments.isUserInteractionEnabled = isFeed
        segments.accessibilityElementsHidden = !isFeed
        feedTools.isUserInteractionEnabled = isFeed
        feedTools.accessibilityElementsHidden = !isFeed
        sectionTitle.accessibilityElementsHidden = isFeed
        let changes = {
            self.segments.alpha = isFeed ? 1 : 0
            self.sectionTitle.alpha = isFeed ? 0 : 1
            self.feedTools.alpha = isFeed ? 1 : 0
        }
        if animated && !UIAccessibility.isReduceMotionEnabled {
            UIViewPropertyAnimator.runningPropertyAnimator(withDuration: 0.28, delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction], animations: changes)
        } else {
            changes()
        }
    }

    private func updatePlayback() {
        guard isViewLoaded else { return }
        feed.playbackEnabled = sceneActive && selectedViewController === feed && presentedViewController == nil
    }

    private func performHeaderAction() {
        if showingProfileAction {
            store.select(nil)
            if store.active == nil { feed.selectSection(.recommended) }
            refresh()
            showStoreError()
        } else {
            let search = SearchController(store: store)
            search.onChange = { [weak self] in self?.refresh() }
            search.onClip = { [weak self, weak search] clip in
                self?.openClip(clip, from: search?.navigationController)
            }
            showSheet(search)
        }
    }

    private func react(to clip: Clip, bookmark: Bool) {
        guard store.active != nil else { openAccount(); return }
        let previous = bookmark ? store.bookmarked(clip) : store.liked(clip)
        store.toggleReaction(clip, bookmark: bookmark)
        if showStoreError() { return }
        let selected = bookmark ? store.bookmarked(clip) : store.liked(clip)
        if selected != previous {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            feed.updateReactions(bounce: bookmark ? .bookmark : .like)
        }
    }

    private func openAccount(afterAuthentication: (() -> Void)? = nil) {
        let account = AccountController(store: store)
        account.onGuest = { [weak self] in self?.closeSheet() }
        account.onAuthenticated = { [weak self] in
            self?.closeSheet {
                self?.feed.selectSection(.recommended)
                self?.refresh()
                afterAuthentication?()
            }
        }
        showSheet(account)
    }

    private func openComments(_ clip: Clip) {
        let comments = CommentsController(store: store, clip: clip)
        comments.onAccount = { [weak self] in
            self?.closeSheet {
                self?.openAccount(afterAuthentication: { [weak self] in self?.openComments(clip) })
            }
        }
        comments.onComment = { [weak self] in self?.feed.updateReactions() }
        showSheet(comments, detents: [.medium(), .large()])
    }

    private func openPublisher() {
        guard store.active != nil else { openAccount(); return }
        let publisher = PublishController(store: store)
        publisher.onPublish = { [weak self] clip in
            self?.closeSheet {
                guard let self else { return }
                self.selectedViewController = self.feed
                self.selectedScreen = self.feed
                self.feed.selectSection(.recommended, preferredID: clip.id)
                self.refresh()
            }
        }
        showSheet(publisher)
    }

    private func openClip(_ clip: Clip, from presenter: UIViewController? = nil) {
        let player = ClipPreviewController(clip: clip)
        if let presenter {
            player.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak player] _ in
                player?.dismiss(animated: true)
            })
            presenter.present(UINavigationController(rootViewController: player), animated: true)
        } else {
            showSheet(player)
        }
    }

    private func showSheet(_ controller: UIViewController, detents: [UISheetPresentationController.Detent] = [.large()]) {
        guard presentedViewController == nil else { return }
        feed.playbackEnabled = false
        controller.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
            self?.closeSheet()
        })
        let navigation = UINavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .pageSheet
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = detents
            sheet.prefersGrabberVisible = true
            sheet.delegate = self
        }
        present(navigation, animated: true)
    }

    private func closeSheet(completion: (() -> Void)? = nil) {
        dismiss(animated: true) { [weak self] in
            self?.refresh()
            completion?()
        }
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        refresh()
    }

    @discardableResult
    private func showStoreError() -> Bool {
        guard let error = store.errorMessage, presentedViewController == nil else { return false }
        store.errorMessage = nil
        showMessage(error)
        return true
    }
}

private final class TabTransition: NSObject, UIViewControllerAnimatedTransitioning {
    private let updateChrome: () -> Void

    init(updateChrome: @escaping () -> Void) {
        self.updateChrome = updateChrome
    }

    func transitionDuration(using transitionContext: (any UIViewControllerContextTransitioning)?) -> TimeInterval { 0.27 }

    func animateTransition(using context: any UIViewControllerContextTransitioning) {
        guard let destination = context.viewController(forKey: .to),
              let incoming = context.view(forKey: .to),
              let outgoing = context.view(forKey: .from) else {
            context.completeTransition(false)
            return
        }
        let finalFrame = context.finalFrame(for: destination)
        incoming.frame = finalFrame.isEmpty ? outgoing.frame : finalFrame
        incoming.alpha = 0
        incoming.transform = CGAffineTransform(translationX: 0, y: 8)
        context.containerView.addSubview(incoming)
        updateChrome()
        let animator = UIViewPropertyAnimator(duration: transitionDuration(using: context), curve: .easeInOut) {
            incoming.alpha = 1
            incoming.transform = .identity
        }
        animator.addCompletion { _ in
            if context.transitionWasCancelled {
                incoming.alpha = 1
                incoming.transform = .identity
                incoming.removeFromSuperview()
            }
            context.completeTransition(!context.transitionWasCancelled)
        }
        animator.startAnimation()
    }
}
