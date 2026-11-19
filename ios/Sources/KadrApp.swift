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

final class KadrTabs: UITabBarController, UITabBarControllerDelegate, UISheetPresentationControllerDelegate {
    private let store = LocalStore()
    private lazy var feed = FeedController(store: store)
    private lazy var saved = SavedController(store: store)
    private lazy var profile = ProfileController(store: store, profileID: nil)
    private let segments = FeedSectionPicker()
    private let header = UINavigationBar()
    private let feedHeader = UINavigationItem()
    private let savedHeader = UINavigationItem(title: "Збережене")
    private let inboxHeader = UINavigationItem(title: "Вхідні")
    private let profileHeader = UINavigationItem(title: "Профіль")
    private let guestProfileHeader = UINavigationItem(title: "Профіль")
    private let topEdge = UIScrollEdgeElementContainerInteraction()
    private let bottomEdge = UIScrollEdgeElementContainerInteraction()
    private let addTab = UIViewController()
    private let inbox = InboxController()
    private var keepsFeedPlaying = false
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
        addTab.tabBarItem = UITabBarItem(title: "Додати", image: UIImage(systemName: "plus.circle.fill"), selectedImage: nil)
        inbox.tabBarItem = UITabBarItem(title: "Вхідні", image: UIImage(systemName: "tray"),
                                         selectedImage: UIImage(systemName: "tray.fill"))
        inbox.additionalSafeAreaInsets.top = 58
        setViewControllers([feed, saved, addTab, inbox, profile], animated: false)
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
        feed.onComments = { [weak self] clip in self?.openComments(clip) }
        saved.onClip = { [weak self] clip in self?.openClip(clip) }
        saved.onAccount = { [weak self] in self?.openAccount() }
        profile.onClip = { [weak self] clip in self?.openClip(clip) }
        profile.onAccount = { [weak self] in self?.openAccount() }

        segments.onSelection = { [weak self] section in
            guard let self else { return }
            if section == .following && self.store.active == nil {
                self.segments.updateSelection(self.feed.section)
                self.openAccount()
                return
            }
            self.feed.selectSection(section)
            self.segments.updateSelection(section)
        }
    }

    private func configureChrome() {
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        header.isTranslucent = true
        header.tintColor = .label
        feedHeader.titleView = segments
        for item in [feedHeader, savedHeader, inboxHeader, guestProfileHeader] {
            let search = UIBarButtonItem(primaryAction: UIAction(image: UIImage(systemName: "magnifyingglass")) { [weak self] _ in
                self?.openSearch()
            })
            search.accessibilityLabel = "Пошук"
            search.accessibilityIdentifier = "header.action"
            search.identifier = "header.context"
            item.rightBarButtonItem = search
        }
        let logout = UIBarButtonItem(primaryAction: UIAction(title: "Вийти") { [weak self] _ in
            self?.signOut()
        })
        logout.accessibilityIdentifier = "header.action"
        logout.identifier = "header.context"
        profileHeader.rightBarButtonItem = logout
        let editBanner = UIBarButtonItem(primaryAction: UIAction(image: UIImage(systemName: "photo.on.rectangle")) { [weak self] _ in
            self?.profile.editBanner(from: self?.profileHeader.leftBarButtonItem)
        })
        editBanner.accessibilityLabel = "Змінити банер"
        profileHeader.leftBarButtonItem = editBanner

        topEdge.edge = .top
        header.addInteraction(topEdge)
        bottomEdge.edge = .bottom
        tabBar.addInteraction(bottomEdge)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        view.bringSubviewToFront(header)
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
        saved.refresh()
        profile.refresh()
        feed.refresh()
        updateChrome(for: selectedViewController, animated: animated)
        updatePlayback()
    }

    private func updateChrome(for controller: UIViewController?, animated: Bool) {
        let isFeed = controller === feed
        let isProfile = controller === profile
        segments.updateSelection(feed.section)
        let scroll: UIScrollView? = isFeed ? feed.edgeScrollView
            : isProfile ? profile.edgeScrollView : controller === inbox ? inbox.scrollView : saved.tableView
        scroll?.bottomEdgeEffect.style = .soft
        scroll?.topEdgeEffect.style = .soft
        bottomEdge.scrollView = scroll
        topEdge.scrollView = isFeed ? nil : scroll
        showHeader(for: controller, animated: animated)
    }

    private func showHeader(for controller: UIViewController?, animated: Bool) {
        let item: UINavigationItem
        if controller === profile {
            item = store.active == nil ? guestProfileHeader : profileHeader
        } else if controller === inbox {
            item = inboxHeader
        } else if controller === saved {
            item = savedHeader
        } else {
            item = feedHeader
        }
        guard header.topItem !== item else { return }
        header.setItems([item], animated: animated)
    }

    private func updatePlayback() {
        guard isViewLoaded else { return }
        feed.playbackEnabled = sceneActive && selectedViewController === feed && (presentedViewController == nil || keepsFeedPlaying)
    }

    private func signOut() {
        store.select(nil)
        if store.active == nil { feed.selectSection(.recommended) }
        refresh()
        showStoreError()
    }

    private func openSearch() {
        let search = SearchController(store: store)
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
        showSheet(comments, detents: [.medium(), .large()], continuePlayback: true)
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

private final class InboxController: UIViewController {
    let scrollView = UIScrollView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        scrollView.pin(to: view)
        let empty = EmptyStateView(title: "Вхідні порожні", message: "Тут з’являтимуться сповіщення.",
                                   symbol: "tray")
        empty.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(empty)
        NSLayoutConstraint.activate([
            empty.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            empty.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            empty.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            empty.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            empty.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            empty.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])
    }
}
