import UIKit

final class SavedController: UITableViewController {
    private let store: LocalStore
    private var clips: [Clip] = []
    var onClip: ((Clip) -> Void)?
    var onAccount: (() -> Void)?

    init(store: LocalStore) {
        self.store = store
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("Use init(store:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityIdentifier = "saved.screen"
        refresh()
    }

    func refresh() {
        guard isViewLoaded else { return }
        clips = store.feed(.saved)
        if clips.isEmpty {
            let guest = store.active == nil
            var empty = UIContentUnavailableConfiguration.empty()
            empty.image = UIImage(systemName: "bookmark")
            empty.text = guest ? "Збережені відео" : "Немає збережених відео"
            empty.secondaryText = guest ? "Увійди, щоб зберігати відео на цьому пристрої."
                                        : "Натисни закладку під відео, щоб додати його сюди."
            if guest {
                empty.button.title = "Увійти або створити акаунт"
                empty.buttonProperties.primaryAction = UIAction { [weak self] _ in self?.onAccount?() }
            }
            contentUnavailableConfiguration = empty
        } else {
            contentUnavailableConfiguration = nil
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

final class ProfileController: UITableViewController {
    private let store: LocalStore
    private let profileID: UUID?
    private var clips: [Clip] = []
    private var visibleProfileID: UUID?
    private var follows: Bool?
    private var header: UIView?
    var onClip: ((Clip) -> Void)?
    var onAccount: (() -> Void)?
    var onChange: (() -> Void)?

    init(store: LocalStore, profileID: UUID?) {
        self.store = store
        self.profileID = profileID
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("Use init(store:profileID:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityIdentifier = "profile.screen"
        refresh()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        sizeHeader()
    }

    func refresh() {
        guard isViewLoaded else { return }
        let profile = profileID.flatMap { store.profile($0) } ?? (profileID == nil ? store.active : nil)
        guard let profile else {
            visibleProfileID = nil
            follows = nil
            clips = []
            header = nil
            tableView.tableHeaderView = nil
            var empty = UIContentUnavailableConfiguration.empty()
            empty.image = UIImage(systemName: "person.crop.circle")
            empty.text = "Твій профіль"
            empty.secondaryText = "Створи акаунт, щоб додати фото, нікнейм і власні відео."
            empty.button.title = "Увійти або створити акаунт"
            empty.buttonProperties.primaryAction = UIAction { [weak self] _ in self?.onAccount?() }
            contentUnavailableConfiguration = empty
            tableView.reloadData()
            return
        }
        title = profileID == nil ? "Профіль" : "@\(profile.handle)"
        contentUnavailableConfiguration = nil
        clips = store.allClips.filter { $0.authorID == profile.id }
        let canFollow = store.active != nil && store.active?.id != profile.id
        let following = canFollow ? store.follows(profile) : nil
        if profile.id != visibleProfileID || following != follows {
            visibleProfileID = profile.id
            follows = following
            header = makeHeader(profile, following: following)
            sizeHeader()
        }
        tableView.reloadData()
    }

    private func makeHeader(_ profile: Profile, following: Bool?) -> UIView {
        let container = UIView()
        let banner = GradientView()
        banner.gradient.colors = [UIColor.kadrPeach.cgColor, UIColor.systemIndigo.cgColor, UIColor.black.cgColor]
        banner.gradient.startPoint = CGPoint(x: 0, y: 0)
        banner.gradient.endPoint = CGPoint(x: 1, y: 1)
        banner.layer.cornerRadius = 24
        banner.clipsToBounds = true
        banner.heightAnchor.constraint(equalToConstant: 144).isActive = true

        let avatar = avatarView(profile.avatar)
        avatar.translatesAutoresizingMaskIntoConstraints = false
        avatar.backgroundColor = .systemBackground
        avatar.layer.cornerRadius = 35
        avatar.layer.borderWidth = 2
        avatar.layer.borderColor = UIColor.white.withAlphaComponent(0.65).cgColor
        banner.addSubview(avatar)
        NSLayoutConstraint.activate([
            avatar.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 14),
            avatar.bottomAnchor.constraint(equalTo: banner.bottomAnchor, constant: -14),
            avatar.widthAnchor.constraint(equalToConstant: 70),
            avatar.heightAnchor.constraint(equalTo: avatar.widthAnchor)
        ])

        let name = makeLabel(.title1, text: profile.name)
        name.font = name.font.withTraits(.traitBold)
        let stack = UIStackView(arrangedSubviews: [banner, name, makeLabel(.subheadline, text: "@\(profile.handle)", color: .secondaryLabel)])
        stack.axis = .vertical
        stack.spacing = 8
        if !profile.bio.isEmpty { stack.addArrangedSubview(makeLabel(.body, text: profile.bio)) }
        if let following {
            stack.addArrangedSubview(textButton(following ? "Відписатися" : "Підписатися", prominent: !following) { [weak self] in
                guard let self else { return }
                self.store.toggleFollow(profile)
                if let error = self.store.errorMessage {
                    self.store.errorMessage = nil
                    self.showMessage(error)
                } else {
                    self.refresh()
                    self.onChange?()
                }
            })
        }
        stack.pin(to: container, insets: NSDirectionalEdgeInsets(top: 10, leading: 20, bottom: 12, trailing: 20))
        return container
    }

    private func sizeHeader() {
        guard let header, tableView.bounds.width > 0 else { return }
        let width = tableView.bounds.width
        let height = ceil(header.systemLayoutSizeFitting(CGSize(width: width, height: 0),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height)
        if tableView.tableHeaderView !== header || header.frame.size != CGSize(width: width, height: height) {
            header.frame = CGRect(x: 0, y: 0, width: width, height: height)
            tableView.tableHeaderView = header
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        visibleProfileID == nil ? nil : "Публікації"
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        visibleProfileID == nil ? 0 : max(1, clips.count)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if clips.isEmpty {
            let cell = UITableViewCell()
            var configuration = cell.defaultContentConfiguration()
            configuration.text = "Поки немає відео"
            configuration.textProperties.color = .secondaryLabel
            cell.contentConfiguration = configuration
            cell.selectionStyle = .none
            return cell
        }
        return clipCell(in: tableView, clip: clips[indexPath.row], store: store)
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if clips.indices.contains(indexPath.row) { onClip?(clips[indexPath.row]) }
    }
}

final class SearchController: UITableViewController, UISearchResultsUpdating {
    private let store: LocalStore
    private var matches: [Profile] = []
    var onChange: (() -> Void)?
    var onClip: ((Clip) -> Void)?

    init(store: LocalStore) {
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
        matches = store.profiles.filter { term.isEmpty || $0.handle.hasPrefix(term) }.sorted { $0.handle < $1.handle }
        if matches.isEmpty {
            var empty = UIContentUnavailableConfiguration.search()
            empty.text = "Немає профілів"
            contentUnavailableConfiguration = empty
        } else {
            contentUnavailableConfiguration = nil
        }
        tableView.reloadData()
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
        let profile = ProfileController(store: store, profileID: matches[indexPath.row].id)
        profile.onClip = onClip
        profile.onChange = onChange
        navigationController?.pushViewController(profile, animated: true)
    }
}

private func clipCell(in table: UITableView, clip: Clip, store: LocalStore) -> UITableViewCell {
    let cell = table.dequeueReusableCell(withIdentifier: "clip") ??
        UITableViewCell(style: .default, reuseIdentifier: "clip")
    var configuration = cell.defaultContentConfiguration()
    configuration.image = UIImage(systemName: "play.rectangle.fill")
    configuration.imageProperties.tintColor = .kadrPeach
    configuration.text = clip.caption
    configuration.secondaryText = store.profile(clip.authorID).map { "@\($0.handle)" } ?? clip.credit
    cell.contentConfiguration = configuration
    cell.accessoryType = .disclosureIndicator
    return cell
}
