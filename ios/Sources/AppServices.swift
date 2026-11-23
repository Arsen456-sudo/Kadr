import Foundation

@MainActor
final class AppServices: SocialRepository {
    private let store: LocalStore
    private var backend: any SocialRepository
    private(set) var sync: FeatureSyncEngine?
    var social: any SocialRepository { self }
    init(store: LocalStore, serverURL: URL? = nil, token: (@Sendable () async throws -> String)? = nil) {
        self.store = store; backend = LocalSocialRepository(store: store)
        if let serverURL, let token { configure(serverURL: serverURL, token: token) }
    }
    func configure(serverURL: URL, token: @escaping @Sendable () async throws -> String) {
        let engine = FeatureSyncEngine(store: store, transport: HTTPFeatureTransport(baseURL: serverURL, token: token))
        sync = engine; backend = SyncedSocialRepository(store: store, engine: engine)
    }
    func search(handle: String) async throws -> [Profile] { try await backend.search(handle: handle) }
    func setFollowing(_ following: Bool, profileID: UUID) async throws { try await backend.setFollowing(following, profileID: profileID) }
    func conversations() async throws -> [ConversationSummary] { try await backend.conversations() }
    func messages(with profileID: UUID) async throws -> [ChatMessage] { try await backend.messages(with: profileID) }
    func send(text: String, to profileID: UUID, id: UUID) async throws -> ChatMessage { try await backend.send(text: text, to: profileID, id: id) }
}

@MainActor
private final class SyncedSocialRepository: SocialRepository {
    private let local: LocalSocialRepository
    private let engine: FeatureSyncEngine
    init(store: LocalStore, engine: FeatureSyncEngine) { local = LocalSocialRepository(store: store); self.engine = engine }
    func search(handle: String) async throws -> [Profile] { try await engine.synchronize(); return try await local.search(handle: handle) }
    func setFollowing(_ following: Bool, profileID: UUID) async throws { try await local.setFollowing(following, profileID: profileID); try await engine.synchronize() }
    func conversations() async throws -> [ConversationSummary] { try await engine.synchronize(); return try await local.conversations() }
    func messages(with profileID: UUID) async throws -> [ChatMessage] { try await engine.synchronize(); return try await local.messages(with: profileID) }
    func send(text: String, to profileID: UUID, id: UUID) async throws -> ChatMessage {
        let message = try await local.send(text: text, to: profileID, id: id)
        try await engine.synchronize(); return message
    }
}
