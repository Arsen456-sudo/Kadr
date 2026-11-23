import Foundation

struct Profile: Codable, Identifiable {
    let id: UUID
    let handle: String
    let name: String
    let bio: String
    var avatar: Data?
    var bannerFile: String? = nil
    var avatarRemoteURL: URL? = nil
    var avatarRevision: UUID? = nil

    var bannerURL: URL? { bannerFile.map { LocalStore.directory.appending(path: $0) } }
}

enum MediaKind: String, Codable { case video, photo }

struct PostMedia: Codable, Identifiable {
    let id: UUID
    let kind: MediaKind
    let file: String
    var remoteURL: URL?
    var url: URL { remoteURL ?? LocalStore.directory.appending(path: file) }
}

struct PostOptions: Codable {
    var tags: String = ""
    var location: String = ""
    var allowsComments: Bool = true
    var onlyMe: Bool = false
    var coverIndex: Int = 0
}

struct Clip: Codable, Identifiable {
    let id: String
    let authorID: UUID?
    var caption: String
    let file: String
    let credit: String
    var media: [PostMedia]? = nil
    var options: PostOptions? = nil
    var createdAt: Date? = nil
    var isDraft: Bool? = nil
    var extras: PostExtras? = nil

    var isPhoto: Bool { media?.first?.kind == .photo }
    var settings: PostOptions { options ?? PostOptions() }
    var coverURL: URL? {
        guard let media, !media.isEmpty else { return url }
        return media[min(max(0, settings.coverIndex), media.count - 1)].url
    }

    static let samples = [
        Clip(id: "bunny", authorID: nil, caption: "Big Buck Bunny",
             file: "bunny", credit: "Blender Foundation"),
        Clip(id: "sintel", authorID: nil, caption: "Sintel",
             file: "sintel", credit: "Blender Foundation")
    ]

    var url: URL? {
        if authorID == nil { return Bundle.main.url(forResource: file, withExtension: "mp4") }
        return LocalStore.directory.appending(path: file)
    }
}

struct Comment: Codable, Identifiable {
    let id: UUID
    let authorID: UUID
    var text: String
    var parentID: UUID? = nil
    var likes: Set<UUID>? = nil
    var pinned: Bool? = nil
    var createdAt: Date? = nil
}

final class LocalStore {
    struct State: Codable {
        var studio: StudioState? = nil
        var activity: [ActivityEntry]? = nil
        var messages: [ChatMessage]? = nil
        var profiles: [Profile] = []
        var activeID: UUID?
        var clips: [Clip] = []
        var likes: [String: Set<UUID>] = [:]
        var bookmarks: [String: Set<UUID>] = [:]
        var comments: [String: [Comment]] = [:]
        var following: [UUID: Set<UUID>] = [:]
    }

    static let directory = URL.applicationSupportDirectory.appending(path: "Kadr", directoryHint: .isDirectory)
    private static let stateFile = directory.appending(path: "state.json")
    private(set) var state: State

    init() {
        if FileManager.default.fileExists(atPath: Self.stateFile.path) {
            do {
                state = try JSONDecoder().decode(State.self, from: Data(contentsOf: Self.stateFile))
            } catch {
                state = State()
                errorMessage = "Не вдалося відкрити локальні дані."
                canSave = false
            }
        } else {
            state = State()
        }
    }

    var errorMessage: String?
    private var canSave = true
    var profiles: [Profile] { state.profiles }
    var active: Profile? { profile(state.activeID) }
    var allClips: [Clip] {
        (state.clips.filter { $0.isDraft != true && (!$0.settings.onlyMe || $0.authorID == state.activeID) } + Clip.samples).filter { clip in
            let preferences = studio.preferences
            return !preferences.hiddenPosts.contains(clip.id) && !(clip.authorID.map { preferences.blocked.contains($0) || preferences.hiddenAuthors.contains($0) } ?? false)
                && (preferences.mediaFilter == "all" || (preferences.mediaFilter == "photo") == clip.isPhoto)
        }
    }
    var draft: Clip? { state.clips.first { $0.authorID == state.activeID && $0.isDraft == true } }


