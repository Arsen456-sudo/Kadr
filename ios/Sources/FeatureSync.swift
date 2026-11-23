import Foundation

struct ResourceRecord: Codable {
    var owner: UUID
    var resource: String
    var entityID: String
    var payload: Data
}
struct SyncPage: Codable {
    var records: [ResourceRecord]
    var cursor: Int
}
protocol FeatureSyncTransport {
    func push(_ records: [ResourceRecord]) async throws
    func pull(after cursor: Int) async throws -> SyncPage
    func upload(file: URL) async throws
    func download(name: String) async throws -> URL
}

// Opt-in transport. The app never contacts a server without an injected session.
// Original files are uploaded byte-for-byte; incoming files are cached locally,
// so AVFoundation does not need embedded credentials or private streaming APIs.
struct HTTPFeatureTransport: FeatureSyncTransport {
    let baseURL: URL
    let token: @Sendable () async throws -> String
    var session = URLSession.shared
    private func request(_ path: String, method: String = "GET") async throws -> URLRequest {
        guard baseURL.scheme == "https" else { throw SocialError.unavailable }
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60
        return request
    }
    private func validate(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw SocialError.unavailable }
    }
    func push(_ records: [ResourceRecord]) async throws {
        var request = try await request("sync", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(records)
        let (_, response) = try await session.data(for: request); try validate(response)
    }
    func pull(after cursor: Int) async throws -> SyncPage {
        var request = try await request("sync")
        var components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "after", value: String(cursor))]; request.url = components.url
        let (data, response) = try await session.data(for: request); try validate(response)
        return try JSONDecoder().decode(SyncPage.self, from: data)
    }
    func upload(file: URL) async throws {
        let head = try await request("assets/" + file.lastPathComponent, method: "HEAD")
        let (_, headResponse) = try await session.data(for: head)
        if let response = headResponse as? HTTPURLResponse, response.statusCode == 200,
           let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, response.expectedContentLength == Int64(size) { return }
        let request = try await request("assets/" + file.lastPathComponent, method: "PUT")
        let (_, response) = try await session.upload(for: request, fromFile: file); try validate(response)
    }
    func download(name: String) async throws -> URL {
        guard URL(fileURLWithPath: name).lastPathComponent == name, !name.contains("..") else { throw SocialError.unavailable }
        let (file, response) = try await session.download(for: request("assets/" + name)); try validate(response)
        let target = LocalStore.directory.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: target.path) { try FileManager.default.moveItem(at: file, to: target) }
        return target
    }
}

struct CommentResource: Codable { var postID: String; var comment: Comment }
struct ReactionResource: Codable { var postID: String; var liked: Bool; var bookmarked: Bool }
struct FollowingResource: Codable { var ids: Set<UUID> }
struct MessageReactionResource: Codable { var messageID: UUID; var emoji: String }
struct CommentReactionResource: Codable { var postID: String; var commentID: UUID; var liked: Bool }
struct CommentPinResource: Codable { var postID: String; var commentID: UUID? }

