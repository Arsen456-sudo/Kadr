import UIKit

final class PeopleListController: ActionListController, UISearchResultsUpdating {
    private let store: LocalStore
    private let profile: Profile
    private let followers: Bool
    private var query = ""
    init(store: LocalStore, profile: Profile, followers: Bool) {
        self.store = store; self.profile = profile; self.followers = followers
        super.init(followers ? "Підписники" : "Підписки")
    }
    required init?(coder: NSCoder) { fatalError("Use init(store:profile:followers:)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        let search = UISearchController(); search.searchResultsUpdater = self; search.obscuresBackgroundDuringPresentation = false; navigationItem.searchController = search
        reloadRows = { [weak self] in
            guard let self else { return [] }
            let people = self.followers ? self.store.people(followersOf: self.profile.id) : self.store.people(followedBy: self.profile.id)
            return people.filter { self.query.isEmpty || $0.handle.localizedCaseInsensitiveContains(self.query) || $0.name.localizedCaseInsensitiveContains(self.query) }.map { person in
                StudioRow(title: person.name, detail: "@" + person.handle, icon: "person.crop.circle", action: {
                    self.push(ProfileController(store: self.store, profileID: person.id))
                })
            }
        }
    }
    func updateSearchResults(for searchController: UISearchController) { query = searchController.searchBar.text ?? ""; reload() }
}

final class InterestPickerController: ActionListController {
    private let store: LocalStore
    var onComplete: (() -> Void)?
    init(store: LocalStore) { self.store = store; super.init("Що тобі цікаво?") }
    required init?(coder: NSCoder) { fatalError("Use init(store:)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Готово", primaryAction: UIAction { [weak self] _ in self?.onComplete?() })
        let tags = ["подорожі", "музика", "спорт", "кіно", "мистецтво", "технології", "природа", "їжа", "ігри", "гумор"]
        reloadRows = { [weak self] in
            guard let self else { return [] }
            return tags.map { tag in StudioRow(title: (self.store.studio.appearance.interests.contains(tag) ? "✓ " : "") + tag, icon: "number", action: {
                self.store.changeStudio { account in
                    if account.appearance.interests.contains(tag) { account.appearance.interests.removeAll { $0 == tag }; account.preferences.preferredTags.remove(tag) }
                    else { account.appearance.interests.append(tag); account.preferences.preferredTags.insert(tag) }
                }; self.reload()
            }) }
        }
    }
}