    func profile(_ id: UUID?) -> Profile? { state.profiles.first { $0.id == id } }

    func feed(_ section: FeedSection) -> [Clip] {
        switch section {
        case .saved:
            guard let id = state.activeID else { return [] }
            return allClips.filter { state.bookmarks[$0.id]?.contains(id) == true }
        case .following:
            guard let id = state.activeID else { return [] }
            let followed = state.following[id, default: []]
            return allClips.filter { $0.authorID.map(followed.contains) ?? false }
        case .recommended:
            guard let id = state.activeID else { return allClips }
            let followed = state.following[id, default: []]
            let preferred = allClips.filter { $0.authorID.map(followed.contains) ?? false }
            let others = allClips.filter { $0.authorID != nil && !($0.authorID.map(followed.contains) ?? false) }
            let samples = id.uuid.0.isMultiple(of: 2) ? Clip.samples : Array(Clip.samples.reversed())
            return preferred + others + samples
        }
    }

    func follows(_ profile: Profile) -> Bool {
        guard let id = state.activeID else { return false }
        return state.following[id]?.contains(profile.id) == true
    }

    func toggleFollow(_ profile: Profile) {
        guard let id = state.activeID, id != profile.id else { return }
        var next = state
        if next.following[id, default: []].remove(profile.id) == nil {
            next.following[id, default: []].insert(profile.id)
            next.activity = (next.activity ?? []) + [ActivityEntry(recipientID: profile.id, actorID: id, kind: "follow")]
        }
        _ = save(next)
    }

    func searchProfiles(_ handle: String) -> [Profile] {
        let term = normalized(handle)
        return profiles.filter { !studio.preferences.blocked.contains($0.id) && (term.isEmpty || $0.handle.hasPrefix(term) || $0.name.localizedCaseInsensitiveContains(term) || $0.bio.localizedCaseInsensitiveContains(term)) }.sorted { $0.handle < $1.handle }
    }

    func messages(with peer: UUID) -> [ChatMessage] {
        guard let me = state.activeID else { return [] }
        return (state.messages ?? []).filter {
            ($0.senderID == me && $0.recipientID == peer) || ($0.senderID == peer && $0.recipientID == me)
        }.sorted { $0.createdAt < $1.createdAt }
    }

    func conversations() -> [ConversationSummary] {
        guard let me = state.activeID else { return [] }
        let mine = (state.messages ?? []).filter { $0.senderID == me || $0.recipientID == me }
        let peers = Set(mine.map { $0.senderID == me ? $0.recipientID : $0.senderID })
        return peers.compactMap { peer in
            guard let profile = profile(peer), let last = messages(with: peer).last else { return nil }
            return ConversationSummary(profile: profile, lastMessage: last)
        }.sorted { $0.lastMessage.createdAt > $1.lastMessage.createdAt }
    }

    func sendMessage(_ text: String, to peer: UUID, id: UUID) throws -> ChatMessage {
        guard let me = state.activeID else { throw SocialError.accountRequired }
        guard let profile = profile(peer), peer != me else { throw SocialError.unavailable }
        guard !studio.preferences.blocked.contains(peer) else { throw SocialError.unavailable }
        let recipient = state.studio?.accounts[peer.uuidString]?.preferences ?? AppPreferences()
        guard !recipient.blocked.contains(me), recipient.messagePermission != "nobody" else { throw SocialError.unavailable }
        guard follows(profile) || !messages(with: peer).isEmpty || recipient.messagePermission == "everyone" else { throw SocialError.followRequired }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 4000 else { throw SocialError.invalidMessage }
        if let existing = (state.messages ?? []).first(where: { $0.id == id }) {
            guard existing.senderID == me, existing.recipientID == peer, existing.text == text else { throw SocialError.unavailable }
            return existing
        }
        let message = ChatMessage(id: id, senderID: me, recipientID: peer, text: text, createdAt: Date())
        var next = state
        next.messages = (next.messages ?? []) + [message]
        guard save(next) else { throw SocialError.unavailable }
        NotificationCenter.default.post(name: .kadrMessagesDidChange, object: self)
        return message
    }

