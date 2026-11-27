import UIKit
import UniformTypeIdentifiers

final class SettingsController: ActionListController, UISearchResultsUpdating, UIDocumentPickerDelegate {
    private let store: LocalStore
    var onRestore: (() -> Void)?
    private var query = ""
    private var backupTask: Task<Void, Never>?
    init(store: LocalStore) { self.store = store; super.init("Налаштування") }
    required init?(coder: NSCoder) { fatalError("Use init(store:)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        let search = UISearchController(); search.searchResultsUpdater = self; search.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = search
        reloadRows = { [weak self] in self?.settingsRows() ?? [] }
    }
    private func settingsRows() -> [StudioRow] {
        let preferences = store.studio.preferences
        let rows = [StudioRow(title: "Акцент застосунку", detail: "Колір активних кнопок та іконок", icon: "paintpalette", action: { [weak self] in guard let self else { return }; self.push(AccentSettingsController(store: self.store)) }), StudioRow(title: "Оновлення", detail: AppUpdates.current.version, icon: "sparkles", action: { [weak self] in self?.push(UpdatesController()) }), StudioRow(title: "Тактильні відгуки", detail: preferences.haptics ? "Увімкнено" : "Вимкнено", icon: "hand.tap", action: { [weak self] in
            self?.store.changeStudio { $0.preferences.haptics.toggle() }; self?.reload()
        }), StudioRow(title: "Автоматичний звук", detail: preferences.autoSound ? "Увімкнено" : "Вимкнено", icon: "speaker.wave.2", action: { [weak self] in
            self?.store.changeStudio { $0.preferences.autoSound.toggle() }; self?.reload()
        }), StudioRow(title: "Швидкість відео", detail: "\(preferences.playbackRate)×", icon: "speedometer", action: { [weak self] in
            self?.options("Швидкість", values: ["0.5", "0.75", "1", "1.25", "1.5", "2"]) { value in self?.store.changeStudio { $0.preferences.playbackRate = Float(value) ?? 1 }; self?.reload() }
        }), StudioRow(title: "Хто може починати чат", detail: StudioLabels.title(preferences.messagePermission), icon: "lock", action: { [weak self] in
            self?.options("Повідомлення", values: ["following", "everyone", "nobody"].map(StudioLabels.title)) { value in self?.store.changeStudio { $0.preferences.messagePermission = StudioLabels.key(value, among: ["following", "everyone", "nobody"]) }; self?.reload() }
        }), StudioRow(title: "Заблоковані користувачі", detail: "\(preferences.blocked.count)", icon: "person.slash", action: { [weak self] in
            guard let self else { return }; let page = ActionListController("Заблоковані")
            page.reloadRows = { [weak self, weak page] in
                guard let self else { return [] }
                return self.store.profiles.filter { self.store.studio.preferences.blocked.contains($0.id) }.map { profile in
                    StudioRow(title: "Розблокувати @\(profile.handle)", action: { self.store.changeStudio { $0.preferences.blocked.remove(profile.id) }; page?.reload() })
                }
            }; self.push(page)
        }), StudioRow(title: "Фільтр слів у коментарях", icon: "text.badge.checkmark", action: { [weak self] in
            guard let self else { return }; self.prompt("Слова через кому", value: preferences.mutedWords.joined(separator: ", ")) { text in
                self.store.changeStudio { $0.preferences.mutedWords = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty } }
            }
        }), StudioRow(title: "Кеш", detail: ByteCountFormatter.string(fromByteCount: Int64(URLCache.shared.currentDiskUsage), countStyle: .file), icon: "internaldrive", action: { [weak self] in
            PhotoLoader.clearCache(); VideoPoster.clearCache(); URLCache.shared.removeAllCachedResponses(); self?.reload()
        }), StudioRow(title: "Резервна копія", icon: "externaldrive.badge.plus", action: { [weak self] in self?.backup() }),
        StudioRow(title: "Відновити резервну копію", icon: "arrow.clockwise", action: { [weak self] in
            guard let self else { return }; let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false); picker.delegate = self; self.present(picker, animated: true)
        }), StudioRow(title: "Доступність", detail: "Розмір тексту, VoiceOver, зменшення руху й прозорості — системні налаштування iOS", icon: "accessibility", action: {
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        })]
        return rows.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.detail.localizedCaseInsensitiveContains(query) }
    }
    func updateSearchResults(for searchController: UISearchController) { query = searchController.searchBar.text ?? ""; reload() }
    private func backup() {
        guard backupTask == nil else { return }
        let spinner = UIActivityIndicatorView(style: .medium); spinner.startAnimating()
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: spinner)
        backupTask = Task { [weak self] in
            guard let self else { return }
            defer { self.backupTask = nil; self.navigationItem.rightBarButtonItem = nil }
            do {
                try await self.store.flush()
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Kadr-Backup-" + UUID().uuidString)
                try await Task.detached(priority: .utility) { try FileManager.default.copyItem(at: LocalStore.directory, to: folder) }.value
                guard self.view.window != nil else { return }
                self.present(UIDocumentPickerViewController(forExporting: [folder], asCopy: true), animated: true)
            } catch { self.showMessage(error.localizedDescription) }
        }
    }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let source = urls.first else { return }
        let confirmation = UIAlertController(title: "Відновити локальні дані?", message: "Поточні профілі й публікації будуть замінені даними з копії.", preferredStyle: .alert)
        confirmation.addAction(UIAlertAction(title: "Скасувати", style: .cancel))
        confirmation.addAction(UIAlertAction(title: "Відновити", style: .destructive) { [weak self] _ in
            guard let self else { return }
            Task { [weak self] in
                guard let self else { return }
                let accessed = source.startAccessingSecurityScopedResource(); defer { if accessed { source.stopAccessingSecurityScopedResource() } }
                let spinner = UIActivityIndicatorView(style: .medium); spinner.startAnimating(); self.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: spinner)
                defer { self.navigationItem.rightBarButtonItem = nil }
                do { try await self.store.restoreBackup(source); self.reload(); self.onRestore?() } catch { self.showMessage(error.localizedDescription) }
            }
        })
        present(confirmation, animated: true)
    }
}

