import AVFoundation
import PhotosUI
import UIKit
import UniformTypeIdentifiers

final class ProfileController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate,
                               PHPickerViewControllerDelegate {
    private let store: LocalStore
    private let profileID: UUID?
    private let preview: Bool
    private let repository: any SocialRepository
    private var followTask: Task<Void, Never>?
    private var selectedSection = ProfileSection.posts
    private var sectionIsland = ProfileSectionPicker()
    private var atmosphere = false
    private var dashboard: [ProfileDashboardRow] = []
    private let ambientBackground = GradientView()
    var sectionInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16) { didSet { updateSectionPosition() } }
    var sectionPinTop: CGFloat? { didSet { updateSectionPosition() } }
    var usesToolbarDock = false
    var onDocked: ((Bool) -> Void)?
    var onSectionChange: ((ProfileSection) -> Void)?
    private weak var sectionToolbarHost: UIView?
    private var islandOverlay: ProfileIslandOverlay?

    private func installIslandOverlay() {
        guard atmosphere, usesToolbarDock, let parent = navigationController?.view else { return }
        if islandOverlay?.superview !== parent {
            islandOverlay?.removeFromSuperview()
            let overlay = ProfileIslandOverlay(frame: parent.bounds)
            overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            parent.addSubview(overlay); islandOverlay = overlay
        }
        islandOverlay?.isHidden = !visible
    }

    func setSectionToolbarHost(_ host: UIView, removing: Bool) {
        if removing {
            guard sectionToolbarHost === host else { return }
            sectionToolbarHost = nil
        } else { sectionToolbarHost = host }
        updateSectionPosition()
    }
    private enum PhotoDestination { case banner, avatar, portrait }
    private var pickerDestination = PhotoDestination.banner
    private lazy var layout = UICollectionViewCompositionalLayout { [weak self] sectionIndex, environment in
        let width = environment.container.effectiveContentSize.width
        let dashboard = self?.atmosphere == true && self?.selectedSection == .overview
        let modern = self?.atmosphere == true
        let side = modern ? (width - 40) / 2 : (width - 4) / 3
        let group: NSCollectionLayoutGroup
        if modern {
            if dashboard {
                let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(92))
                group = .vertical(layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)])
            } else {
                let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1)))
                group = .horizontal(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute((side * 1.38).rounded())), repeatingSubitem: item, count: 2)
                group.interItemSpacing = .fixed(8)
            }
        } else {
            let size = NSCollectionLayoutSize(widthDimension: .absolute(side), heightDimension: .absolute(side * 1.27))
            let item = NSCollectionLayoutItem(layoutSize: size)
            group = .horizontal(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(side * 1.27)), subitems: [item, item, item])
            group.interItemSpacing = .fixed(2)
        }
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = modern ? (dashboard ? 0 : 8) : 2
        if modern && sectionIndex == 1 {
            section.contentInsets = .init(top: 12, leading: 16, bottom: 24, trailing: 16)
        }
        if sectionIndex == 0, let self, let profile = self.visibleProfile {
            let height = self.heroHeight(for: profile)
            section.boundarySupplementaryItems = [NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(height)),
                elementKind: UICollectionView.elementKindSectionHeader, alignment: .top)]
        }
        return section
    }
    private let backdrop = ProfileBackdrop()
    private var cachedHeroHeight: CGFloat?
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
    var onCompact: ((String?) -> Void)?
    private var compact = false
    private var displayedAppearance: CreatorAppearance?
    private var displayedTheme: String?

    init(store: LocalStore, profileID: UUID?, repository: (any SocialRepository)? = nil, preview: Bool = false) {
        self.preview = preview
        self.repository = repository ?? store.services.social
        self.store = store
        self.profileID = profileID
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Use init(store:profileID:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        ambientBackground.isUserInteractionEnabled = false
        ambientBackground.pin(to: view)
        backdrop.onPalette = { [weak self] color in self?.setAmbientColor(color) }
        backdrop.translatesAutoresizingMaskIntoConstraints = true
        view.addSubview(backdrop)
        grid.backgroundColor = .clear
        grid.alwaysBounceVertical = true
        grid.contentInsetAdjustmentBehavior = .never
        grid.topEdgeEffect.style = .soft
        grid.topEdgeEffect.isHidden = false
        grid.accessibilityIdentifier = "profile.screen"
        NotificationCenter.default.addObserver(self, selector: #selector(contentSizeChanged), name: UIContentSizeCategory.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(localAppearanceChanged), name: .kadrLocalDidChange, object: store)
        grid.dataSource = self
        grid.delegate = self
        grid.register(ClipThumbnailCell.self, forCellWithReuseIdentifier: "clip")
        grid.register(ProfileDashboardCell.self, forCellWithReuseIdentifier: "dashboard")
        grid.register(ProfileHero.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                      withReuseIdentifier: "hero")
        grid.pin(to: view)
        sectionIsland.translatesAutoresizingMaskIntoConstraints = true
        sectionIsland.onSelection = { [weak self] section in self?.select(section) }
        view.addSubview(sectionIsland)
        refresh()
    }

    @objc private func contentSizeChanged() {
        cachedHeroHeight = nil; layout.invalidateLayout(); view.setNeedsLayout()
    }

    @objc private func localAppearanceChanged() {
        let profile = profileID.flatMap { store.profile($0) } ?? (profileID == nil ? store.active : nil)
        let appearance = profile.flatMap { store.state.studio?.accounts[$0.id.uuidString]?.appearance } ?? CreatorAppearance()
        guard appearance != displayedAppearance else { return }
        refresh()
        onChange?()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refresh()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateBackdropPosition()
        updateSectionPosition()
    }

    private func heroHeight(for profile: Profile) -> CGFloat {
        if let height = cachedHeroHeight { return height }
        let height = ProfileHero.height(for: profile, width: view.bounds.width, top: view.safeAreaInsets.top,
                                        showsFollow: followState != nil, appearance: store.state.studio?.accounts[profile.id.uuidString]?.appearance ?? CreatorAppearance(), own: profile.id == store.active?.id && !preview)
        cachedHeroHeight = height
        return height
    }

    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint,
                                  targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard !atmosphere, let profile = visibleProfile else { return }
        let pin = sectionPinTop ?? (navigationController == nil ? view.safeAreaInsets.top + 46 : view.safeAreaInsets.top + 2)
        let pinOffset = max(0, heroHeight(for: profile) - 50 - pin)
        let proposed = targetContentOffset.pointee.y
        // Let UIKit finish the existing deceleration; do not run another animation
        // or intercept the pan. A fast fling that reaches the pinned tabs continues.
        if proposed > 0, proposed < pinOffset { targetContentOffset.pointee.y = 0 }
    }

    private func setAmbientColor(_ color: UIColor) {
        guard atmosphere else { return }
        view.backgroundColor = color
        CATransaction.begin(); CATransaction.setDisableActions(true)
        ambientBackground.gradient.colors = [color.cgColor, color.cgColor]
        CATransaction.commit()
    }

    private func updateBackdropPosition() {
        guard let profile = visibleProfile else { return }
        let height = ProfileHero.coverSize(for: profile, width: view.bounds.width, top: view.safeAreaInsets.top, theme: store.state.studio?.accounts[profile.id.uuidString]?.appearance.theme ?? "minimal") + 100
        let offset = grid.contentOffset.y
        let frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: max(0, height - offset))
        if backdrop.frame != frame { backdrop.frame = frame }
        backdrop.setScroll(offset: offset, mediaHeight: height)
    }

    private func updateSectionPosition() {
        guard isViewLoaded, let profile = visibleProfile else {
            sectionIsland.isHidden = true
            if compact {
                compact = false
                if usesToolbarDock { onDocked?(false) }
                onCompact?(nil)
            }
            return
        }
        let headerHeight = heroHeight(for: profile)
        let naturalY = headerHeight - 50 - grid.contentOffset.y
        let pin = sectionPinTop ?? (navigationController == nil ? view.safeAreaInsets.top + 46 : view.safeAreaInsets.top + 2)
        let nowCompact = naturalY <= pin
        let titleProgress = min(1, max(0, (pin + 88 - naturalY) / 88))
        (sectionToolbarHost as? ProfileScrollTitle)?.setScrollProgress(titleProgress)
        if compact != nowCompact {
            compact = nowCompact
            if usesToolbarDock { onDocked?(compact) }
            onCompact?(compact ? "@" + profile.handle : nil)
            if navigationController?.presentingViewController != nil { navigationItem.title = compact ? "@" + profile.handle : "Профіль" }
        }
        let leading = max(view.safeAreaInsets.left, sectionInsets.leading)
        let trailing = max(view.safeAreaInsets.right, sectionInsets.trailing)
        let fullWidth = max(0, view.bounds.width - leading - trailing)
        let dockWidth = atmosphere ? min(260, max(160, view.bounds.width - 128)) : min(216, max(132, view.bounds.width - 172))
        let dockX = (view.bounds.width - dockWidth) / 2 - (atmosphere ? 0 : 14)
        let fraction = usesToolbarDock ? min(1, max(0, (pin + 96 - naturalY) / 96)) : 0
        let progress = fraction * fraction * (3 - 2 * fraction)
        let floatingFrame = CGRect(x: atmosphere ? dockX : leading + (dockX - leading) * progress, y: max(pin, naturalY),
                                   width: atmosphere ? dockWidth : fullWidth + (dockWidth - fullWidth) * progress, height: 44)
        if atmosphere {
            installIslandOverlay()
            let parent: UIView = islandOverlay ?? view
            if sectionIsland.superview !== parent { sectionIsland.removeFromSuperview(); parent.addSubview(sectionIsland) }
            var frame = parent.convert(floatingFrame, from: view)
            if let host = sectionToolbarHost, host.window != nil, parent !== view {
                let dock = parent.convert(host.bounds, from: host)
                frame.origin.x = dock.minX; frame.size.width = dock.width
                frame.origin.y = max(frame.minY, dock.minY)
            }
            if sectionIsland.frame != frame { sectionIsland.frame = frame }
            sectionIsland.isHidden = false
            if parent === view, view.subviews.last !== sectionIsland { view.bringSubviewToFront(sectionIsland) }
        } else {
            islandOverlay?.isHidden = true
            if sectionIsland.superview !== view { sectionIsland.removeFromSuperview(); view.addSubview(sectionIsland) }
            sectionIsland.frame = floatingFrame
            sectionIsland.isHidden = usesToolbarDock && nowCompact
            if view.subviews.last !== sectionIsland { view.bringSubviewToFront(sectionIsland) }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if lastSize != view.bounds.size || lastSafeTop != view.safeAreaInsets.top {
            cachedHeroHeight = nil
            lastSafeTop = view.safeAreaInsets.top
            lastSize = view.bounds.size
            if let visibleProfile {
                hero?.setCover(for: visibleProfile, width: lastSize.width, top: lastSafeTop)
                updateBackdropPosition()
            }
            layout.invalidateLayout()
        }
        var bottomInset = view.safeAreaInsets.bottom
        if atmosphere, let profile = visibleProfile {
            let pin = sectionPinTop ?? view.safeAreaInsets.top
            let pinOffset = max(0, heroHeight(for: profile) - 50 - pin)
            let available = max(0, layout.collectionViewContentSize.height - view.bounds.height)
            bottomInset += max(0, pinOffset - available)
        }
        if abs(grid.contentInset.bottom - bottomInset) > 0.25 { grid.contentInset.bottom = bottomInset }
        grid.verticalScrollIndicatorInsets = view.safeAreaInsets
        updateSectionPosition()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        visible = true
        islandOverlay?.isHidden = !atmosphere
        updateSectionPosition()
        backdrop.setPlaying(true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        visible = false
        islandOverlay?.isHidden = true
        backdrop.setPlaying(false)
    }

    func refresh() {
        guard isViewLoaded else { return }
        configureBannerMenu()
        let profile = profileID.flatMap { store.profile($0) } ?? (profileID == nil ? store.active : nil)
        let appearance = profile.flatMap { store.state.studio?.accounts[$0.id.uuidString]?.appearance } ?? CreatorAppearance()
        let changedAppearance = appearance != displayedAppearance
        displayedAppearance = appearance
        let changedTheme = displayedTheme != appearance.theme
        displayedTheme = appearance.theme
        let newAtmosphere = appearance.theme == "atmosphere"
        if atmosphere != newAtmosphere {
            atmosphere = newAtmosphere
            sectionIsland.removeFromSuperview()
            sectionIsland = ProfileSectionPicker(atmosphere: atmosphere)
            sectionIsland.translatesAutoresizingMaskIntoConstraints = true
            sectionIsland.onSelection = { [weak self] section in self?.select(section) }
            view.addSubview(sectionIsland)
            ambientBackground.isHidden = !atmosphere
            if atmosphere { setAmbientColor(UIColor(white: 0.16, alpha: 1)) }
            else { view.backgroundColor = .systemBackground }
        }
        let changedText = visibleProfile?.name != profile?.name || visibleProfile?.bio != profile?.bio || visibleProfile?.handle != profile?.handle
        let resetScroll = visibleProfile?.id != profile?.id
        let changedBanner = visibleProfile?.bannerFile != profile?.bannerFile || visibleProfile?.portraitFile != profile?.portraitFile
        let changedAvatar = visibleProfile?.avatar != profile?.avatar
        if resetScroll || changedAppearance || changedText || changedBanner || changedAvatar { cachedHeroHeight = nil }
        visibleProfile = profile
        if resetScroll || changedBanner || changedAppearance || (changedAvatar && appearance.theme == "atmosphere") {
            backdrop.show(profile, start: appearance.bannerStart, theme: appearance.theme)
            backdrop.setPlaying(visible)
        }
        if resetScroll || changedTheme {
            selectedSection = atmosphere ? .overview : .posts
            onSectionChange?(selectedSection)
        }
        if let profile { dashboard = ProfileDashboardRow.rows(profile: profile, store: store, own: !preview && store.active?.id == profile.id) }
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
            let state: Bool? = store.active?.id != profile.id ? store.follows(profile) : nil
            if resetScroll || changedBanner || changedAvatar || changedAppearance || changedText || state != followState || clips != newClips || (atmosphere && selectedSection == .overview) {
                clips = newClips
                followState = state
                cachedHeroHeight = nil
                layout.invalidateLayout()
                grid.reloadData()
                if resetScroll || changedTheme { grid.setContentOffset(.zero, animated: false) }
                updateBackdropPosition()
                updateSectionPosition()
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

    func numberOfSections(in collectionView: UICollectionView) -> Int { atmosphere ? 3 : 1 }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if atmosphere {
            if section == 0 { return 0 }
            if selectedSection == .overview { return section == 1 ? dashboard.count : 0 }
            return section == 1 ? clips.count : 0
        }
        return clips.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if atmosphere && selectedSection == .overview {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "dashboard", for: indexPath) as! ProfileDashboardCell
            cell.show(dashboard[indexPath.item], first: indexPath.item == 0, last: indexPath.item == dashboard.count - 1); return cell
        }
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "clip", for: indexPath) as! ClipThumbnailCell
        cell.layer.cornerRadius = atmosphere ? 18 : 0; cell.layer.cornerCurve = .continuous
        cell.show(clips[indexPath.item], modern: atmosphere)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        if atmosphere && selectedSection == .overview {
            openDashboard(dashboard[indexPath.item].destination); return
        }
        if let onClip { onClip(clips[indexPath.item]) }
        else { navigationController?.pushViewController(ClipPreviewController(clip: clips[indexPath.item], store: store), animated: true) }
    }

    private func posts(for profile: Profile) -> [Clip] {
        if selectedSection == .posts {
            let pins = store.state.studio?.accounts[profile.id.uuidString]?.appearance.pinnedPosts ?? []
            return store.allClips.filter {
                $0.authorID == profile.id && (!preview || !$0.settings.onlyMe) &&
                (!atmosphere || store.active?.id == profile.id || !$0.settings.onlyMe)
            }.sorted {
                (pins.firstIndex(of: $0.id) ?? Int.max) < (pins.firstIndex(of: $1.id) ?? Int.max)
            }
        }
        guard !preview, store.active?.id == profile.id else { return [] }
        switch selectedSection {
        case .posts, .overview: return []
        case .saved: return store.feed(.saved)
        case .liked: return store.allClips.filter { store.liked($0) }
        case .comments: return store.allClips.filter { clip in store.comments(clip).contains { $0.authorID == profile.id } }
        }
    }

    func select(_ section: ProfileSection) {
        guard section != selectedSection, let profile = visibleProfile else { return }
        selectedSection = section
        onSectionChange?(section)
        clips = posts(for: profile)
        sectionIsland.select(section)
        layout.invalidateLayout()
        grid.reloadSections(atmosphere ? IndexSet([1, 2]) : IndexSet(integer: 0))
        updateSectionPosition()
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView {
        let view = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "hero",
                                                                   for: indexPath) as! ProfileHero
        guard let profile = visibleProfile else { return view }
        let follow = followState
        view.setCover(for: profile, width: collectionView.bounds.width, top: self.view.safeAreaInsets.top)
        view.show(profile, store: store, own: profile.id == store.active?.id && !preview, following: follow, onPeople: { [weak self] followers in
            guard let self else { return }; self.showChild(PeopleListController(store: self.store, profile: profile, followers: followers))
        }, onStudio: { [weak self] in
            guard let self else { return }; self.showChild(StudioController(store: self.store))
        }, onAvatar: { [weak self] in self?.openAvatar() }, onMessage: { [weak self] in
            guard let self else { return }
            self.navigationController?.pushViewController(ChatController(store: self.store, repository: self.repository, peer: profile), animated: true)
        }) { [weak self] in
            guard let self else { return }
            guard self.store.active != nil else { self.onAccount?(); return }
            guard self.followTask == nil else { return }
            let following = !self.store.follows(profile)
            self.followTask = Task { [weak self] in
                guard let self else { return }
                defer { self.followTask = nil }
                do {
                    try await self.repository.setFollowing(following, profileID: profile.id)
                    self.refresh()
                    self.onChange?()
                } catch { self.showMessage(error.localizedDescription) }
            }
        }
        return view
    }

    func scrollToPublications() {
        if atmosphere { select(.posts) }
        guard let profile = visibleProfile else { return }
        let pin = sectionPinTop ?? view.safeAreaInsets.top + 46
        grid.setContentOffset(CGPoint(x: 0, y: max(0, heroHeight(for: profile) - 50 - pin)), animated: !UIAccessibility.isReduceMotionEnabled)
    }

    private func showChild(_ child: UIViewController) {
        if let navigationController { navigationController.pushViewController(child, animated: true) }
        else {
            child.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak child] _ in child?.dismiss(animated: true) })
            present(UINavigationController(rootViewController: child), animated: true)
        }
    }

    private func openDashboard(_ destination: ProfileDashboardRow.Destination) {
        guard let profile = visibleProfile else { return }
        let own = !preview && store.active?.id == profile.id
        switch destination {
        case .settings:
            if own { showChild(SettingsController(store: store)) }
        case .appearance:
            if own { showChild(StudioController(store: store)) }
        case .library:
            if own { select(.saved) }
        case .community:
            showChild(PeopleListController(store: store, profile: profile, followers: true))
        case .about:
            let page = ActionListController("Про автора")
            page.rows = [StudioRow(title: profile.name, detail: profile.bio.isEmpty ? "@" + profile.handle : profile.bio, navigates: false, action: {})]
            showChild(page)
        case .statistics:
            let posts = store.allClips.filter { $0.authorID == profile.id && (own || !$0.settings.onlyMe) }
            let page = ActionListController("Статистика")
            page.rows = [
                StudioRow(title: "Публікації", detail: "\(posts.count)", navigates: false, action: {}),
                StudioRow(title: "Уподобання публікацій", detail: "\(posts.reduce(0) { $0 + store.likes($1) })", navigates: false, action: {}),
                StudioRow(title: "Підписники", detail: "\(store.people(followersOf: profile.id).count)", navigates: false, action: {})
            ]
            if own {
                page.rows.append(StudioRow(title: "Чернетки", detail: "\(store.drafts.count)", navigates: false, action: {}))
                page.rows.append(StudioRow(title: "Джерело даних", detail: "Локальні дані цього пристрою", navigates: false, action: {}))
            }
            showChild(page)
        }
    }

    private func configureBannerMenu() {
        guard !preview else { return }
        if let profileID, store.active?.id != profileID {
            navigationItem.rightBarButtonItem = UIBarButtonItem(image: AppSymbol.image("ellipsis"), menu: UIMenu(children: [UIAction(title: "Заблокувати", image: AppSymbol.image("person.slash"), attributes: .destructive) { [weak self] _ in
                self?.store.changeStudio { $0.preferences.blocked.insert(profileID) }; self?.navigationController?.popViewController(animated: true)
            }]))
            return
        }
        guard let profileID, store.active?.id == profileID else { return }
        let portrait = store.studio.appearance.theme == "atmosphere"
        var actions = [UIAction(title: portrait ? "Вибрати фото профілю" : "Вибрати фото або відео", image: AppSymbol.image( "photo.on.rectangle")) { [weak self] _ in
            self?.chooseBanner()
        }]
        if !portrait, store.active?.bannerURL != nil {
            actions.append(UIAction(title: "Прибрати банер", image: AppSymbol.image( "trash"), attributes: .destructive) { [weak self] _ in
                self?.removeBanner()
            })
        }
        let button = UIBarButtonItem(title: nil, image: AppSymbol.image( "photo.on.rectangle"),
                                     primaryAction: nil, menu: UIMenu(children: actions))
        button.accessibilityLabel = portrait ? "Змінити фото профілю" : "Змінити банер"
        navigationItem.leftItemsSupplementBackButton = true
        navigationItem.leftBarButtonItem = button
    }

    func chooseBanner() {
        guard let profile = store.active, profileID == nil || profile.id == profileID else { return }
        if store.studio.appearance.theme == "atmosphere" { openPortraitPicker(for: profile.id) }
        else { openBannerPicker(for: profile.id) }
    }

    func removeBanner() {
        guard let profile = store.active, profileID == nil || profile.id == profileID else { return }
        if store.setBanner(nil, extension: "", for: profile.id) {
            refresh()
            onChange?()
        } else { showStorageErrorIfNeeded() }
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

    private func openPortraitPicker(for id: UUID) {
        pickerOwner = id; pickerDestination = .portrait
        var configuration = PHPickerConfiguration()
        configuration.filter = .images; configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self; present(picker, animated: true)
    }

    private func openAvatar() {
        guard let profile = visibleProfile else { return }
        if store.state.studio?.accounts[profile.id.uuidString]?.appearance.theme == "atmosphere",
           !preview, store.active?.id == profile.id { openPortraitPicker(for: profile.id); return }
        let menu = AvatarMenuController(data: profile.avatar, editable: !preview && store.active?.id == profile.id)
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
                    guard let self, let owner = self.store.profile(id), self.store.active?.id == id,
                          let image = object as? UIImage, image.size.width > 0, image.size.height > 0 else {
                        self?.showMessage("Не вдалося відкрити фотографію.")
                        return
                    }
                    let height = destination == .portrait
                        ? AtmosphereProfile.photoHeight(owner, width: self.view.bounds.width, top: self.view.safeAreaInsets.top) + 100
                        : ProfileHero.bannerSize(width: self.view.bounds.width, top: self.view.safeAreaInsets.top) + 100
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
                        } else if destination == .portrait {
                            let edge = min(image.size.width, image.size.height)
                            let format = UIGraphicsImageRendererFormat(); format.scale = 1
                            let thumbnail = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512), format: format).image { _ in
                                image.draw(in: CGRect(x: (512 - image.size.width * 512 / edge) / 2,
                                                      y: (512 - image.size.height * 512 / edge) / 2,
                                                      width: image.size.width * 512 / edge, height: image.size.height * 512 / edge))
                            }
                            guard let avatar = thumbnail.jpegData(compressionQuality: 0.95) else { return }
                            if self.store.setPortrait(data, avatar: avatar, for: id) { self.refresh(); self.onChange?() }
                            else { self.showStorageErrorIfNeeded() }
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
            onChange?()
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
    private let content = UIStackView()
    private var cover: NSLayoutConstraint?
    private var appearance = CreatorAppearance()
    private var width: CGFloat = 390
    private var top: CGFloat = 0
    override init(frame: CGRect) {
        super.init(frame: frame)
        content.axis = .vertical; content.spacing = 12
        content.pin(to: self)
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
    static func coverSize(for profile: Profile, width: CGFloat, top: CGFloat, theme: String = "minimal") -> CGFloat {
        if theme == "atmosphere" { return AtmosphereProfile.photoHeight(profile, width: width, top: top) }
        return profile.bannerURL == nil ? top + 90 : max(top + 140, min(270, width * 0.62))
    }
    static func bannerSize(width: CGFloat, top: CGFloat) -> CGFloat { max(top + 140, min(270, width * 0.62)) }
    func setCover(for profile: Profile, width: CGFloat, top: CGFloat) {
        self.width = width; self.top = top
        cover?.constant = max(0, Self.coverSize(for: profile, width: width, top: top, theme: appearance.theme) - (appearance.theme == "atmosphere" ? 110 : 56))
    }
    static func height(for profile: Profile, width: CGFloat, top: CGFloat, showsFollow: Bool, appearance: CreatorAppearance = CreatorAppearance(), own: Bool = false) -> CGFloat {
        let stack = makeContent(profile, width: width, top: top, appearance: appearance, own: own, following: showsFollow ? false : nil,
                                counts: (0,0,0), onAvatar: {}, onPeople: { _ in }, onStudio: {}, onMessage: {}, onFollow: {}, onShare: {})
        return ceil(stack.systemLayoutSizeFitting(CGSize(width: width, height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height)
    }
    func show(_ profile: Profile, store: LocalStore, own: Bool, following: Bool?, onPeople: @escaping (Bool) -> Void, onStudio: @escaping () -> Void,
              onAvatar: @escaping () -> Void, onMessage: @escaping () -> Void, onFollow: @escaping () -> Void) {
        appearance = store.state.studio?.accounts[profile.id.uuidString]?.appearance ?? CreatorAppearance()
        content.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let counts = (store.allClips.filter { $0.authorID == profile.id }.count, store.people(followersOf: profile.id).count, store.people(followedBy: profile.id).count)
        let stack = Self.makeContent(profile, width: width, top: top, appearance: appearance, own: own, following: following, counts: counts,
            onAvatar: onAvatar, onPeople: onPeople, onStudio: onStudio, onMessage: onMessage, onFollow: onFollow, onShare: {
                guard let controller = self.nearestController else { return }
                controller.present(UIActivityViewController(activityItems: [URL(string: "kadr://profile/" + profile.handle)!], applicationActivities: nil), animated: true)
            })
        for child in Array(stack.arrangedSubviews) { child.removeFromSuperview(); content.addArrangedSubview(child) }
        cover = content.arrangedSubviews.first?.constraints.first { $0.firstAttribute == .height }
    }
    private static func makeContent(_ profile: Profile, width: CGFloat, top: CGFloat, appearance: CreatorAppearance, own: Bool, following: Bool?, counts: (Int,Int,Int),
                                    onAvatar: @escaping () -> Void, onPeople: @escaping (Bool) -> Void, onStudio: @escaping () -> Void,
                                    onMessage: @escaping () -> Void, onFollow: @escaping () -> Void, onShare: @escaping () -> Void) -> UIStackView {
        if appearance.theme == "atmosphere" {
            return AtmosphereProfile.header(profile, width: width, top: top, appearance: appearance, own: own,
                following: following, counts: counts, onPhoto: onAvatar, onPeople: onPeople,
                onStudio: onStudio, onMessage: onMessage, onFollow: onFollow, onShare: onShare)
        }
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 12
        let spacer = UIView(); spacer.heightAnchor.constraint(equalToConstant: max(0, coverSize(for: profile, width: width, top: top) - 56)).isActive = true
        stack.addArrangedSubview(spacer)
        let identity = UIStackView(); identity.axis = .vertical; identity.alignment = .center; identity.spacing = 8
        let avatar = avatarView(profile.avatar); avatar.layer.cornerRadius = 56; avatar.clipsToBounds = true
        avatar.widthAnchor.constraint(equalToConstant: 112).isActive = true; avatar.heightAnchor.constraint(equalToConstant: 112).isActive = true
        let avatarButton = UIButton(type: .custom); avatar.pin(to: avatarButton)
        avatarButton.accessibilityLabel = "Фото @" + profile.handle; avatarButton.addAction(UIAction { _ in onAvatar() }, for: .primaryActionTriggered)
        identity.addArrangedSubview(avatarButton)
        let name = makeLabel(appearance.theme == "cinema" ? .largeTitle : .title1, text: profile.name)
        name.font = name.font.withTraits(.traitBold); name.textAlignment = .center
        let handle = makeLabel(.headline, text: "@" + profile.handle, color: accent(appearance.accent)); handle.textAlignment = .center
        identity.addArrangedSubview(name); identity.addArrangedSubview(handle)
        if !profile.bio.isEmpty { let bio = makeLabel(.body, text: profile.bio, color: .secondaryLabel); bio.textAlignment = .center; identity.addArrangedSubview(bio) }
        let inset = UIView(); identity.pin(to: inset, insets: .init(top: 0, leading: 20, bottom: 0, trailing: 20)); stack.addArrangedSubview(inset)
        let stats = UIStackView(); stats.distribution = .fillEqually; stats.spacing = 8
        for (index, text) in ["Публікації", "Підписники", "Підписки"].enumerated() {
            var style = appearance.theme == "vivid" ? UIButton.Configuration.prominentGlass() : .glass()
            style.title = String([counts.0,counts.1,counts.2][index]); style.subtitle = text; style.baseForegroundColor = .label; style.baseBackgroundColor = accent(appearance.accent)
            let button = UIButton(configuration: style); button.heightAnchor.constraint(greaterThanOrEqualToConstant: 56).isActive = true
            button.addAction(UIAction { [weak button] _ in
                if index > 0 { onPeople(index == 1) }
                else { (button?.nearestController as? ProfileController)?.scrollToPublications() }
            }, for: .primaryActionTriggered)
            stats.addArrangedSubview(button)
        }
        let statInset = UIView(); stats.pin(to: statInset, insets: .init(top: 0, leading: 16, bottom: 0, trailing: 16)); stack.addArrangedSubview(statInset)
        if !appearance.introduction.isEmpty {
            let card = glassIsland(style: .clear, interactive: false); let text = makeLabel(.body, text: appearance.introduction)
            text.pin(to: card.contentView, insets: .init(top: 16, leading: 20, bottom: 16, trailing: 20)); stack.addArrangedSubview(card)
        }
        for link in appearance.links {
            let button = textButton(link, symbol: "link") { if let url = URL(string: link), url.scheme == "https" { UIApplication.shared.open(url) } }
            stack.addArrangedSubview(button)
        }
        let actions = UIStackView(); actions.distribution = .fillEqually; actions.spacing = 8
        if let following {
            actions.addArrangedSubview(textButton(following ? "Відписатися" : "Підписатися", prominent: !following, action: onFollow))
            if following { actions.addArrangedSubview(textButton("Повідомлення", symbol: "bubble.left", action: onMessage)) }
        }
        if own { actions.addArrangedSubview(textButton("Студія", symbol: "slider.horizontal.3", action: onStudio)) }
        actions.addArrangedSubview(textButton("Поділитися", symbol: "square.and.arrow.up", action: onShare))
        let actionInset = UIView(); actions.pin(to: actionInset, insets: .init(top: 0, leading: 16, bottom: 0, trailing: 16)); stack.addArrangedSubview(actionInset)
        let footer = UIView(); footer.heightAnchor.constraint(equalToConstant: 48).isActive = true; stack.addArrangedSubview(footer)
        return stack
    }
    private static func accent(_ value: String) -> UIColor {
        switch value { case "mint": return .systemMint; case "violet": return .systemPurple; case "blue": return .systemBlue; case "rose": return .systemPink; default: return .kadrPeach }
    }
}

private extension UIView {
    var nearestController: UIViewController? {
        var candidate: UIResponder? = self
        while let next = candidate?.next { if let controller = next as? UIViewController { return controller }; candidate = next }
        return nil
    }
}

private final class ProfileBackdrop: UIView {
    var onPalette: ((UIColor) -> Void)?
    private let artwork = UIImageView()
    private let blurredBackdrop = UIImageView()
    private let blurMask = CAGradientLayer()
    private let edgeMask = CAGradientLayer()
    private let video = VideoSurface(frame: .zero)
    private let shade = GradientView()
    private var isVideo = false
    private var scrollOffset: CGFloat = 0
    private var mediaHeight: CGFloat = 260
    private var artworkTask: Task<Void, Never>?
    private var artworkRevision = UUID()
    private var portrait = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true
        edgeMask.colors = [1, 1, 0.98, 0.88, 0.62, 0.22, 0].map { UIColor.black.withAlphaComponent(CGFloat($0)).cgColor }
        edgeMask.locations = [0, 0.56, 0.66, 0.76, 0.85, 0.94, 1]
        artwork.contentMode = .scaleAspectFill
        artwork.clipsToBounds = true
        addSubview(artwork)
        addSubview(video)
        blurredBackdrop.contentMode = .scaleAspectFill; blurredBackdrop.clipsToBounds = true
        blurMask.colors = [UIColor.clear.cgColor, UIColor.clear.cgColor,
                           UIColor.black.withAlphaComponent(0.25).cgColor, UIColor.black.cgColor, UIColor.black.cgColor]
        blurMask.locations = [0, 0.50, 0.59, 0.72, 1]
        blurredBackdrop.layer.mask = blurMask; addSubview(blurredBackdrop)
        let background = UIColor.systemBackground.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        let alphas: [CGFloat] = [0, 0, 0.03, 0.10, 0.22, 0.38, 0.56, 0.73, 0.87, 0.96, 1]
        shade.gradient.colors = alphas.map { background.withAlphaComponent($0).cgColor }
        shade.gradient.locations = [0, 0.33, 0.43, 0.51, 0.59, 0.67, 0.74, 0.81, 0.88, 0.94, 1]
        addSubview(shade)
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    func setScroll(offset: CGFloat, mediaHeight: CGFloat) {
        guard scrollOffset != offset || self.mediaHeight != mediaHeight else { return }
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
        let backdropY = -max(0, scrollOffset)
        blurredBackdrop.frame = artwork.frame
        CATransaction.begin(); CATransaction.setDisableActions(true)
        blurMask.frame = CGRect(x: 0, y: backdropY - (portrait ? 3 : 0), width: bounds.width, height: height)
        edgeMask.frame = CGRect(x: 0, y: backdropY, width: bounds.width, height: height)
        CATransaction.commit()
        shade.frame = CGRect(x: 0, y: backdropY, width: bounds.width, height: height)
    }

    func show(_ profile: Profile?, start: Double = 0, theme: String = "minimal") {
        artworkTask?.cancel(); artworkRevision = UUID(); let revision = artworkRevision
        let portrait = theme == "atmosphere"
        self.portrait = portrait
        layer.mask = portrait ? edgeMask : nil
        let url = portrait ? profile?.portraitFile.map { LocalStore.directory.appendingPathComponent($0) } : profile?.bannerURL
        isVideo = !portrait && url.flatMap { UTType(filenameExtension: $0.pathExtension) }?.conforms(to: .movie) == true
        artwork.image = nil
        blurredBackdrop.image = nil; blurredBackdrop.isHidden = !portrait
        updateShade(color: portrait ? UIColor(white: 0.16, alpha: 1) : .systemBackground, portrait: portrait)
        if !isVideo {
            let fallback = portrait ? profile?.avatar : nil
            artworkTask = Task { [weak self] in
                let image: UIImage?
                if let url {
                    let loaded = await PhotoLoader.image(url, maxPixel: 1920)
                    if loaded == nil, let fallback { image = await Task.detached { UIImage(data: fallback) }.value }
                    else { image = loaded }
                }
                else if let fallback { image = await Task.detached { UIImage(data: fallback) }.value }
                else { image = nil }
                guard !Task.isCancelled, let self, self.artworkRevision == revision else { return }
                self.artwork.image = image
                if portrait, let image {
                    ProfilePhotoRenderer.render(image) { [weak self] rendered, color in
                        guard let self, self.artworkRevision == revision else { return }
                        if let rendered { self.blurredBackdrop.image = rendered }
                        self.updateShade(color: color, portrait: true)
                        self.onPalette?(color)
                    }
                }
            }
        }
        video.isHidden = !isVideo; video.load(isVideo ? url : nil)
        if isVideo { video.seek(to: max(0, start)) }
        setNeedsLayout()
    }

    func setPlaying(_ playing: Bool) { video.setPlaying(playing && isVideo, muted: true) }

    private func updateShade(color: UIColor, portrait: Bool) {
        let background = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        let alphas: [CGFloat] = portrait ? [0, 0, 0.015, 0.06, 0.16, 0.32, 0.52, 0.72, 0.88, 0.97, 1] : [0, 0, 0.03, 0.10, 0.22, 0.38, 0.56, 0.73, 0.87, 0.96, 1]
        CATransaction.begin(); CATransaction.setDisableActions(true)
        shade.gradient.colors = alphas.map { background.withAlphaComponent($0).cgColor }
        shade.gradient.locations = portrait ? [0, 0.46, 0.54, 0.60, 0.66, 0.72, 0.78, 0.84, 0.90, 0.96, 1] : [0, 0.33, 0.43, 0.51, 0.59, 0.67, 0.74, 0.81, 0.88, 0.94, 1]
        CATransaction.commit()
    }
}

private final class ClipThumbnailCell: UICollectionViewCell {
    private let image = UIImageView()
    private let play = UIImageView(image: AppSymbol.image( "play.fill"))
    private let caption = UILabel()
    private let albumCount = UILabel()
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
        caption.font = .preferredFont(forTextStyle: .caption1); caption.textColor = .white
        caption.layer.shadowColor = UIColor.black.cgColor; caption.layer.shadowOpacity = 0.8; caption.layer.shadowRadius = 3
        caption.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview(caption)
        albumCount.font = .preferredFont(forTextStyle: .caption2); albumCount.textColor = .white
        albumCount.textAlignment = .center; albumCount.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        albumCount.layer.cornerRadius = 10; albumCount.clipsToBounds = true
        albumCount.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview(albumCount)
        NSLayoutConstraint.activate([
            caption.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            caption.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            caption.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            albumCount.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            albumCount.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            albumCount.widthAnchor.constraint(greaterThanOrEqualToConstant: 28),
            albumCount.heightAnchor.constraint(equalToConstant: 22)
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

    func show(_ clip: Clip, modern: Bool = false) {
        task?.cancel()
        caption.isHidden = !modern; caption.text = clip.caption
        let count = clip.media?.count ?? 1
        albumCount.isHidden = !modern || count < 2; albumCount.text = " \(count) "
        representedID = clip.id
        accessibilityLabel = (clip.isPhoto ? "Фото. " : "Відео. ") + (clip.caption.isEmpty ? "Публікація" : clip.caption)
        image.image = nil
        play.image = AppSymbol.image( clip.isPhoto ? "square.on.square" : "play.fill")
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
            guard let poster = await VideoPoster.image(for: url, at: clip.extras?.coverTime ?? 0.5), !Task.isCancelled,
                  let self, self.representedID == clip.id else { return }
            self.image.image = UIImage(cgImage: poster)
        }
    }
}
