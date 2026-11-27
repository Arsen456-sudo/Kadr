import UIKit

class LibraryController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var emptyView: EmptyStateView?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        tableView.dataSource = self
        tableView.delegate = self
        tableView.pin(to: view)
    }

    func showEmpty(_ empty: EmptyStateView?) {
        emptyView?.removeFromSuperview()
        emptyView = empty
        empty?.pin(to: view)
        tableView.isHidden = empty != nil
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 0 }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell { UITableViewCell() }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {}
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { nil }
}

final class SavedController: LibraryController {
    private let store: LocalStore
    private var clips: [Clip] = []
    var onClip: ((Clip) -> Void)?
    var onAccount: (() -> Void)?

    init(store: LocalStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Use init(store:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.accessibilityIdentifier = "saved.screen"
        refresh()
    }

    func refresh() {
        guard isViewLoaded else { return }
        clips = store.feed(.saved)
        if clips.isEmpty {
            let guest = store.active == nil
            let action = guest ? textButton("Увійти або створити акаунт") { [weak self] in self?.onAccount?() } : nil
            showEmpty(EmptyStateView(title: guest ? "Збережені відео" : "Немає збережених відео",
                message: guest ? "Увійди, щоб зберігати відео на цьому пристрої."
                               : "Натисни закладку під відео, щоб додати його сюди.",
                symbol: "bookmark", action: action))
        } else {
            showEmpty(nil)
        }
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { clips.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        clipCell(in: tableView, clip: clips[indexPath.row], store: store)
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        onClip?(clips[indexPath.row])
    }
}

final class SearchController: UITableViewController, UISearchResultsUpdating, UISearchBarDelegate {
    private let store: LocalStore
    private let repository: any SocialRepository
    private var searchTask: Task<Void, Never>?
    var onAccount: (() -> Void)?
    private var matches: [Profile] = []
    private var posts: [Clip] = []
    private var term = ""
    private var filter = 0
    private var tags: [String] = []
    var onChange: (() -> Void)?
    var onClip: ((Clip) -> Void)?

    init(store: LocalStore, repository: any SocialRepository) {
        self.repository = repository
        self.store = store
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("Use init(store:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Пошук"
        let search = UISearchController()
        search.searchBar.placeholder = "Люди, публікації та #теги"
        search.searchBar.delegate = self
        search.searchBar.scopeButtonTitles = ["Усе", "Люди", "Публікації"]
        search.scopeBarActivation = .always
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.autocapitalizationType = .none
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
        tableView.keyboardDismissMode = .onDrag
        tableView.topEdgeEffect.style = .soft
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: AppSymbol.image("clock.arrow.circlepath"), menu: UIMenu(children: [UIAction(title: "Очистити історію", image: AppSymbol.image("trash"), attributes: .destructive) { [weak self] _ in
            self?.store.changeStudio { $0.searches.removeAll() }; self?.tableView.reloadData()
        }]))
        updateSearchResults(for: search)
    }

    func updateSearchResults(for searchController: UISearchController) {
        let term = (searchController.searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "@#"))
        self.term = term
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .milliseconds(180))
                let matches = try await self.repository.search(handle: term)
                guard !Task.isCancelled else { return }
                let interests = Set(self.store.studio.appearance.interests)
                self.matches = matches.sorted { a, b in
                    let first = Set(self.store.state.studio?.accounts[a.id.uuidString]?.appearance.interests ?? []).intersection(interests).count
                    let second = Set(self.store.state.studio?.accounts[b.id.uuidString]?.appearance.interests ?? []).intersection(interests).count
                    return first != second ? first > second : a.handle < b.handle
                }
                let preferences = self.store.studio.preferences
                self.matches.removeAll { preferences.blocked.contains($0.id) }
                self.posts = self.store.allClips.filter { clip in
                    (!clip.settings.onlyMe || clip.authorID == self.store.active?.id) &&
                    !(clip.authorID.map { preferences.blocked.contains($0) || preferences.hiddenAuthors.contains($0) } ?? false) && !preferences.hiddenPosts.contains(clip.id) &&
                    !preferences.mutedWords.contains { !$0.isEmpty && clip.caption.localizedCaseInsensitiveContains($0) } &&
                    (term.isEmpty || clip.caption.localizedCaseInsensitiveContains(term) || clip.settings.tags.localizedCaseInsensitiveContains(term) || self.store.profile(clip.authorID)?.handle.localizedCaseInsensitiveContains(term) == true)
                }
                self.tags = Array(Set(self.posts.flatMap { $0.settings.tags.components(separatedBy: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
                self.contentUnavailableConfiguration = nil
                if matches.isEmpty && self.posts.isEmpty && self.store.studio.searches.isEmpty {
                    var empty = UIContentUnavailableConfiguration.search()
                    empty.text = "Нічого не знайдено"
                    empty.secondaryText = "Спробуй інше імʼя, опис або #тег."
                    self.contentUnavailableConfiguration = empty
                } else { self.contentUnavailableConfiguration = nil }
                self.tableView.reloadData()
            } catch is CancellationError { }
            catch { self.showMessage(error.localizedDescription) }
        }
    }

    func searchBar(_ searchBar: UISearchBar, selectedScopeButtonIndexDidChange selectedScope: Int) { filter = selectedScope; tableView.reloadData() }
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        rememberQuery(); searchBar.resignFirstResponder()
    }
    private func rememberQuery() {
        guard !term.isEmpty else { return }
        store.changeStudio { account in account.searches.removeAll { $0 == term }; account.searches.insert(term, at: 0); account.searches = Array(account.searches.prefix(30)) }
    }
    override func numberOfSections(in tableView: UITableView) -> Int { 4 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 { return filter == 2 ? 0 : matches.count }
        if section == 1 { return filter == 1 ? 0 : (posts.count + 1) / 2 }
        if section == 2 { return term.isEmpty ? store.studio.searches.count : 0 }
        return term.isEmpty ? min(tags.count, 6) : 0
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if self.tableView(tableView, numberOfRowsInSection: section) == 0 { return nil }
        return ["Автори", "Фото та відео", "Недавні запити", "Теми у кадрах"][section]
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 1 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "media-pair") as? SearchMediaPairCell ?? SearchMediaPairCell(style: .default, reuseIdentifier: "media-pair")
            let start = indexPath.row * 2
            cell.show(Array(posts[start..<min(start + 2, posts.count)])) { [weak self] clip in self?.openPost(clip) }
            return cell
        }
        if indexPath.section == 3 {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = tags[indexPath.row]; cell.imageView?.image = AppSymbol.image("number"); cell.accessoryType = .disclosureIndicator; return cell
        }
        if indexPath.section == 2 {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil); cell.textLabel?.text = store.studio.searches[indexPath.row]; cell.imageView?.image = AppSymbol.image("clock"); return cell
        }
        let profile = matches[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "profile") ??
            UITableViewCell(style: .default, reuseIdentifier: "profile")
        var configuration = cell.defaultContentConfiguration()
        configuration.text = profile.name
        configuration.secondaryText = "@\(profile.handle)"
        configuration.image = profile.avatar.flatMap { UIImage(data: $0) } ?? AppSymbol.image( "person.crop.circle.fill")
        configuration.imageProperties.maximumSize = CGSize(width: 40, height: 40)
        configuration.imageProperties.cornerRadius = 20
        configuration.imageProperties.tintColor = .kadrPeach
        cell.contentConfiguration = configuration
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 3 {
            navigationItem.searchController?.searchBar.text = tags[indexPath.row]
            if let search = navigationItem.searchController { updateSearchResults(for: search) }; return
        }
        if indexPath.section == 2 {
            navigationItem.searchController?.searchBar.text = store.studio.searches[indexPath.row]
            if let search = navigationItem.searchController { updateSearchResults(for: search) }; return
        }
        if !term.isEmpty { store.changeStudio { account in account.searches.removeAll { $0 == term }; account.searches.insert(term, at: 0); account.searches = Array(account.searches.prefix(30)) } }
        if indexPath.section == 1 {
            return
        }
        let profile = ProfileController(store: store, profileID: matches[indexPath.row].id, repository: repository)
        profile.onClip = onClip
        profile.onAccount = onAccount
        profile.onChange = onChange
        navigationController?.pushViewController(profile, animated: true)
    }
    private func openPost(_ clip: Clip) {
        rememberQuery()
        if let onClip { onClip(clip) } else { navigationController?.pushViewController(ClipPreviewController(clip: clip, store: store), animated: true) }
    }
    deinit { searchTask?.cancel() }
    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard indexPath.section == 2 else { return nil }
        let term = store.studio.searches[indexPath.row]
        return UISwipeActionsConfiguration(actions: [UIContextualAction(style: .destructive, title: "Видалити") { [weak self] _, _, done in
            self?.store.changeStudio { $0.searches.removeAll { $0 == term } }; self?.tableView.reloadData(); done(true)
        }])
    }

}

private func clipCell(in table: UITableView, clip: Clip, store: LocalStore) -> UITableViewCell {
    let cell = table.dequeueReusableCell(withIdentifier: "clip") ??
        UITableViewCell(style: .default, reuseIdentifier: "clip")
    var configuration = cell.defaultContentConfiguration()
    configuration.image = AppSymbol.image( clip.isPhoto ? "photo.on.rectangle" : "play.rectangle.fill")
    configuration.imageProperties.tintColor = .kadrPeach
    configuration.text = clip.caption
    configuration.secondaryText = store.profile(clip.authorID).map { "@\($0.handle)" } ?? clip.credit
    cell.contentConfiguration = configuration
    cell.accessoryType = .disclosureIndicator
    return cell
}