extension LocalStore {
    @MainActor func restoreBackup(_ source: URL) async throws {
        guard !isRestoringBackup else { throw CocoaError(.fileWriteFileExists) }
        isRestoringBackup = true; defer { isRestoringBackup = false }
        await cleanupTask?.value
        try await flush()
        let snapshot = try await Task.detached(priority: .utility) { () throws -> State in
            let snapshot = try JSONDecoder().decode(State.self, from: Data(contentsOf: source.appendingPathComponent("state.json")))
            var files = Set(snapshot.clips.flatMap { ($0.media ?? []).map(\.file) })
            snapshot.profiles.compactMap(\.bannerFile).forEach { files.insert($0) }
            snapshot.profiles.compactMap(\.portraitFile).forEach { files.insert($0) }
            snapshot.profiles.compactMap(\.avatarVideoFile).forEach { files.insert($0) }
            snapshot.clips.compactMap { $0.extras?.coverFile }.forEach { files.insert($0) }
            snapshot.messages?.compactMap(\.attachmentFile).forEach { files.insert($0) }
            guard files.allSatisfy({ !$0.isEmpty && URL(fileURLWithPath: $0).lastPathComponent == $0 && !$0.contains("..") }) else { throw CocoaError(.fileReadCorruptFile) }
            for file in files {
                let url = source.appendingPathComponent(file)
                guard FileManager.default.fileExists(atPath: url.path), try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw CocoaError(.fileReadCorruptFile) }
            }
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            for file in files {
                let destination = Self.directory.appendingPathComponent(file)
                let temporary = Self.directory.appendingPathComponent("restore-" + UUID().uuidString)
                try FileManager.default.copyItem(at: source.appendingPathComponent(file), to: temporary)
                if FileManager.default.fileExists(atPath: destination.path) { _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary) }
                else { try FileManager.default.moveItem(at: temporary, to: destination) }
            }
            return snapshot
        }.value
        isRestoringBackup = false
        guard acceptRestoredState(snapshot) else { throw CocoaError(.fileWriteUnknown) }
        isRestoringBackup = true
        try await flush()
        NotificationCenter.default.post(name: .kadrMessagesDidChange, object: self)
        NotificationCenter.default.post(name: .kadrProfileDidChange, object: self)
    }

}

final class PostEditController: ActionListController {
    private let store: LocalStore
    private var clip: Clip
    init(store: LocalStore, clip: Clip) { self.store = store; self.clip = clip; super.init("Редагування публікації") }
    required init?(coder: NSCoder) { fatalError("Use init(store:clip:)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        reloadRows = { [weak self] in
            guard let self else { return [] }
            return [StudioRow(title: "Опис", detail: self.clip.caption, icon: "text.alignleft", action: {
                self.prompt("Опис", value: self.clip.caption) { text in self.clip.caption = String(text.prefix(2200)); self.save() }
            }), StudioRow(title: "Коментарі", detail: self.clip.settings.allowsComments ? "Увімкнені" : "Вимкнені", icon: "bubble.left", action: {
                var options = self.clip.settings; options.allowsComments.toggle(); self.clip.options = options; self.save()
            }), StudioRow(title: "Видимість", detail: self.clip.settings.onlyMe ? "Тільки я" : "Усі", icon: "eye", action: {
                var options = self.clip.settings; options.onlyMe.toggle(); self.clip.options = options; self.save()
            }), StudioRow(title: "Кількість лайків", detail: self.clip.extras?.hideLikes == true ? "Прихована" : "Видима", icon: "heart", action: {
                var extras = self.clip.extras ?? PostExtras(); extras.hideLikes.toggle(); self.clip.extras = extras; self.save()
            }), StudioRow(title: "Обкладинка", icon: "photo", action: {
                if self.clip.isPhoto {
                    self.options("Номер фото", values: (self.clip.media ?? []).indices.map { String($0 + 1) }) { number in var options = self.clip.settings; options.coverIndex = max(0, (Int(number) ?? 1) - 1); self.clip.options = options; self.save() }
                } else { self.prompt("Кадр у секундах", value: String(self.clip.extras?.coverTime ?? 0.5)) { text in
                    var extras = self.clip.extras ?? PostExtras(); extras.coverTime = max(0, Double(text) ?? 0.5); self.clip.extras = extras; self.save()
                } }
            })]
        }
    }
    private func save() { store.editPost(clip, caption: clip.caption, options: clip.settings, extras: clip.extras ?? PostExtras()); reload() }
}
