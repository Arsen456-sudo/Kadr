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
    private let sectionTitle = UILabel()
    private let headerAction = HeaderActionButton()
    private let topEdge = UIScrollEdgeElementContainerInteraction()
    private let bottomEdge = UIScrollEdgeElementContainerInteraction()
    private let addTab = UIViewController()
    private let inbox = InboxController()
    private var keepsFeedPlaying = false
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

        headerAction.accessibilityIdentifier = "header.action"
        segments.onSelection = { [weak self] section in
            guard let self else { return }
            if section == .following && self.store.active == nil {
                self.openAccount()
                return
            }
            self.feed.selectSection(section)
            self.segments.updateSelection(section)
        }

        headerAction.addAction(UIAction { [weak self] _ in self?.performHeaderAction() }, for: .primaryActionTriggered)
    }

    private func configureChrome() {
        let safe = view.safeAreaLayoutGuide
        sectionTitle.font = .preferredFont(forTextStyle: .title2).withTraits(.traitBold)
        sectionTitle.adjustsFontForContentSizeCategory = true
        sectionTitle.accessibilityTraits.insert(.header)
        sectionTitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for item in [sectionTitle, segments, headerAction] {
            item.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(item)
        }
        NSLayoutConstraint.activate([
            headerAction.topAnchor.constraint(equalTo: safe.topAnchor, constant: 5),
            headerAction.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),
            segments.centerXAnchor.constraint(equalTo: safe.centerXAnchor),
            segments.centerYAnchor.constraint(equalTo: headerAction.centerYAnchor),
            segments.heightAnchor.constraint(equalToConstant: HeaderActionButton.side),
            segments.widthAnchor.constraint(equalToConstant: 184),
            sectionTitle.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 16),
            sectionTitle.centerYAnchor.constraint(equalTo: headerAction.centerYAnchor),
            sectionTitle.trailingAnchor.constraint(lessThanOrEqualTo: headerAction.leadingAnchor, constant: -10)
        ])
        topEdge.edge = .top
        headerAction.addInteraction(topEdge)
        bottomEdge.edge = .bottom
        tabBar.addInteraction(bottomEdge)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        view.bringSubviewToFront(sectionTitle)
        view.bringSubviewToFront(segments)
        view.bringSubviewToFront(headerAction)
    }

    func tabBarController(_ tabBarController: UITabBarController, shouldSelect controller: UIViewController) -> Bool {
        if controller === addTab {
            openPublisher()
            return false
        }
        updateHeaderAction(for: controller, animated: true)
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
        sectionTitle.text = isProfile ? "Профіль" : controller === inbox ? "Вхідні" : "Збережене"
        let scroll: UIScrollView? = isFeed ? feed.edgeScrollView
            : isProfile ? profile.edgeScrollView : controller === inbox ? inbox.scrollView : saved.tableView
        scroll?.bottomEdgeEffect.style = .soft
        scroll?.topEdgeEffect.style = .soft
        bottomEdge.scrollView = scroll
        topEdge.scrollView = isFeed ? nil : scroll
        updateHeaderAction(for: controller, animated: animated)
        segments.isHidden = !isFeed
        sectionTitle.isHidden = isFeed
    }

    private func updateHeaderAction(for controller: UIViewController?, animated: Bool) {
        let canSignOut = controller === profile && store.active != nil
        guard canSignOut != showingProfileAction else { return }
        showingProfileAction = canSignOut
        headerAction.setLogout(canSignOut, animated: animated)
    }

    private func updatePlayback() {
        guard isViewLoaded else { return }
        feed.playbackEnabled = sceneActive && selectedViewController === feed && (presentedViewController == nil || keepsFeedPlaying)
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
