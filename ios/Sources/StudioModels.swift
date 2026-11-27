import Foundation

struct CreatorAppearance: Codable, Equatable {
    var theme = "minimal"
    var accent = "peach"
    var accentMode: String? = nil
    var introduction = ""
    var links: [String] = []
    var pinnedPosts: [String] = []
    var bannerStart: Double = 0
    var interests: [String] = []
}
struct SavedCollection: Codable, Identifiable {
    var id = UUID()
    var title: String
    var posts: [String] = []
    var cover: String?
}
struct WatchRecord: Codable {
    var postID: String
    var seconds: Double
    var duration: Double
    var updatedAt = Date()
    var completed: Bool { duration > 0 && seconds / duration > 0.9 }
}
struct AppPreferences: Codable {
    var haptics = true
    var autoSound = false
    var playbackRate: Float = 1
    var mediaFilter = "all"
    var messagePermission = "following"
    var blocked: Set<UUID> = []
    var hiddenPosts: Set<String> = []
    var hiddenAuthors: Set<UUID> = []
    var preferredTags: Set<String> = []
    var mutedWords: [String] = []
}
struct AccountStudio: Codable {
    var appearance = CreatorAppearance()
    var preferences = AppPreferences()
    var collections: [SavedCollection] = []
    var notes: [String: String] = [:]
    var watches: [String: WatchRecord] = [:]
    var feedPositions: [String: String] = [:]
    var searches: [String] = []
    var chatDrafts: [String: String] = [:]
    var pinnedChats: Set<UUID> = []
    var searchSort = "date"
    var dailyViews: [String: Int]? = nil
}
struct SyncMutation: Codable, Identifiable {
    var id = UUID()
    var owner: UUID
    var resource: String
    var entityID: String
    var payload: Data
    var createdAt = Date()
}
struct StudioState: Codable {
    var accounts: [String: AccountStudio] = [:]
    var outbox: [SyncMutation] = []
}
struct ActivityEntry: Codable, Identifiable {
    var id = UUID()
    var recipientID: UUID
    var actorID: UUID
    var kind: String
    var postID: String?
    var createdAt = Date()
}
struct PostExtras: Codable, Equatable {
    var photoCaptions: [String: String] = [:]
    var albumLayout = "fit"
    var hideLikes = false
    var trimStart: Double = 0
    var trimEnd: Double?
    var coverTime: Double = 0.5
    var collageGap: Double? = nil
    var coverFile: String?
}

