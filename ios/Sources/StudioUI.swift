import UIKit
import PhotosUI
import UniformTypeIdentifiers
import AVKit
import CoreImage.CIFilterBuiltins

struct StudioRow {
    var title: String
    var detail: String = ""
    var icon: String = "chevron.right"
    var thumbnail: URL? = nil
    var videoThumbnail = false
    var action: () -> Void
}

class ActionListController: UITableViewController {
    var rows: [StudioRow] = []
    var reloadRows: (() -> [StudioRow])?
    init(_ title: String) { super.init(style: .insetGrouped); self.title = title }
    required init?(coder: NSCoder) { fatalError("Use init(title:)") }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }
    func reload() { if let reloadRows { rows = reloadRows() }; tableView.reloadData() }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = rows[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "action") as? StudioActionCell ?? StudioActionCell(style: .subtitle, reuseIdentifier: "action")
        var content = cell.defaultContentConfiguration()
        content.text = row.title
        content.secondaryText = row.detail.isEmpty ? nil : row.detail
        content.image = AppSymbol.image(row.icon)
        content.imageProperties.tintColor = .kadrPeach
        cell.contentConfiguration = content
        cell.loadThumbnail(row)
        cell.accessoryType = .disclosureIndicator
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        rows[indexPath.row].action()
    }
    func prompt(_ title: String, value: String = "", completion: @escaping (String) -> Void) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addTextField { $0.text = value }
        alert.addAction(UIAlertAction(title: "Скасувати", style: .cancel))
        alert.addAction(UIAlertAction(title: "Зберегти", style: .default) { _ in completion(alert.textFields?.first?.text ?? "") })
        present(alert, animated: true)
    }
    func options(_ title: String, values: [String], select: @escaping (String) -> Void) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
        for value in values { alert.addAction(UIAlertAction(title: value, style: .default) { _ in select(value) }) }
        alert.addAction(UIAlertAction(title: "Скасувати", style: .cancel))
        alert.popoverPresentationController?.sourceView = view
        alert.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        present(alert, animated: true)
    }
    func push(_ controller: UIViewController) { navigationController?.pushViewController(controller, animated: true) }
}

private final class StudioActionCell: UITableViewCell {
    private var task: Task<Void, Never>?
    override func prepareForReuse() { task?.cancel(); super.prepareForReuse() }
    func loadThumbnail(_ row: StudioRow) {
        task?.cancel()
        guard let url = row.thumbnail else { return }
        task = Task { [weak self] in
            let image: UIImage?
            if row.videoThumbnail { image = await VideoPoster.image(for: url).map { UIImage(cgImage: $0) } }
            else { image = await PhotoLoader.image(url, maxPixel: 160) }
            guard !Task.isCancelled, let self, var content = self.contentConfiguration as? UIListContentConfiguration else { return }
            content.image = image; content.imageProperties.maximumSize = CGSize(width: 48, height: 48); content.imageProperties.cornerRadius = 8
            self.contentConfiguration = content
        }
    }
    deinit { task?.cancel() }
}

