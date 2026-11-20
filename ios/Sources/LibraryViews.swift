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

final class SearchController: UITableViewController, UISearchResultsUpdating {
    private let store: LocalStore
    private let repository: any SocialRepository
    private var searchTask: Task<Void, Never>?
    var onAccount: (() -> Void)?
    private var matches: [Profile] = []
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
        title = "Пошук профілів"
        let search = UISearchController()
        search.searchBar.placeholder = "@нікнейм"
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.autocapitalizationType = .none
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
        updateSearchResults(for: search)
    }

    func updateSearchResults(for searchController: UISearchController) {
        let term = (searchController.searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .milliseconds(180))
                let matches = try await self.repository.search(handle: term)
                guard !Task.isCancelled else { return }
                self.matches = matches
                if matches.isEmpty {
                    var empty = UIContentUnavailableConfiguration.search()
                    empty.text = "Немає профілів"
                    self.contentUnavailableConfiguration = empty
                } else { self.contentUnavailableConfiguration = nil }
                self.tableView.reloadData()
            } catch is CancellationError { }
            catch { self.showMessage(error.localizedDescription) }
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { matches.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let profile = matches[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "profile") ??
            UITableViewCell(style: .default, reuseIdentifier: "profile")
        var configuration = cell.defaultContentConfiguration()
        configuration.text = profile.name
        configuration.secondaryText = "@\(profile.handle)"
        configuration.image = profile.avatar.flatMap { UIImage(data: $0) } ?? UIImage(systemName: "person.crop.circle.fill")
        configuration.imageProperties.maximumSize = CGSize(width: 40, height: 40)
        configuration.imageProperties.cornerRadius = 20
        configuration.imageProperties.tintColor = .kadrPeach
        cell.contentConfiguration = configuration
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let profile = ProfileController(store: store, profileID: matches[indexPath.row].id, repository: repository)
        profile.onClip = onClip
        profile.onAccount = onAccount
        profile.onChange = onChange
        navigationController?.pushViewController(profile, animated: true)
    }
}

private func clipCell(in table: UITableView, clip: Clip, store: LocalStore) -> UITableViewCell {
    let cell = table.dequeueReusableCell(withIdentifier: "clip") ??
        UITableViewCell(style: .default, reuseIdentifier: "clip")
    var configuration = cell.defaultContentConfiguration()
    configuration.image = UIImage(systemName: clip.isPhoto ? "photo.on.rectangle" : "play.rectangle.fill")
    configuration.imageProperties.tintColor = .kadrPeach
    configuration.text = clip.caption
    configuration.secondaryText = store.profile(clip.authorID).map { "@\($0.handle)" } ?? clip.credit
    cell.contentConfiguration = configuration
    cell.accessoryType = .disclosureIndicator
    return cell
}