extension LocalStore {
    var studio: AccountStudio { state.studio?.accounts[active?.id.uuidString ?? "guest"] ?? AccountStudio() }
    func changeStudio(_ update: (inout AccountStudio) -> Void) {
        updateState { state in
            var studio = state.studio ?? StudioState()
            let key = state.activeID?.uuidString ?? "guest"
            var account = studio.accounts[key] ?? AccountStudio()
            update(&account)
            studio.accounts[key] = account
            if let owner = state.activeID, let payload = try? JSONEncoder().encode(account) {
                studio.outbox.removeAll { $0.owner == owner && $0.resource == "preferences" }
                studio.outbox.append(SyncMutation(owner: owner, resource: "preferences", entityID: key, payload: payload))
            }
            state.studio = studio
        }
    }
    var drafts: [Clip] { state.clips.filter { $0.authorID == active?.id && $0.isDraft == true } }
    func editPost(_ clip: Clip, caption: String, options: PostOptions, extras: PostExtras) {
        guard let me = active?.id, clip.authorID == me else { return }
        updateState { state in
            guard let index = state.clips.firstIndex(where: { $0.id == clip.id }) else { return }
            state.clips[index].caption = caption
            state.clips[index].options = options
            state.clips[index].extras = extras
        }
    }
    func deletePost(_ clip: Clip) {
        guard let me = active?.id, me == clip.authorID else { return }
        updateState { $0.clips.removeAll { $0.id == clip.id } }
    }
    func people(followersOf id: UUID) -> [Profile] {
        profiles.filter { state.following[$0.id]?.contains(id) == true }
    }
    func people(followedBy id: UUID) -> [Profile] {
        profiles.filter { state.following[id]?.contains($0.id) == true }
    }
    func recordWatch(_ clip: Clip, seconds: Double, duration: Double) {
        guard seconds.isFinite, duration.isFinite else { return }
        changeStudio { account in
            account.watches[clip.id] = WatchRecord(postID: clip.id, seconds: seconds, duration: duration)
            let date = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            let key = String(format: "%04d-%02d-%02d", date.year ?? 0, date.month ?? 0, date.day ?? 0)
            var days = account.dailyViews ?? [:]; days[key, default: 0] += 1; account.dailyViews = days
        }
    }
    func addToCollection(_ clip: Clip, collectionID: UUID) {
        guard active != nil else { return }
        if !bookmarked(clip) { toggleReaction(clip, bookmark: true) }
        changeStudio { account in
            guard let index = account.collections.firstIndex(where: { $0.id == collectionID }) else { return }
            if !account.collections[index].posts.contains(clip.id) { account.collections[index].posts.append(clip.id) }
        }
    }
    func updateComment(_ comment: Comment, clip: Clip, text: String) {
        guard comment.authorID == active?.id, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 500 else { return }
        updateState { state in
            guard let index = state.comments[clip.id]?.firstIndex(where: { $0.id == comment.id }) else { return }
            state.comments[clip.id]?[index].text = text
        }
    }
    func deleteComment(_ comment: Comment, clip: Clip) {
        guard let me = active?.id, comment.authorID == me || clip.authorID == me else { return }
        updateState { $0.comments[clip.id]?.removeAll { $0.id == comment.id || $0.parentID == comment.id } }
    }
    func toggleCommentLike(_ comment: Comment, clip: Clip) {
        guard let me = active?.id else { return }
        updateState { state in
            guard let index = state.comments[clip.id]?.firstIndex(where: { $0.id == comment.id }) else { return }
            var likes = state.comments[clip.id]?[index].likes ?? []
            if likes.remove(me) == nil { likes.insert(me) }
            state.comments[clip.id]?[index].likes = likes
        }
    }
    func pinComment(_ comment: Comment, clip: Clip) {
        guard let me = active?.id, clip.authorID == me else { return }
        updateState { state in
            guard let comments = state.comments[clip.id] else { return }
            for index in comments.indices { state.comments[clip.id]?[index].pinned = comments[index].id == comment.id && comments[index].pinned != true }
        }
    }
    func editMessage(_ message: ChatMessage, text: String) {
        guard message.senderID == active?.id, !text.isEmpty, text.count <= 4000 else { return }
        updateState { state in
            guard let index = state.messages?.firstIndex(where: { $0.id == message.id }) else { return }
            state.messages?[index].text = text
            state.messages?[index].edited = true
        }
        NotificationCenter.default.post(name: .kadrMessagesDidChange, object: self)
    }
    func deleteMessage(_ message: ChatMessage) {
        guard message.senderID == active?.id else { return }
        updateState { $0.messages?.removeAll { $0.id == message.id } }
        NotificationCenter.default.post(name: .kadrMessagesDidChange, object: self)
    }
    func reactToMessage(_ message: ChatMessage, emoji: String) {
        guard let me = active?.id, message.senderID == me || message.recipientID == me else { return }
        updateState { state in
            guard let index = state.messages?.firstIndex(where: { $0.id == message.id }) else { return }
            var reactions = state.messages?[index].reactions ?? [:]
            reactions[me.uuidString] = reactions[me.uuidString] == emoji ? nil : emoji
            state.messages?[index].reactions = reactions
        }
        NotificationCenter.default.post(name: .kadrMessagesDidChange, object: self)
    }
}
