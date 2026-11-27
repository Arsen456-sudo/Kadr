import UIKit
import PhotosUI
import AVFoundation

final class InboxController: LibraryController, UISearchResultsUpdating {
    private let store: LocalStore
    private let repository: any SocialRepository
    private var rows: [ConversationSummary] = [] { didSet { conversationKey = "" } }
    private var conversationKey = ""
    private var conversationSnapshot: [ConversationSummary] = []
    private var query = ""
    private var activityMode = false
    private var chatFilter = 0
    private let filterButton = UIButton(configuration: .glass())
    private let header = UIView()
    private let sectionHeading = makeLabel(.title2, text: "Твої розмови")
    private var conversations: [ConversationSummary] {
        let key = "\(store.localRevision):\(store.active?.id.uuidString ?? "guest"):\(chatFilter):\(query)"
        if key == conversationKey { return conversationSnapshot }
        let owner = store.active?.id
        let mediaPeers = Set((store.state.messages ?? []).filter { ($0.senderID == owner || $0.recipientID == owner) && ($0.attachmentFile != nil || $0.postID != nil) }.map { $0.senderID == owner ? $0.recipientID : $0.senderID })
        conversationSnapshot = rows.filter { row in
        let matchesQuery = query.isEmpty || row.profile.handle.localizedCaseInsensitiveContains(query) || row.profile.name.localizedCaseInsensitiveContains(query) || row.lastMessage.text.localizedCaseInsensitiveContains(query)
        let matchesFilter = chatFilter == 0 || (chatFilter == 1 && store.studio.pinnedChats.contains(row.id)) || (chatFilter == 2 && mediaPeers.contains(row.id))
        return matchesQuery && matchesFilter
    }.sorted {
        let a = store.studio.pinnedChats.contains($0.id), b = store.studio.pinnedChats.contains($1.id)
        return a != b ? a : $0.lastMessage.createdAt > $1.lastMessage.createdAt
        }
        conversationKey = key
        return conversationSnapshot
    }
    private var activities: [ActivityEntry] { (store.state.activity ?? []).filter { $0.recipientID == store.active?.id }.sorted { $0.createdAt > $1.createdAt } }
    var onProfile: ((UUID) -> Void)?
    var onPost: ((Clip) -> Void)?
    private var request: Task<Void, Never>?
    var scrollView: UIScrollView { tableView }
    var onSearch: (() -> Void)?
    var onAccount: (() -> Void)?
    var onChat: ((Profile) -> Void)?

