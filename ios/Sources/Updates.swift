import UIKit

struct UpdateEntry: Decodable {
    struct Section: Decodable { let title: String; let detail: String }
    let version: String
    let title: String
    let summary: [String]
    let sections: [Section]
}
enum AppUpdates {
    static let entries: [UpdateEntry] = {
        guard let url = Bundle.main.url(forResource: "Updates", withExtension: "json"),
              let data = try? Data(contentsOf: url), let entries = try? JSONDecoder().decode([UpdateEntry].self, from: data) else { return [] }
        return entries
    }()
    static var current: UpdateEntry {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        return entries.first { $0.version == version } ?? UpdateEntry(version: version, title: "Оновлення Кадру", summary: ["Встановлена нова версія застосунку."], sections: [])
    }
}

final class UpdatesController: UITableViewController {
    init() { super.init(style: .insetGrouped); title = "Оновлення" }
    required init?(coder: NSCoder) { fatalError("Use init()") }
    override func viewDidLoad() {
        super.viewDidLoad(); tableView.topEdgeEffect.style = .soft; tableView.bottomEdgeEffect.style = .soft
        tableView.rowHeight = UITableView.automaticDimension; tableView.estimatedRowHeight = 140
        tableView.allowsSelection = false
    }
    override func numberOfSections(in tableView: UITableView) -> Int { AppUpdates.entries.count }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { AppUpdates.entries[section].sections.count }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let entry = AppUpdates.entries[section]; return entry.version + " · " + entry.title
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section = AppUpdates.entries[indexPath.section].sections[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "release") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "release")
        var content = cell.defaultContentConfiguration(); content.text = section.title; content.secondaryText = section.detail
        content.textProperties.numberOfLines = 0; content.secondaryTextProperties.numberOfLines = 0
        content.image = AppSymbol.image("sparkles"); content.imageProperties.tintColor = .kadrPeach
        cell.contentConfiguration = content; return cell
    }
}

@MainActor final class UpdateAnnouncementCoordinator {
    private weak var window: UIWindow?
    private let store: LocalStore
    private var task: Task<Void, Never>?
    private var observer: NSObjectProtocol?
    init(window: UIWindow, store: LocalStore) {
        self.window = window; self.store = store
        observer = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.schedule() } }
        schedule()
    }
    private func schedule() {
        let key = AppUpdates.current.version + ":" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "")
        guard UserDefaults.standard.string(forKey: "lastPresentedUpdate") != key, task == nil else { return }
        task = Task { [weak self] in
            defer { self?.task = nil }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(700)) } catch { return }
                guard let self, let root = self.window?.rootViewController else { return }
                guard UIApplication.shared.applicationState == .active else { return }
                var presenter = root
                while let presented = presenter.presentedViewController { presenter = presented }
                guard presenter.viewIfLoaded?.window != nil, !presenter.isBeingPresented, !presenter.isBeingDismissed,
                      !(presenter is UIAlertController), presenter.transitionCoordinator == nil else { continue }
                let entry = AppUpdates.current
                let alert = UIAlertController(title: "Що нового · " + entry.version, message: entry.summary.map { "• " + $0 }.joined(separator: "\n\n"), preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Продовжити", style: .cancel))
                alert.addAction(UIAlertAction(title: "Налаштування → Оновлення", style: .default) { [weak self, weak presenter] _ in
                    guard let self, let presenter else { return }
                    let settings = SettingsController(store: self.store)
                    let navigation = UINavigationController(rootViewController: settings)
                    navigation.pushViewController(UpdatesController(), animated: false)
                    settings.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak navigation] _ in navigation?.dismiss(animated: true) })
                    presenter.present(navigation, animated: true)
                })
                presenter.present(alert, animated: true) { UserDefaults.standard.set(key, forKey: "lastPresentedUpdate") }
                return
            }
        }
    }
    deinit { task?.cancel(); if let observer { NotificationCenter.default.removeObserver(observer) } }
}