@MainActor
final class FeatureSyncEngine {
    private let store: LocalStore
    private let transport: any FeatureSyncTransport
    private var syncing = false
    private var capturedRevision = 0
    init(store: LocalStore, transport: any FeatureSyncTransport) { self.store = store; self.transport = transport }
    func synchronize() async throws {
        guard !syncing, let owner = store.active?.id else { return }
        syncing = true; defer { syncing = false }
        try await store.flush()
        let snapshot = store.state
        capturedRevision = store.localRevision
        let records = try await Task.detached(priority: .utility) { try Self.records(snapshot, owner: owner) }.value
        let files = Set(snapshot.clips.filter { $0.authorID == owner }.flatMap { ($0.media ?? []).map(\.file) })
            .union(snapshot.profiles.filter { $0.id == owner }.compactMap(\.bannerFile))
            .union(snapshot.messages?.filter { $0.senderID == owner }.compactMap(\.attachmentFile) ?? [])
        for file in files {
            guard URL(fileURLWithPath: file).lastPathComponent == file, !file.contains("..") else { throw SocialError.unavailable }
            try await transport.upload(file: LocalStore.directory.appendingPathComponent(file))
        }
        // Bounded batches prevent a large history or conversation from making a
        // single oversized request. A failed batch is safe to retry as an upsert.
        for start in stride(from: 0, to: records.count, by: 50) { try await transport.push(Array(records[start..<min(start + 50, records.count)])) }
        guard store.active?.id == owner else { return }
        var cursor = 0
        while true {
            let page = try await transport.pull(after: cursor)
            guard store.active?.id == owner else { return }
            for record in page.records {
                if ["post", "draft"].contains(record.resource), let clip = try? JSONDecoder().decode(Clip.self, from: record.payload) {
                    for media in clip.media ?? [] where !FileManager.default.fileExists(atPath: media.url.path) { _ = try await transport.download(name: media.file) }
                }
                if record.resource == "profile", let profile = try? JSONDecoder().decode(Profile.self, from: record.payload), let file = profile.bannerFile,
                   !FileManager.default.fileExists(atPath: LocalStore.directory.appendingPathComponent(file).path) { _ = try await transport.download(name: file) }
                if record.resource == "message", let message = try? JSONDecoder().decode(ChatMessage.self, from: record.payload), let file = message.attachmentFile,
                   !FileManager.default.fileExists(atPath: LocalStore.directory.appendingPathComponent(file).path) { _ = try await transport.download(name: file) }
                apply(record, owner: owner)
            }
            if page.cursor <= cursor { break }
            cursor = page.cursor
        }
        store.updateState { state in state.studio?.outbox.removeAll { $0.owner == owner && $0.createdAt <= (snapshot.studio?.outbox.map(\.createdAt).max() ?? .distantPast) } }
        try await store.flush()
    }
    nonisolated private static func records(_ state: LocalStore.State, owner: UUID) throws -> [ResourceRecord] {
        let encoder = JSONEncoder()
        var result: [ResourceRecord] = []
        func add<T: Encodable>(_ resource: String, id: String, value: T) throws { result.append(ResourceRecord(owner: owner, resource: resource, entityID: id, payload: try encoder.encode(value))) }
        if let profile = state.profiles.first(where: { $0.id == owner }) { try add("profile", id: owner.uuidString, value: profile) }
        for clip in state.clips where clip.authorID == owner {
            try add(clip.isDraft == true ? "draft" : "post", id: clip.id, value: clip)
            if clip.isDraft != true { result.append(ResourceRecord(owner: owner, resource: "draft", entityID: clip.id, payload: Data("{\"deleted\":true}".utf8))) }
        }
        for (postID, comments) in state.comments {
            for comment in comments {
                if comment.authorID == owner {
                    var content = comment; content.likes = nil; content.pinned = nil
                    try add("comment", id: comment.id.uuidString, value: CommentResource(postID: postID, comment: content))
                }
                try add("commentReaction", id: comment.id.uuidString, value: CommentReactionResource(postID: postID, commentID: comment.id, liked: comment.likes?.contains(owner) == true))
            }
            if state.clips.contains(where: { $0.id == postID && $0.authorID == owner }) {
                try add("commentPin", id: postID, value: CommentPinResource(postID: postID, commentID: comments.first(where: { $0.pinned == true })?.id))
            }
        }
        let postIDs = Set(state.likes.keys).union(state.bookmarks.keys)
        for id in postIDs { try add("reaction", id: id, value: ReactionResource(postID: id, liked: state.likes[id]?.contains(owner) == true, bookmarked: state.bookmarks[id]?.contains(owner) == true)) }
        try add("following", id: owner.uuidString, value: FollowingResource(ids: state.following[owner] ?? []))
        for message in state.messages ?? [] where message.senderID == owner || message.recipientID == owner {
            if message.senderID == owner { var value = message; value.reactions = nil; try add("message", id: message.id.uuidString, value: value) }
            try add("messageReaction", id: message.id.uuidString, value: MessageReactionResource(messageID: message.id, emoji: message.reactions?[owner.uuidString] ?? ""))
        }
        if let account = state.studio?.accounts[owner.uuidString] {
            try add("preferences", id: owner.uuidString, value: account)
            try add("appearance", id: owner.uuidString, value: account.appearance)
        }
        for mutation in state.studio?.outbox ?? [] where mutation.owner == owner && mutation.resource != "preferences" {
            result.append(ResourceRecord(owner: owner, resource: mutation.resource, entityID: mutation.entityID, payload: mutation.payload))
        }
        return result
    }
    private func apply(_ record: ResourceRecord, owner: UUID) {
        guard !store.isRestoringBackup else { return }
        if record.owner == owner, store.localRevision != capturedRevision { return }
        store.isApplyingRemote = true; defer { store.isApplyingRemote = false }
        let decoder = JSONDecoder()
        if let object = try? JSONSerialization.jsonObject(with: record.payload) as? [String: Any], object["deleted"] as? Bool == true {
            store.updateState { state in
                switch record.resource {
                case "post", "draft": state.clips.removeAll { $0.id == record.entityID && $0.authorID == record.owner && ($0.isDraft == true) == (record.resource == "draft") }
                case "message": state.messages?.removeAll { $0.id.uuidString.lowercased() == record.entityID.lowercased() && $0.senderID == record.owner }
                case "comment": for id in Array(state.comments.keys) { state.comments[id]?.removeAll { $0.id.uuidString.lowercased() == record.entityID.lowercased() && $0.authorID == record.owner } }
                default: break
                }
            }; return
        }
        store.updateState { state in
            switch record.resource {
            case "profile":
                if let value = try? decoder.decode(Profile.self, from: record.payload), value.id == record.owner {
                    if let index = state.profiles.firstIndex(where: { $0.id == value.id }) { state.profiles[index] = value } else { state.profiles.append(value) }
                }
            case "post", "draft":
                if let value = try? decoder.decode(Clip.self, from: record.payload), value.authorID == record.owner {
                    if let index = state.clips.firstIndex(where: { $0.id == value.id }) { state.clips[index] = value } else { state.clips.append(value) }
                }
            case "comment":
                if var value = try? decoder.decode(CommentResource.self, from: record.payload), value.comment.authorID == record.owner {
                    if let index = state.comments[value.postID]?.firstIndex(where: { $0.id == value.comment.id }) {
                        value.comment.likes = state.comments[value.postID]?[index].likes; value.comment.pinned = state.comments[value.postID]?[index].pinned
                        state.comments[value.postID]?[index] = value.comment
                    }
                    else { state.comments[value.postID, default: []].append(value.comment) }
                }
            case "message":
                if var value = try? decoder.decode(ChatMessage.self, from: record.payload), value.senderID == owner || value.recipientID == owner {
                    if let index = state.messages?.firstIndex(where: { $0.id == value.id }) { value.reactions = state.messages?[index].reactions; state.messages?[index] = value } else { state.messages = (state.messages ?? []) + [value] }
                }
            case "messageReaction":
                if let value = try? decoder.decode(MessageReactionResource.self, from: record.payload), let index = state.messages?.firstIndex(where: { $0.id == value.messageID }) {
                    var reactions = state.messages?[index].reactions ?? [:]
                    reactions[record.owner.uuidString] = value.emoji.isEmpty ? nil : value.emoji; state.messages?[index].reactions = reactions
                }
            case "commentReaction":
                if let value = try? decoder.decode(CommentReactionResource.self, from: record.payload), let index = state.comments[value.postID]?.firstIndex(where: { $0.id == value.commentID }) {
                    var likes = state.comments[value.postID]?[index].likes ?? []
                    if value.liked { likes.insert(record.owner) } else { likes.remove(record.owner) }
                    state.comments[value.postID]?[index].likes = likes
                }
            case "commentPin":
                if let value = try? decoder.decode(CommentPinResource.self, from: record.payload), let comments = state.comments[value.postID] {
                    for index in comments.indices { state.comments[value.postID]?[index].pinned = comments[index].id == value.commentID }
                }
            case "following": if let value = try? decoder.decode(FollowingResource.self, from: record.payload) { state.following[record.owner] = value.ids }
            case "reaction":
                if let value = try? decoder.decode(ReactionResource.self, from: record.payload) {
                    if value.liked { state.likes[value.postID, default: []].insert(record.owner) } else { state.likes[value.postID]?.remove(record.owner) }
                    if record.owner == owner { if value.bookmarked { state.bookmarks[value.postID, default: []].insert(owner) } else { state.bookmarks[value.postID]?.remove(owner) } }
                }
            case "appearance":
                if let value = try? decoder.decode(CreatorAppearance.self, from: record.payload) {
                    var studio = state.studio ?? StudioState(); var account = studio.accounts[record.owner.uuidString] ?? AccountStudio()
                    account.appearance = value; studio.accounts[record.owner.uuidString] = account; state.studio = studio
                }
            case "preferences":
                if record.owner == owner, let value = try? decoder.decode(AccountStudio.self, from: record.payload) {
                    var studio = state.studio ?? StudioState(); studio.accounts[owner.uuidString] = value; state.studio = studio
                }
            default: break
            }
        }
    }
}