    init(store: LocalStore, repository: any SocialRepository) {
        self.store = store
        self.repository = repository
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(store:repository:)") }
    override func showEmpty(_ empty: EmptyStateView?) {
        tableView.isHidden = false
        tableView.backgroundView = empty
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .kadrMessagesDidChange, object: store)
        let search = UISearchController(); search.searchResultsUpdater = self; search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = "Імʼя, @нікнейм або повідомлення"
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false
        let sections = GlassSectionPicker(titles: ["Розмови", "Активність"])
        sections.accessibilityIdentifier = "inbox.sections"
        sections.onIndexSelection = { [weak self] index in
            self?.activityMode = index == 1; self?.filterButton.isEnabled = index == 0
            self?.sectionHeading.text = index == 1 ? "Твоя активність" : "Твої розмови"; self?.reloadInbox()
        }
        let effect = UIGlassEffect(); effect.isInteractive = true
        let island = UIVisualEffectView(effect: effect)
        island.layer.cornerRadius = 22; island.clipsToBounds = true
        sections.pin(to: island.contentView)
        island.heightAnchor.constraint(equalToConstant: 44).isActive = true
        let heading = sectionHeading
        heading.font = heading.font.withTraits(.traitBold)
        heading.accessibilityTraits.insert(.header)
        filterButton.configuration?.image = AppSymbol.image("line.3.horizontal.decrease")
        filterButton.configuration?.cornerStyle = .capsule
        filterButton.accessibilityLabel = "Фільтр розмов"
        filterButton.widthAnchor.constraint(equalToConstant: 44).isActive = true
        filterButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
        updateFilterMenu()
        let compose = UIButton(configuration: .glass())
        compose.configuration?.image = AppSymbol.image("square.and.pencil"); compose.configuration?.cornerStyle = .capsule
        compose.accessibilityLabel = "Нова розмова"
        compose.widthAnchor.constraint(equalToConstant: 44).isActive = true; compose.heightAnchor.constraint(equalToConstant: 44).isActive = true
        compose.addAction(UIAction { [weak self] _ in self?.onSearch?() }, for: .primaryActionTriggered)
        let actions = UIStackView(arrangedSubviews: [heading, filterButton, compose]); actions.spacing = 10; actions.alignment = .center
        let stack = UIStackView(arrangedSubviews: [island, actions]); stack.axis = .vertical; stack.spacing = 20
        header.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 140)
        stack.pin(to: header, insets: .init(top: 12, leading: 16, bottom: 16, trailing: 16))
        tableView.tableHeaderView = header
        tableView.backgroundColor = .systemBackground
        tableView.rowHeight = UITableView.automaticDimension; tableView.estimatedRowHeight = 88
        tableView.keyboardDismissMode = .onDrag; tableView.topEdgeEffect.style = .soft
        tableView.separatorStyle = .none
        tableView.refreshControl = UIRefreshControl()
        tableView.refreshControl?.addAction(UIAction { [weak self] _ in self?.refresh() }, for: .valueChanged)
        refresh()
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = tableView.bounds.width
        let size = header.systemLayoutSizeFitting(CGSize(width: width, height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        if abs(header.frame.height - size.height) > 0.5 || header.frame.width != width {
            header.frame = CGRect(x: 0, y: 0, width: width, height: size.height); tableView.tableHeaderView = header
        }
    }
    private func updateFilterMenu() {
        filterButton.menu = UIMenu(title: "Розмови", options: .singleSelection, children: ["Усі", "Закріплені", "З медіа"].enumerated().map { index, title in
            UIAction(title: title, image: AppSymbol.image(["bubble.left.and.bubble.right", "pin", "photo.stack"][index]), state: chatFilter == index ? .on : .off) { [weak self] _ in
                self?.chatFilter = index; self?.updateFilterMenu(); self?.reloadInbox()
            }
        })
        filterButton.showsMenuAsPrimaryAction = true
    }
    private func reloadInbox() {
        showEmpty(nil); tableView.reloadData()
        if store.active == nil {
            showEmpty(EmptyStateView(title: "Твої повідомлення", message: "Увійди, щоб почати розмову.", symbol: "bubble.left.and.bubble.right", action: textButton("Увійти") { [weak self] in self?.onAccount?() }))
        } else if activityMode ? activities.isEmpty : conversations.isEmpty {
            showEmpty(EmptyStateView(title: activityMode ? "Активності поки немає" : "Розмов не знайдено", message: activityMode ? "Тут зʼявляться підписки, реакції та коментарі." : "Спробуй інший запит, зміни фільтр або почни нову розмову.", symbol: activityMode ? "bell" : "bubble.left.and.bubble.right"))
        }
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refresh()
    }
    @objc func refresh() {
        guard isViewLoaded else { return }
        request?.cancel()
        guard store.active != nil else {
            rows = []
            tableView.reloadData()
            showEmpty(EmptyStateView(title: "Твої повідомлення", message: "Увійди, щоб почати розмову.", symbol: "bubble.left.and.bubble.right",
                action: textButton("Увійти") { [weak self] in self?.onAccount?() }))
            tableView.refreshControl?.endRefreshing()
            return
        }
        let accountID = store.active?.id
        request = Task { [weak self] in
            guard let self else { return }
            defer { self.tableView.refreshControl?.endRefreshing() }
            do {
                let rows = try await self.repository.conversations()
                guard !Task.isCancelled, self.store.active?.id == accountID else { return }
                self.rows = rows
                self.reloadInbox()
            } catch {
                if !Task.isCancelled { self.showMessage(error.localizedDescription) }
            }
        }
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { activityMode ? activities.count : conversations.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if activityMode {
            let entry = activities[indexPath.row]
            if let profile = store.profile(entry.actorID) {
                let cell = tableView.dequeueReusableCell(withIdentifier: "activity") as? InboxConversationCell ?? InboxConversationCell(style: .default, reuseIdentifier: "activity")
                cell.show(profile: profile, preview: entry.kind == "follow" ? "Підписався на тебе" : entry.kind == "like" ? "Уподобав публікацію" : "Залишив коментар", date: entry.createdAt, pinned: false, draft: false)
                return cell
            }
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
            cell.textLabel?.text = "@" + (store.profile(entry.actorID)?.handle ?? "користувач")
            cell.detailTextLabel?.text = entry.kind == "follow" ? "Підписався на тебе" : entry.kind == "like" ? "Уподобав публікацію" : "Залишив коментар"
            cell.imageView?.image = AppSymbol.image(entry.kind == "follow" ? "person.badge.plus" : entry.kind == "like" ? "heart" : "bubble.left")
            return cell
        }
        let row = conversations[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "conversation") as? InboxConversationCell ?? InboxConversationCell(style: .default, reuseIdentifier: "conversation")
        let pinned = store.studio.pinnedChats.contains(row.id)
        let draft = store.studio.chatDrafts[row.id.uuidString] ?? ""
        let preview = !draft.isEmpty ? "Чернетка: " + draft : row.lastMessage.text.isEmpty ? (row.lastMessage.postID != nil ? "Публікація" : "Вкладення") : row.lastMessage.text
        cell.show(profile: row.profile, preview: preview, date: row.lastMessage.createdAt, pinned: pinned, draft: !draft.isEmpty)
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if activityMode {
            let entry = activities[indexPath.row]
            if let post = store.allClips.first(where: { $0.id == entry.postID }) { onPost?(post) } else { onProfile?(entry.actorID) }
        } else { onChat?(conversations[indexPath.row].profile) }
    }
    func updateSearchResults(for searchController: UISearchController) { query = searchController.searchBar.text ?? ""; reloadInbox() }
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard !activityMode else { return nil }
        let id = conversations[indexPath.row].id
        let pinned = store.studio.pinnedChats.contains(id)
        let action = UIContextualAction(style: .normal, title: pinned ? "Відкріпити" : "Закріпити") { [weak self] _, _, done in
            guard let self else { done(false); return }
            self.store.changeStudio { account in if pinned { account.pinnedChats.remove(id) } else { account.pinnedChats.insert(id) } }
            self.tableView.reloadData(); done(true)
        }
        action.image = AppSymbol.image(pinned ? "pin.slash" : "pin"); return UISwipeActionsConfiguration(actions: [action])
    }
    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard !activityMode else { return nil }; let peer = conversations[indexPath.row].profile
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: [UIAction(title: "Написати", image: AppSymbol.image("bubble.left")) { _ in self?.onChat?(peer) }, UIAction(title: "Відкрити профіль", image: AppSymbol.image("person.crop.circle")) { _ in self?.onProfile?(peer.id) }])
        }
    }
    deinit { request?.cancel() }

}