final class StudioController: ActionListController, UIDocumentPickerDelegate, UISearchResultsUpdating {
    private let store: LocalStore
    private var settingRows: [StudioRow] = []
    init(store: LocalStore) { self.store = store; super.init("Студія автора") }
    required init?(coder: NSCoder) { fatalError("Use init(store:)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        reloadRows = { [weak self] in self?.homeRows() ?? [] }
    }
    private func homeRows() -> [StudioRow] {
        [StudioRow(title: "Оформлення профілю", icon: "paintpalette", action: { [weak self] in self?.appearance() }),
         StudioRow(title: "Чернетки", detail: "\(store.drafts.count)", icon: "square.and.pencil", action: { [weak self] in self?.drafts() }),
         StudioRow(title: "Колекції та збережене", icon: "bookmark", action: { [weak self] in self?.collections() }),
         StudioRow(title: "Історія переглядів", icon: "clock", action: { [weak self] in self?.history(false) }),
         StudioRow(title: "Продовжити перегляд", icon: "play.circle", action: { [weak self] in self?.history(true) }),
         StudioRow(title: "Моя статистика", icon: "chart.bar", action: { [weak self] in self?.statistics() }),
         StudioRow(title: "Мій QR-код", icon: "qrcode", action: { [weak self] in self?.qr() }),
         StudioRow(title: "Сканувати QR-код", icon: "qrcode.viewfinder", action: { [weak self] in
             guard let self else { return }; let scanner = ProfileScannerController()
             scanner.onCode = { [weak self, weak scanner] text in
                 guard let self, let url = URL(string: text), let handle = url.pathComponents.last,
                       let profile = self.store.profiles.first(where: { $0.handle == handle }) else { scanner?.showMessage("Цей профіль ще недоступний локально."); return }
                 scanner?.navigationController?.popViewController(animated: false)
                 self.push(ProfileController(store: self.store, profileID: profile.id))
             }; self.push(scanner)
         }),
         StudioRow(title: "Мої інтереси", icon: "sparkles", action: { [weak self] in self?.interests() }),
         StudioRow(title: "Попередній перегляд профілю", icon: "eye", action: { [weak self] in
             guard let self, let me = self.store.active else { return }
             self.push(ProfileController(store: self.store, profileID: me.id, preview: true))
         }),
         StudioRow(title: "Налаштування", icon: "gearshape", action: { [weak self] in self?.settings() })]
    }
    private func page(_ title: String, rows: @escaping () -> [StudioRow]) -> ActionListController {
        let page = ActionListController(title)
        page.reloadRows = rows
        push(page)
        return page
    }
    private func appearance() {
        let page = ActionListController("Оформлення")
        page.reloadRows = { [weak self, weak page] in
            guard let self, let page else { return [] }
            let appearance = self.store.studio.appearance
            return [StudioRow(title: "Стиль", detail: appearance.theme, icon: "rectangle.3.group", action: {
                page.options("Стиль профілю", values: ["minimal", "cinema", "vivid"]) { value in self.store.changeStudio { $0.appearance.theme = value }; page.reload() }
            }), StudioRow(title: "Акцент", detail: appearance.accent, icon: "paintpalette", action: {
                page.options("Акцент", values: ["peach", "mint", "violet", "blue", "rose"]) { value in self.store.changeStudio { $0.appearance.accent = value }; page.reload() }
            }), StudioRow(title: "Знайомство з автором", detail: appearance.introduction, icon: "person.text.rectangle", action: {
                page.prompt("Текст знайомства", value: appearance.introduction) { value in self.store.changeStudio { $0.appearance.introduction = value }; page.reload() }
            }), StudioRow(title: "Посилання", detail: "\(appearance.links.count)", icon: "link", action: {
                page.prompt("HTTPS-посилання, через пробіл", value: appearance.links.joined(separator: " ")) { value in
                    let links = value.split(separator: " ").map(String.init).filter { URL(string: $0)?.scheme == "https" }
                    self.store.changeStudio { $0.appearance.links = Array(links.prefix(8)) }; page.reload()
                }
            }), StudioRow(title: "Кадр початку відеобанера", detail: "\(Int(appearance.bannerStart)) с", icon: "film", action: {
                page.prompt("Початок у секундах", value: String(appearance.bannerStart)) { value in
                    if let time = Double(value), time.isFinite, time >= 0 { self.store.changeStudio { $0.appearance.bannerStart = time } }; page.reload()
                }
            }), StudioRow(title: "Закріплені публікації", detail: "До трьох", icon: "pin", action: {
                self.postList("Закріпити", clips: self.store.allClips.filter { $0.authorID == self.store.active?.id }) { clip in
                    self.store.changeStudio { account in
                        if account.appearance.pinnedPosts.contains(clip.id) { account.appearance.pinnedPosts.removeAll { $0 == clip.id } }
                        else if account.appearance.pinnedPosts.count < 3 { account.appearance.pinnedPosts.append(clip.id) }
                    }
                }
            })]
        }
        push(page)
    }
    func postList(_ title: String, clips: [Clip], select: ((Clip) -> Void)? = nil) {
        let page = ActionListController(title)
        page.rows = clips.map { clip in StudioRow(title: clip.caption.isEmpty ? "Публікація" : clip.caption, detail: clip.isPhoto ? "Фото" : "Відео", icon: clip.isPhoto ? "photo" : "play.rectangle", action: { [weak self, weak page] in
            if let select { page?.navigationController?.popViewController(animated: false); select(clip) }
            else { self?.postActions(clip, from: page) }
        }) }
        push(page)
    }
    private func postActions(_ clip: Clip, from page: ActionListController?) {
        page?.options("Публікація", values: ["Переглянути", "До колекції", "Приватна нотатка", "Редагувати"]) { [weak self, weak page] value in
            guard let self, let page else { return }
            switch value {
            case "Переглянути": page.push(ClipPreviewController(clip: clip))
            case "До колекції": self.chooseCollection(clip, from: page)
            case "Приватна нотатка": page.prompt("Нотатка", value: self.store.studio.notes[clip.id] ?? "") { value in self.store.changeStudio { $0.notes[clip.id] = value } }
            default:
                guard clip.authorID == self.store.active?.id else { return }
                page.push(PostEditController(store: self.store, clip: clip))
            }
        }
    }
    func chooseCollection(_ clip: Clip, from page: ActionListController) {
        let collections = store.studio.collections
        if collections.isEmpty { page.prompt("Назва першої колекції") { [weak self] title in
            guard let self, !title.isEmpty else { return }
            let collection = SavedCollection(title: title, posts: [clip.id], cover: clip.id)
            self.store.changeStudio { $0.collections.append(collection) }
            if !self.store.bookmarked(clip) { self.store.toggleReaction(clip, bookmark: true) }
        }; return }
        page.options("Колекція", values: collections.map(\.title)) { [weak self] title in
            guard let self, let collection = collections.first(where: { $0.title == title }) else { return }
            self.store.addToCollection(clip, collectionID: collection.id)
        }
    }
    func collections() {
        let page = ActionListController("Колекції")
        page.reloadRows = { [weak self, weak page] in
            guard let self, let page else { return [] }
            return [StudioRow(title: "Усе збережене", icon: "bookmark", action: { self.savedBrowser() }),
                    StudioRow(title: "Створити колекцію", icon: "plus", action: {
                        page.prompt("Назва колекції") { title in guard !title.isEmpty else { return }; self.store.changeStudio { $0.collections.append(SavedCollection(title: title)) }; page.reload() }
                    })] + self.store.studio.collections.map { collection in StudioRow(title: collection.title, detail: "\(collection.posts.count) публікацій", icon: "rectangle.stack", thumbnail: self.store.allClips.first { $0.id == collection.cover }?.coverURL, videoThumbnail: self.store.allClips.first { $0.id == collection.cover }?.isPhoto == false, action: { self.collection(collection.id) }) }
        }
        push(page)
    }
    private func collection(_ id: UUID) {
        guard let collection = store.studio.collections.first(where: { $0.id == id }) else { return }
        let page = ActionListController(collection.title)
        page.rows = [StudioRow(title: "Обкладинка колекції", icon: "photo", action: { [weak self] in
            guard let self else { return }
            self.postList("Обкладинка", clips: self.store.allClips.filter { collection.posts.contains($0.id) }) { clip in
                self.store.changeStudio { account in if let index = account.collections.firstIndex(where: { $0.id == id }) { account.collections[index].cover = clip.id } }
            }
        }), StudioRow(title: "Перемістити всі до іншої колекції", icon: "folder", action: { [weak self, weak page] in
            guard let self, let page else { return }
            let others = self.store.studio.collections.filter { $0.id != id }
            page.options("Перемістити", values: others.map(\.title)) { title in
                guard let target = others.first(where: { $0.title == title }) else { return }
                self.store.changeStudio { account in
                    if let dest = account.collections.firstIndex(where: { $0.id == target.id }), let source = account.collections.firstIndex(where: { $0.id == id }) {
                        account.collections[dest].posts = Array(Set(account.collections[dest].posts + account.collections[source].posts))
                        account.collections[source].posts = []
                    }
                }
                page.navigationController?.popViewController(animated: true)
            }
        })] + store.allClips.filter { collection.posts.contains($0.id) }.map { clip in StudioRow(title: (collection.cover == clip.id ? "★ " : "") + clip.caption, icon: "play.rectangle", action: { [weak self, weak page] in self?.postActions(clip, from: page) }) }
        push(page)
    }
    private func savedBrowser() { push(SavedBrowserController(store: store)) }
    private func history(_ unfinished: Bool) {
        let page = ActionListController(unfinished ? "Продовжити перегляд" : "Історія")
        page.reloadRows = { [weak self, weak page] in
            guard let self else { return [] }
            let records = self.store.studio.watches.values.filter { !unfinished || !$0.completed }.sorted { $0.updatedAt > $1.updatedAt }
            return [StudioRow(title: "Очистити історію", icon: "trash", action: { self.store.changeStudio { $0.watches = [:] }; page?.reload() })] + records.compactMap { record in
                guard let clip = self.store.allClips.first(where: { $0.id == record.postID }) else { return nil }
                return StudioRow(title: clip.caption, detail: "\(Int(record.seconds)) / \(Int(record.duration)) с", icon: "play", action: { page?.push(ClipPreviewController(clip: clip, store: self.store)) })
            }
        }
        push(page)
    }
    private func drafts() {
        postList("Чернетки", clips: store.drafts) { [weak self] clip in
            guard let self else { return }
            let editor = PublishController(store: self.store, draft: clip)
            editor.onClose = { [weak editor] in editor?.navigationController?.popViewController(animated: true) }
            editor.onPublish = { [weak editor] _ in editor?.navigationController?.popViewController(animated: true) }
            self.push(editor)
        }
    }
    private func statistics() {
        let mine = store.allClips.filter { $0.authorID == store.active?.id }
        var days: [String: Int] = [:]
        if let saved = store.studio.dailyViews { days = saved }
        else { for watch in store.studio.watches.values { days[watch.updatedAt.formatted(date: .abbreviated, time: .omitted), default: 0] += 1 } }
        let page = ActionListController("Моя статистика")
        page.rows = [StudioRow(title: "Публікації: \(mine.count)", action: {}), StudioRow(title: "Лайки публікацій: \(mine.reduce(0) { $0 + store.likes($1) })", action: {}), StudioRow(title: "Переглянуто: \(store.studio.watches.count)", action: {})]
            + days.keys.sorted().map { day in StudioRow(title: day, detail: "\(days[day] ?? 0) переглядів", action: {}) }
        push(page)
    }
    private func qr() {
        guard let me = store.active else { return }
        push(ProfileQRController(profile: me))
    }
    private func interests() {
        let page = ActionListController("Інтереси")
        let tags = ["подорожі", "музика", "спорт", "кіно", "мистецтво", "технології", "природа", "їжа", "ігри", "гумор"]
        page.reloadRows = { [weak self, weak page] in
            guard let self else { return [] }
            return tags.map { tag in StudioRow(title: (self.store.studio.appearance.interests.contains(tag) ? "✓ " : "") + tag, icon: "number", action: {
                self.store.changeStudio { account in
                    if account.appearance.interests.contains(tag) { account.appearance.interests.removeAll { $0 == tag } }
                    else { account.appearance.interests.append(tag); account.preferences.preferredTags.insert(tag) }
                }
                page?.reload()
            }) }
        }
        push(page)
    }
    private func settings() { push(SettingsController(store: store)) }
    func updateSearchResults(for searchController: UISearchController) { }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { }
}

final class SavedBrowserController: ActionListController, UISearchResultsUpdating {
    private let store: LocalStore
    private var term = ""
    private var sort = "date"
    init(store: LocalStore) { self.store = store; super.init("Збережене") }
    required init?(coder: NSCoder) { fatalError("Use init(store:)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        let search = UISearchController(); search.searchResultsUpdater = self; search.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = search
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: AppSymbol.image("arrow.up.arrow.down"), primaryAction: UIAction { [weak self] _ in
            self?.options("Порядок", values: ["date", "author", "media"]) { value in self?.sort = value; self?.reload() }
        })
        reloadRows = { [weak self] in
            guard let self else { return [] }
            var clips = self.store.feed(.saved).filter { self.term.isEmpty || $0.caption.localizedCaseInsensitiveContains(self.term) || (self.store.profile($0.authorID)?.handle.localizedCaseInsensitiveContains(self.term) ?? false) }
            clips.sort {
                if self.sort == "author" { return (self.store.profile($0.authorID)?.handle ?? $0.credit) < (self.store.profile($1.authorID)?.handle ?? $1.credit) }
                if self.sort == "media", $0.isPhoto != $1.isPhoto { return $0.isPhoto }
                return ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
            }
            return clips.map { clip in StudioRow(title: clip.caption, icon: clip.isPhoto ? "photo" : "play", action: { self.push(ClipPreviewController(clip: clip, store: self.store)) }) }
        }
    }
    func updateSearchResults(for searchController: UISearchController) { term = searchController.searchBar.text ?? ""; reload() }
}

final class ProfileQRController: UIViewController {
    private let profile: Profile
    init(profile: Profile) { self.profile = profile; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("Use init(profile:)") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "@\(profile.handle)"; view.backgroundColor = .systemBackground
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data("kadr://profile/\(profile.handle)".utf8)
        let image = UIImageView()
        if let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) { image.image = UIImage(ciImage: output) }
        image.contentMode = .scaleAspectFit; image.layer.magnificationFilter = .nearest
        image.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(image)
        NSLayoutConstraint.activate([image.centerXAnchor.constraint(equalTo: view.centerXAnchor), image.centerYAnchor.constraint(equalTo: view.centerYAnchor), image.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.72), image.heightAnchor.constraint(equalTo: image.widthAnchor)])
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .action, primaryAction: UIAction { [weak self] _ in
            guard let self else { return }; self.present(UIActivityViewController(activityItems: ["kadr://profile/\(self.profile.handle)"], applicationActivities: nil), animated: true)
        })
    }
}
