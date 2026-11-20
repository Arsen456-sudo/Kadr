import UIKit

final class InboxController: LibraryController {
    private let store: LocalStore
    private let repository: any SocialRepository
    private var rows: [ConversationSummary] = []
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
    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .kadrMessagesDidChange, object: store)
        tableView.refreshControl = UIRefreshControl()
        tableView.refreshControl?.addAction(UIAction { [weak self] _ in self?.refresh() }, for: .valueChanged)
        refresh()
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
                self.showEmpty(rows.isEmpty ? EmptyStateView(title: "Почни розмову", message: "Знайди користувача за @нікнеймом, підпишись і напиши йому.",
                    symbol: "bubble.left.and.bubble.right", action: textButton("Знайти користувача", symbol: "magnifyingglass") { [weak self] in self?.onSearch?() }) : nil)
                self.tableView.reloadData()
            } catch {
                if !Task.isCancelled { self.showMessage(error.localizedDescription) }
            }
        }
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = rows[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "conversation") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "conversation")
        var content = cell.defaultContentConfiguration()
        content.text = "@\(row.profile.handle)"
        content.secondaryText = row.lastMessage.text
        content.secondaryTextProperties.numberOfLines = 2
        content.image = row.profile.avatar.flatMap { UIImage(data: $0) } ?? UIImage(systemName: "person.crop.circle.fill")
        content.imageProperties.maximumSize = CGSize(width: 44, height: 44)
        content.imageProperties.cornerRadius = 22
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        onChat?(rows[indexPath.row].profile)
    }
    deinit { request?.cancel() }

}

final class ChatController: UIViewController, UITableViewDataSource, UITextFieldDelegate {
    private let store: LocalStore
    private let repository: any SocialRepository
    private let peer: Profile
    private let accountID: UUID?
    private let table = UITableView()
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
        table.separatorStyle = .none
        table.keyboardDismissMode = .interactive
        table.allowsSelection = false
        table.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(table)
        field.placeholder = "Повідомлення"
        field.returnKeyType = .send
        field.delegate = self
        field.accessibilityLabel = "Текст повідомлення"
        field.addAction(UIAction { [weak self] _ in self?.updateSend() }, for: .editingChanged)
        let island = glassIsland()
        field.pin(to: island.contentView, insets: .init(top: 0, leading: 16, bottom: 0, trailing: 16))
        island.heightAnchor.constraint(equalToConstant: 48).isActive = true
        send.configuration?.image = UIImage(systemName: "arrow.up")
        send.accessibilityLabel = "Надіслати повідомлення"
        send.widthAnchor.constraint(equalToConstant: 48).isActive = true
        send.heightAnchor.constraint(equalToConstant: 48).isActive = true
        send.addAction(UIAction { [weak self] _ in self?.sendMessage() }, for: .primaryActionTriggered)
        let composer = UIStackView(arrangedSubviews: [island, send])
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
                if !messages.isEmpty { self.table.scrollToRow(at: IndexPath(row: messages.count - 1, section: 0), at: .bottom, animated: false) }
            } catch { if !Task.isCancelled { self.showMessage(error.localizedDescription) } }
        }
    }
    private func updateSend() {
        let text = (field.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        send.isEnabled = sendTask == nil && !text.isEmpty && text.count <= 4000 && accountID == store.active?.id
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
        sendTask = Task { [weak self] in
            guard let self else { return }
            defer { self.sendTask = nil; self.field.isEnabled = true; self.updateSend() }
            do {
                _ = try await self.repository.send(text: text, to: self.peer.id, id: id)
                self.field.text = ""
                self.retryID = nil
                self.retryText = nil
                self.loadMessages()
            } catch { self.showMessage(error.localizedDescription) }
        }
    }
    func textFieldShouldReturn(_ textField: UITextField) -> Bool { sendMessage(); return false }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let message = rows[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "message") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "message")
        var content = cell.defaultContentConfiguration()
        let mine = message.senderID == accountID
        content.text = message.text
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
    deinit { loadTask?.cancel(); sendTask?.cancel() }
}