final class ChatController: UIViewController, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate, UISearchResultsUpdating, PHPickerViewControllerDelegate {
    private let store: LocalStore
    private let repository: any SocialRepository
    private let peer: Profile
    private let accountID: UUID?
    private let table = UITableView()
    private var query = ""
    private var replyTo: UUID?
    private var audioPlayer: AVAudioPlayer?
    private var attachment: URL?
    private var attachmentKind: String?
    private var sharedPost: String?
    private var visibleRows: [ChatMessage] { rows.filter { query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) } }
    private let field = UITextField()
    private let send = UIButton(configuration: .glass())
    private var rows: [ChatMessage] = []
    private var loadTask: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?
    private var retryID: UUID?
    private var retryText: String?

    init(store: LocalStore, repository: any SocialRepository, peer: Profile) {
        self.store = store
        self.repository = repository
        self.peer = peer
        accountID = store.active?.id
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(store:repository:peer:)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "@\(peer.handle)"
        view.backgroundColor = .systemBackground
        table.dataSource = self
        table.delegate = self
        let search = UISearchController(); search.searchResultsUpdater = self; search.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = search
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: AppSymbol.image("pin"), primaryAction: UIAction { [weak self] _ in
            guard let self else { return }; self.store.changeStudio { account in
                if account.pinnedChats.remove(self.peer.id) == nil { account.pinnedChats.insert(self.peer.id) }
            }
        })
        table.rowHeight = UITableView.automaticDimension; table.estimatedRowHeight = 88
        table.separatorStyle = .none
        table.keyboardDismissMode = .interactive
        table.allowsSelection = true
        table.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(table)
        field.text = store.studio.chatDrafts[peer.id.uuidString]
        field.placeholder = "Повідомлення"
        field.returnKeyType = .send
        field.delegate = self
        field.accessibilityLabel = "Текст повідомлення"
        field.addAction(UIAction { [weak self] _ in self?.updateSend() }, for: .editingChanged)
        let island = glassIsland()
        field.pin(to: island.contentView, insets: .init(top: 0, leading: 16, bottom: 0, trailing: 16))
        island.heightAnchor.constraint(equalToConstant: 48).isActive = true
        send.configuration?.image = AppSymbol.image( "arrow.up")
        send.accessibilityLabel = "Надіслати повідомлення"
        send.widthAnchor.constraint(equalToConstant: 48).isActive = true
        send.heightAnchor.constraint(equalToConstant: 48).isActive = true
        send.addAction(UIAction { [weak self] _ in self?.sendMessage() }, for: .primaryActionTriggered)
        let attach = UIButton(configuration: .glass())
        attach.configuration?.image = AppSymbol.image("plus")
        attach.accessibilityLabel = "Додати вкладення"
        attach.widthAnchor.constraint(equalToConstant: 44).isActive = true
        attach.menu = UIMenu(children: [UIAction(title: "Фотографія", image: AppSymbol.image("photo")) { [weak self] _ in
            guard let self else { return }; var configuration = PHPickerConfiguration(); configuration.filter = .images; configuration.selectionLimit = 1
            let picker = PHPickerViewController(configuration: configuration); picker.delegate = self; self.present(picker, animated: true)
        }, UIAction(title: "Голосове повідомлення", image: AppSymbol.image("mic")) { [weak self] _ in
            guard let self else { return }; let recorder = VoiceRecorderController()
            recorder.onSend = { [weak self, weak recorder] url in
                let retained = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a")
                do { try FileManager.default.copyItem(at: url, to: retained) } catch { self?.showMessage(error.localizedDescription); return }
                self?.attachment = retained; self?.attachmentKind = "audio"; self?.field.text = "Голосове повідомлення"
                self?.sendMessage(); recorder?.navigationController?.popViewController(animated: true)
            }; self.navigationController?.pushViewController(recorder, animated: true)
        }, UIAction(title: "Публікація", image: AppSymbol.image("play.rectangle")) { [weak self] _ in
            guard let self else { return }; let page = ActionListController("Надіслати публікацію")
            page.rows = self.store.allClips.map { clip in StudioRow(title: clip.caption, icon: "play", action: { [weak self, weak page] in
                self?.sharedPost = clip.id; self?.field.text = clip.caption.isEmpty ? "Публікація" : clip.caption
                self?.sendMessage(); page?.navigationController?.popViewController(animated: true)
            }) }; self.navigationController?.pushViewController(page, animated: true)
        }])
        attach.showsMenuAsPrimaryAction = true
        let composer = UIStackView(arrangedSubviews: [attach, island, send])
        composer.spacing = 8
        composer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(composer)
        NSLayoutConstraint.activate([
            table.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor), table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: composer.topAnchor, constant: -8),
            composer.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            composer.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            composer.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -8)
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(loadMessages), name: .kadrMessagesDidChange, object: store)
        updateSend()
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadMessages()
    }
    @objc private func loadMessages() {
        loadTask?.cancel()
        guard accountID != nil, accountID == store.active?.id else { field.isEnabled = false; send.isEnabled = false; return }
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let messages = try await self.repository.messages(with: self.peer.id)
                guard !Task.isCancelled else { return }
                self.rows = messages
                self.table.reloadData()
                if !self.visibleRows.isEmpty { self.table.scrollToRow(at: IndexPath(row: self.visibleRows.count - 1, section: 0), at: .bottom, animated: false) }
            } catch { if !Task.isCancelled { self.showMessage(error.localizedDescription) } }
        }
    }
    private func updateSend() {
        let text = (field.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        send.isEnabled = sendTask == nil && !text.isEmpty && text.count <= 4000 && accountID == store.active?.id && !store.studio.preferences.blocked.contains(peer.id)
    }
    private func sendMessage() {
        guard sendTask == nil, accountID != nil, accountID == store.active?.id else { return }
        let text = (field.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 4000 else { return }
        let id = retryText == text ? (retryID ?? UUID()) : UUID()
        retryID = id
        retryText = text
        field.isEnabled = false
        send.isEnabled = false
        let source = attachment, kind = attachmentKind, reply = replyTo, post = sharedPost
        sendTask = Task { [weak self] in
            guard let self else { return }
            defer { self.sendTask = nil; self.field.isEnabled = true; self.updateSend() }
            do {
                _ = try await self.repository.send(text: text, to: self.peer.id, id: id)
                try self.store.attachMessage(id, source: source, kind: kind, reply: reply, postID: post)
                try await self.store.flush()
                self.attachment = nil; self.attachmentKind = nil; self.sharedPost = nil; self.replyTo = nil
                self.field.placeholder = "Повідомлення"
                self.field.text = ""
                self.store.changeStudio { $0.chatDrafts[self.peer.id.uuidString] = nil }
                self.retryID = nil
                self.retryText = nil
                self.loadMessages()
            } catch { self.showMessage(error.localizedDescription) }
        }
    }
    func textFieldShouldReturn(_ textField: UITextField) -> Bool { sendMessage(); return false }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { visibleRows.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let message = visibleRows[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "message") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "message")
        var content = cell.defaultContentConfiguration()
        let mine = message.senderID == accountID
        content.text = (message.replyTo.flatMap { id in rows.first { $0.id == id } }.map { "↪ " + String($0.text.prefix(60)) + "\n" } ?? "") + message.text
        if let reactions = message.reactions, !reactions.isEmpty { content.text = (content.text ?? "") + "\n" + reactions.values.sorted().joined(separator: " ") }
        if message.postID != nil { content.image = AppSymbol.image("play.rectangle.fill") }
        if message.attachmentKind == "audio" { content.image = AppSymbol.image("waveform") }
        if message.attachmentKind == "photo", let file = message.attachmentFile {
            content.image = UIImage(contentsOfFile: LocalStore.directory.appendingPathComponent(file).path)
            content.imageProperties.maximumSize = CGSize(width: 160, height: 160)
        }
        content.textProperties.numberOfLines = 0
        content.textProperties.alignment = .natural
        content.secondaryText = message.createdAt.formatted(date: .abbreviated, time: .shortened)
        content.secondaryTextProperties.alignment = .natural
        var background = UIBackgroundConfiguration.listPlainCell()
        background.backgroundColor = mine ? UIColor.kadrPeach.withAlphaComponent(0.15) : .secondarySystemBackground
        background.cornerRadius = 18
        background.backgroundInsets = .init(top: 3, leading: mine ? 60 : 12, bottom: 3, trailing: mine ? 12 : 60)
        content.directionalLayoutMargins = .init(top: 12, leading: mine ? 72 : 24, bottom: 12, trailing: mine ? 24 : 72)
        cell.contentConfiguration = content
        cell.backgroundConfiguration = background
        return cell
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if accountID == store.active?.id { store.changeStudio { $0.chatDrafts[peer.id.uuidString] = field.text } }
        audioPlayer?.stop()
    }
    func updateSearchResults(for searchController: UISearchController) { query = searchController.searchBar.text ?? ""; table.reloadData() }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let message = visibleRows[indexPath.row]
        if let postID = message.postID, let clip = store.allClips.first(where: { $0.id == postID }) { navigationController?.pushViewController(ClipPreviewController(clip: clip, store: store), animated: true) }
        if let file = message.attachmentFile, message.attachmentKind == "audio" {
            do { audioPlayer = try AVAudioPlayer(contentsOf: LocalStore.directory.appendingPathComponent(file)); audioPlayer?.play() } catch { showMessage(error.localizedDescription) }
        }
        if let file = message.attachmentFile, message.attachmentKind == "photo" {
            let album = PhotoAlbumController(media: [PostMedia(id: UUID(), kind: .photo, file: file)])
            navigationController?.pushViewController(album, animated: true)
        }
    }
    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let message = visibleRows[indexPath.row]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            var actions = [UIAction(title: "Відповісти", image: AppSymbol.image("arrowshape.turn.up.left")) { [weak self] _ in
                self?.replyTo = message.id; self?.field.placeholder = "Відповідь на: " + String(message.text.prefix(32)); self?.field.becomeFirstResponder()
            }]
            actions += ["❤️", "👍", "😂", "🔥"].map { emoji in UIAction(title: emoji) { [weak self] _ in self?.store.reactToMessage(message, emoji: emoji) } }
            if message.senderID == self.accountID {
                actions.append(UIAction(title: "Редагувати", image: AppSymbol.image("pencil")) { [weak self] _ in
                    guard let self else { return }; let alert = UIAlertController(title: "Повідомлення", message: nil, preferredStyle: .alert)
                    alert.addTextField { $0.text = message.text }
                    alert.addAction(UIAlertAction(title: "Зберегти", style: .default) { [weak self] _ in self?.store.editMessage(message, text: alert.textFields?.first?.text ?? "") })
                    alert.addAction(UIAlertAction(title: "Скасувати", style: .cancel)); self.present(alert, animated: true)
                })
                actions.append(UIAction(title: "Видалити", image: AppSymbol.image("trash"), attributes: .destructive) { [weak self] _ in self?.store.deleteMessage(message) })
            }
            return UIMenu(children: actions)
        }
    }
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else { return }
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            guard let image = object as? UIImage, let data = image.jpegData(compressionQuality: 0.95) else { return }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
            do { try data.write(to: url); DispatchQueue.main.async {
                self?.attachment = url; self?.attachmentKind = "photo"; self?.field.text = "Фотографія"; self?.sendMessage()
            } } catch { }
        }
    }
    deinit { loadTask?.cancel(); sendTask?.cancel() }
}
