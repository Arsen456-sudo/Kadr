import SwiftUI
import UIKit

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
    private var tabs: KadrTabs?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.overrideUserInterfaceStyle = .dark
        window.tintColor = .kadrPeach
        let tabs = KadrTabs()
        self.tabs = tabs
        window.rootViewController = UIHostingController(rootView: KadrNavigationShell(tabs: tabs, state: tabs.toolbarState))
        self.window = window
        window.makeKeyAndVisible()
        if let url = options.urlContexts.first?.url { DispatchQueue.main.async { tabs.open(link: url) } }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        if let url = URLContexts.first?.url { tabs?.open(link: url) }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        tabs?.sceneActive = true
    }

    func sceneWillResignActive(_ scene: UIScene) {
        tabs?.sceneActive = false
        tabs?.saveForBackground()
    }
}

extension UIColor {
    static let kadrPeach = UIColor(red: 1, green: 0.69, blue: 0.51, alpha: 1)
}

final class KadrTabs: UITabBarController, UITabBarControllerDelegate, UISheetPresentationControllerDelegate {
    private let store = LocalStore()
    private lazy var feed = FeedController(store: store)
    private lazy var profile = ProfileController(store: store, profileID: nil)
    let toolbarState = KadrToolbarState()
    private var immersive = false