    private func normalized(_ handle: String) -> String {
        var handle = handle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if handle.hasPrefix("@") { handle.removeFirst() }
        return handle
    }

    func validate(handle: String) -> String? {
        let handle = normalized(handle)
        guard handle.range(of: #"^[a-z0-9_]{3,24}$"#, options: .regularExpression) != nil else {
            return "Нікнейм має містити 3–24 латинські літери, цифри або _."
        }
        guard !state.profiles.contains(where: { $0.handle == handle }) else {
            return "Цей @нікнейм уже зайнято. Зміни хоча б один символ."
        }
        return nil
    }

    func register(handle: String, name: String, bio: String, avatar: Data?) -> String? {
        if let error = validate(handle: handle) { return error }
        let handle = normalized(handle)
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "Введи імʼя." }
        let profile = Profile(id: UUID(), handle: handle, name: name, bio: bio, avatar: avatar)
        var next = state
        next.profiles.append(profile)
        next.activeID = profile.id
        return save(next) ? nil : "Не вдалося зберегти профіль."
    }

    func select(_ id: UUID?) {
        var next = state
        next.activeID = id
        _ = save(next)
    }

    @discardableResult
    func setAvatar(_ data: Data, for id: UUID) -> Bool {
        guard state.activeID == id, let index = state.profiles.firstIndex(where: { $0.id == id }) else { return false }
        var next = state
        next.profiles[index].avatar = data
        next.profiles[index].avatarRemoteURL = nil
        next.profiles[index].avatarRevision = UUID()
        guard save(next) else { return false }
        NotificationCenter.default.post(name: .kadrProfileDidChange, object: self, userInfo: ["profileID": id])
        return true
    }

    @discardableResult
    func setBanner(_ source: URL?, extension suffix: String, for id: UUID) -> Bool {
        guard state.activeID == id, let index = state.profiles.firstIndex(where: { $0.id == id }) else { return false }
        let old = state.profiles[index].bannerURL
        var next = state
        let name = source.map { _ in "banner-" + UUID().uuidString + "." + suffix }
        let destination = name.map { Self.directory.appending(path: $0) }
        next.profiles[index].bannerFile = name
        do {
            if let source, let destination {
                try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: source, to: destination)
            }
            guard save(next) else {
                if let destination { try? FileManager.default.removeItem(at: destination) }
                return false
            }
            if let old { try? FileManager.default.removeItem(at: old) }
            return true
        } catch {
            if let destination { try? FileManager.default.removeItem(at: destination) }
            errorMessage = "Не вдалося зберегти банер."
            return false
        }
    }

    func liked(_ clip: Clip) -> Bool { containsCurrentUser(in: state.likes[clip.id]) }
    func bookmarked(_ clip: Clip) -> Bool { containsCurrentUser(in: state.bookmarks[clip.id]) }
    func likes(_ clip: Clip) -> Int { state.likes[clip.id]?.count ?? 0 }
    func comments(_ clip: Clip) -> [Comment] { state.comments[clip.id] ?? [] }

    private func containsCurrentUser(in users: Set<UUID>?) -> Bool {
        guard let id = state.activeID else { return false }
        return users?.contains(id) == true
    }

    func toggleReaction(_ clip: Clip, bookmark: Bool = false) {
        guard let id = state.activeID else { return }
        var next = state
        let keyPath = bookmark ? \State.bookmarks : \State.likes
        var users = next[keyPath: keyPath][clip.id, default: []]
        if users.remove(id) == nil {
            users.insert(id)
            if !bookmark, let author = clip.authorID, author != id { next.activity = (next.activity ?? []) + [ActivityEntry(recipientID: author, actorID: id, kind: "like", postID: clip.id)] }
        }
        next[keyPath: keyPath][clip.id] = users
        _ = save(next)
    }

    @discardableResult
    func addComment(_ text: String, to clip: Clip, parentID: UUID? = nil) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clip.settings.allowsComments, let id = state.activeID, !text.isEmpty, text.count <= 500 else { return false }
        var next = state
        let commentPreferences = clip.authorID.flatMap { state.studio?.accounts[$0.uuidString]?.preferences } ?? AppPreferences()
        if let parentID, !comments(clip).contains(where: { $0.id == parentID }) { return false }
        guard !commentPreferences.mutedWords.contains(where: { !$0.isEmpty && text.localizedCaseInsensitiveContains($0) }) else { return false }
        next.comments[clip.id, default: []].append(Comment(id: UUID(), authorID: id, text: text, parentID: parentID, createdAt: Date()))
        if let author = clip.authorID, author != id {
            next.activity = (next.activity ?? []) + [ActivityEntry(recipientID: author, actorID: id, kind: "comment", postID: clip.id)]
        }
        return save(next)
    }

    func publish(_ movie: URL, caption: String) -> Clip? {
        savePost(sources: [(movie, .video)], caption: caption, options: PostOptions(), asDraft: false)
    }

    func savePost(sources: [(URL, MediaKind)], caption: String, options: PostOptions, asDraft: Bool) -> Clip? {
        guard let authorID = state.activeID, !sources.isEmpty else { return nil }
        guard sources.allSatisfy({ $0.1 == sources[0].1 }),
              sources[0].1 != .video || sources.count == 1 else {
            errorMessage = "Вибери одне відео або альбом фотографій."
            return nil
        }
        var copied: [URL] = []
        do {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            let media = try sources.map { source, kind -> PostMedia in
                let id = UUID()
                let file = id.uuidString + "." + source.pathExtension
                let destination = Self.directory.appending(path: file)
                try FileManager.default.copyItem(at: source, to: destination)
                copied.append(destination)
                return PostMedia(id: id, kind: kind, file: file)
            }
            let previousDraft = draft
            let post = Clip(id: UUID().uuidString, authorID: authorID, caption: caption,
                            file: media[0].file, credit: "", media: media, options: options,
                            createdAt: Date(), isDraft: asDraft)
            var next = state
            if let previousDraft { next.clips.removeAll { $0.id == previousDraft.id } }
            next.clips.insert(post, at: 0)
            guard save(next) else {
                for url in copied { try? FileManager.default.removeItem(at: url) }
                return nil
            }
            for item in previousDraft?.media ?? [] {
                try? FileManager.default.removeItem(at: Self.directory.appending(path: item.file))
            }
            return post
        } catch {
            for url in copied { try? FileManager.default.removeItem(at: url) }
            errorMessage = "Не вдалося зберегти публікацію. Перевір вільне місце."
            return nil
        }
    }

    @discardableResult
    func updateState(_ update: (inout State) -> Void) -> Bool {
        var next = state
        update(&next)
        return save(next)
    }

    private func save(_ next: State) -> Bool {
        guard canSave else {
            errorMessage = "Локальні дані недоступні для запису."
            return false
        }
        do {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: Self.stateFile, options: .atomic)
            state = next
            return true
        } catch {
            errorMessage = "Не вдалося зберегти зміни."
            return false
        }
    }
}

enum FeedSection: Equatable {
    case recommended, following, saved
}


extension Notification.Name {
    static let kadrMessagesDidChange = Notification.Name("Kadr.messagesDidChange")
    static let kadrProfileDidChange = Notification.Name("Kadr.profileDidChange")
}