    override var prefersStatusBarHidden: Bool { immersive }
    override var childForStatusBarHidden: UIViewController? { nil }
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .fade }
    override var prefersHomeIndicatorAutoHidden: Bool { immersive }
    private let topEdge = UIScrollEdgeElementContainerInteraction()
    private let bottomEdge = UIScrollEdgeElementContainerInteraction()
    private weak var observedScroll: UIScrollView?
    private var observedImmersive = false
    private let addTab = UIViewController()
    private lazy var services = store.services
    private var social: any SocialRepository { services.social }
    private lazy var inbox = InboxController(store: store, repository: social)
    private var keepsFeedPlaying = false
    private weak var selectedScreen: UIViewController?
    private var welcomePresented = false
    private var syncTask: Task<Void, Never>?
    private var syncRequested = false
    var sceneActive = false { didSet { updatePlayback(); if sceneActive { synchronizeIfConfigured() } } }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(synchronizeIfConfigured), name: .kadrLocalDidChange, object: store)
        tabBar.tintColor = .kadrPeach
        feed.tabBarItem = UITabBarItem(title: "Стрічка", image: AppSymbol.image( "house"),
                                       selectedImage: AppSymbol.image( "house.fill"))
        profile.tabBarItem = UITabBarItem(title: "Профіль", image: AppSymbol.image( "person"),
                                          selectedImage: AppSymbol.image( "person.fill"))
        addTab.tabBarItem = UITabBarItem(title: "Додати", image: AppSymbol.image( "plus.circle.fill"), selectedImage: nil)
        inbox.tabBarItem = UITabBarItem(title: "Вхідні", image: AppSymbol.image( "tray"),
                                         selectedImage: AppSymbol.image( "tray.fill"))
        inbox.additionalSafeAreaInsets.top = 58
        setViewControllers([feed, addTab, inbox, profile], animated: false)
        selectedScreen = feed
        configureActions()
        configureChrome()
        refresh(animated: false)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateChrome(for: selectedViewController, animated: false)
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
        feed.onAuthor = { [weak self] id in self?.openAuthor(id) }
        feed.onComments = { [weak self] clip in self?.openComments(clip) }
        inbox.onSearch = { [weak self] in self?.openSearch() }
        inbox.onAccount = { [weak self] in self?.openAccount() }
        inbox.onProfile = { [weak self] id in self?.openAuthor(id) }
        inbox.onPost = { [weak self] clip in self?.openClip(clip) }
        inbox.onChat = { [weak self] peer in self?.openChat(peer) }
        feed.onDescription = { [weak self] clip in
            guard let self else { return }
            self.showSheet(PostDescriptionController(clip: clip, store: self.store), detents: [.medium(), .large()], continuePlayback: true)
        }
        profile.onClip = { [weak self] clip in self?.openClip(clip) }
        profile.onAccount = { [weak self] in self?.openAccount() }
        profile.onCompact = { [weak self] title in self?.toolbarState.compactTitle = title }
        profile.onChange = { [weak self] in self?.refresh() }
        profile.usesToolbarDock = true
        profile.onDocked = { [weak self] docked in
            guard let self, self.toolbarState.profileDocked != docked else { return }
            self.toolbarState.profileDocked = docked
        }
        profile.onSectionChange = { [weak self] section in self?.toolbarState.profileSection = section }
        toolbarState.onProfileSection = { [weak self] section in self?.profile.select(section) }

        toolbarState.onStudio = { [weak self] in
            guard let self else { return }; self.showSheet(StudioController(store: self.store))
        }
        toolbarState.onSearch = { [weak self] in self?.openSearch() }
        toolbarState.onSignOut = { [weak self] in self?.signOut() }
        toolbarState.onChooseBanner = { [weak self] in self?.profile.chooseBanner() }
        toolbarState.onRemoveBanner = { [weak self] in self?.profile.removeBanner() }
        toolbarState.onImmersive = { [weak self] in
            guard let self else { return }
            self.setImmersive(!self.immersive)
        }

        toolbarState.onOverview = { [weak self] in
            guard let self else { return }
            self.toolbarState.overview = true
            self.feed.setOverview(true)
        }
        toolbarState.onSection = { [weak self] section in
            guard let self else { return }
            if section == .following && self.store.active == nil {
                self.openAccount()
                return
            }
            self.toolbarState.overview = false
            self.feed.setOverview(false)
            self.feed.selectSection(section)
            if self.toolbarState.feedSection != section { self.toolbarState.feedSection = section }
        }
    }

    private func configureChrome() {
        topEdge.edge = .top
        bottomEdge.edge = .bottom
        tabBar.addInteraction(bottomEdge)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Keep the existing full-bleed UIKit screens anchored to the window's top safe area.
        if let window = view.window {
            let inheritedTop = view.safeAreaInsets.top - additionalSafeAreaInsets.top
            let adjustment = window.safeAreaInsets.top - inheritedTop
            if abs(additionalSafeAreaInsets.top - adjustment) > 0.25 {
                additionalSafeAreaInsets.top = adjustment
            }
        }
        updateEdgeEffects(for: selectedViewController)
        guard let header = navigationController?.navigationBar else { return }
        if topEdge.view !== header { header.addInteraction(topEdge) }
        if profile.isViewLoaded, selectedViewController === profile, store.active != nil {
            let glassFrame = navigationGlassFrame(in: header, relativeTo: profile.view)
            let bottom = glassFrame?.maxY ?? profile.view.convert(header.bounds, from: header).maxY
            if let frame = glassFrame, frame.width > profile.view.bounds.width / 2 {
                let leading = max(0, frame.minX)
                let trailing = max(0, profile.view.bounds.width - frame.maxX)
                if abs(profile.sectionInsets.leading - leading) > 0.25 || abs(profile.sectionInsets.trailing - trailing) > 0.25 {
                    profile.sectionInsets = .init(top: 0, leading: leading, bottom: 0, trailing: trailing)
                }
            }
            let barFrame = profile.view.convert(header.bounds, from: header)
            let top = profile.usesToolbarDock ? (glassFrame?.midY ?? barFrame.midY) - 22 : bottom + 2
            if profile.sectionPinTop != top { profile.sectionPinTop = top }
        }
    }

    private func navigationGlassFrame(in container: UIView, relativeTo target: UIView) -> CGRect? {
        var frame: CGRect?
        if let effect = container as? UIVisualEffectView, effect.effect is UIGlassEffect,
           container.bounds.height >= 28, container.bounds.height <= 60,
           container.bounds.width <= target.bounds.width * 0.6 {
            frame = container.convert(container.bounds, to: target)
        }
        for child in container.subviews {
            if let rect = navigationGlassFrame(in: child, relativeTo: target) { frame = frame.map { $0.union(rect) } ?? rect }
        }
        return frame
    }

    private func setImmersive(_ enabled: Bool) {
        immersive = enabled
        feed.immersive = enabled
        toolbarState.immersive = enabled
        setTabBarHidden(enabled, animated: !UIAccessibility.isReduceMotionEnabled)
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
    }

    func tabBarController(_ tabBarController: UITabBarController, shouldSelect controller: UIViewController) -> Bool {
        if controller === addTab {
            openPublisher()
            return false
        }
        showHeader(for: controller, animated: true)
        return true
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        let changed = viewController !== selectedScreen
        selectedScreen = viewController
        refresh(animated: changed)
        if changed { UIAccessibility.post(notification: .screenChanged, argument: nil) }
    }

    private func refresh(animated: Bool = true) {
        if selectedViewController === inbox { inbox.refresh() }
        if selectedViewController === profile { profile.refresh() }
        if selectedViewController === feed { feed.refresh() }
        updateChrome(for: selectedViewController, animated: animated)
        updatePlayback()
    }

    private func updateChrome(for controller: UIViewController?, animated: Bool) {
        let isFeed = controller === feed
        if !isFeed && immersive { setImmersive(false) }
        if toolbarState.feedSection != feed.section { toolbarState.feedSection = feed.section }
        updateEdgeEffects(for: controller)
        showHeader(for: controller, animated: animated)
    }

    private func updateEdgeEffects(for controller: UIViewController?) {
        let isFeed = controller === feed
        let scroll: UIScrollView? = isFeed ? feed.edgeScrollView
            : controller === profile ? profile.edgeScrollView : controller === inbox ? inbox.scrollView : nil
        let changed = observedScroll !== scroll
        let hidden = isFeed && immersive
        if changed {
            observedScroll = scroll
            setContentScrollView(scroll, for: .all)
            var ancestor = parent
            while let controller = ancestor {
                controller.setContentScrollView(scroll, for: .all)
                ancestor = controller.parent
            }
            bottomEdge.scrollView = scroll
            topEdge.scrollView = scroll
        }
        if changed || observedImmersive != hidden {
            observedImmersive = hidden
            scroll?.topEdgeEffect.style = .soft
            scroll?.bottomEdgeEffect.style = .soft
            scroll?.topEdgeEffect.isHidden = hidden
            scroll?.bottomEdgeEffect.isHidden = hidden
        }
    }

    private func showHeader(for controller: UIViewController?, animated: Bool) {
        let screen: KadrToolbarState.Screen
        if controller === profile { screen = .profile }
        else if controller === inbox { screen = .inbox }
        else { screen = .feed }
        let canSignOut = screen == .profile && store.active != nil
        let context = KadrToolbarState.Context(screen: screen, canSignOut: canSignOut,
                                               hasBanner: canSignOut && store.active?.bannerURL != nil,
                                               usesPortrait: canSignOut && store.studio.appearance.theme == "atmosphere")
        guard toolbarState.context != context else { return }
        // Only publish the toolbar context in the transaction. The UIKit content
        // representable has a no-op update, so video and grid layout do not animate.
        if animated && !UIAccessibility.isReduceMotionEnabled {
            withAnimation(.smooth(duration: 0.28)) { toolbarState.context = context }
        } else { toolbarState.context = context }
        view.setNeedsLayout()
    }

    @objc private func synchronizeIfConfigured() {
        guard let engine = services.sync else { return }
        syncRequested = true
        guard syncTask == nil else { return }
        syncRequested = false
        syncTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.syncTask = nil
                if self.syncRequested { self.synchronizeIfConfigured() }
            }
            do {
                try await Task.sleep(for: .milliseconds(600))
                try await engine.synchronize()
                self.refresh(animated: false)
            } catch { /* The durable local state remains available while offline. */ }
        }
    }

    private func updatePlayback() {
        guard isViewLoaded else { return }
        feed.playbackEnabled = sceneActive && selectedViewController === feed && (presentedViewController == nil || keepsFeedPlaying)
    }

    func saveForBackground() { store.flushForBackground() }

    private func signOut() {
        store.select(nil)
        if store.active == nil { feed.selectSection(.recommended) }
        refresh()
        showStoreError()
    }

    func open(link: URL) {
        guard link.scheme == "kadr" else { return }
        let key = link.lastPathComponent
        let action: () -> Void = { [weak self] in
            guard let self else { return }
            if link.host == "profile", let profile = self.store.profiles.first(where: { $0.handle == key }) { self.openAuthor(profile.id) }
            else if link.host == "post", let clip = self.store.allClips.first(where: { $0.id == key }) { self.openClip(clip) }
            else { self.showMessage("Цей матеріал ще недоступний локально.") }
        }
        if presentedViewController != nil { closeSheet(completion: action) } else { action() }
    }

    private func openSearch() {
        let search = SearchController(store: store, repository: social)
        search.onAccount = { [weak self] in self?.closeSheet { self?.openAccount() } }
        search.onChange = { [weak self] in self?.refresh() }
        search.onClip = { [weak self, weak search] clip in
            self?.openClip(clip, from: search?.navigationController)
        }
        showSheet(search)
    }

    private func react(to clip: Clip, bookmark: Bool) {
        guard store.active != nil else { openAccount(); return }
        let previous = bookmark ? store.bookmarked(clip) : store.liked(clip)
        store.toggleReaction(clip, bookmark: bookmark)
        if showStoreError() { return }
        let selected = bookmark ? store.bookmarked(clip) : store.liked(clip)
        if selected != previous {
            if store.studio.preferences.haptics { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
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
                if let afterAuthentication { afterAuthentication() }
                else if let self, self.store.studio.appearance.interests.isEmpty {
                    let interests = InterestPickerController(store: self.store)
                    interests.onComplete = { [weak self] in self?.closeSheet() }
                    self.showSheet(interests)
                }
            }
        }
        showSheet(account)
    }

    private func openComments(_ clip: Clip) {
        guard clip.settings.allowsComments else { return }
        let comments = CommentsController(store: store, clip: clip)
        comments.onAccount = { [weak self] in
            self?.closeSheet {
                self?.openAccount(afterAuthentication: { [weak self] in self?.openComments(clip) })
            }
        }
        comments.onComment = { [weak self] in self?.feed.updateReactions() }
        showSheet(comments, detents: [.medium(), .large()], continuePlayback: true)
    }

    private func openPublisher() {
        guard store.active != nil else { openAccount(); return }
        let publisher = PublishController(store: store)
        publisher.onClose = { [weak self] in self?.closeSheet() }
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

    private func openAuthor(_ id: UUID) {
        guard store.profile(id) != nil else { return }
        if store.active?.id == id {
            selectedViewController = profile
            selectedScreen = profile
            refresh()
            return
        }
        let author = ProfileController(store: store, profileID: id)
        author.onClip = { [weak self, weak author] clip in
            self?.openClip(clip, from: author?.navigationController)
        }
        author.onChange = { [weak self] in self?.feed.refresh() }
        author.onAccount = { [weak self] in self?.closeSheet { self?.openAccount() } }
        showSheet(author)
    }

    private func openChat(_ peer: Profile) {
        guard store.active != nil else { openAccount(); return }
        showSheet(ChatController(store: store, repository: social, peer: peer))
    }

    private func openClip(_ clip: Clip, from presenter: UIViewController? = nil) {
        let player = ClipPreviewController(clip: clip, store: store)
        if let presenter {
            player.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak player] _ in
                player?.dismiss(animated: true)
            })
            presenter.present(UINavigationController(rootViewController: player), animated: true)
        } else {
            showSheet(player)
        }
    }

    private func showSheet(_ controller: UIViewController,
                           detents: [UISheetPresentationController.Detent] = [.large()],
                           continuePlayback: Bool = false) {
        guard presentedViewController == nil else { return }
        keepsFeedPlaying = continuePlayback
        if !continuePlayback { feed.playbackEnabled = false }
        let close = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
            self?.closeSheet()
        })
        close.accessibilityIdentifier = "sheet.close"
        controller.navigationItem.leftBarButtonItem = close
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
            self?.keepsFeedPlaying = false
            self?.refresh()
            completion?()
        }
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        keepsFeedPlaying = false
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

