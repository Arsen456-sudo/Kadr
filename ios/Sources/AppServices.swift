import Foundation

@MainActor
final class AppServices {
    let social: any SocialRepository
    let sync: FeatureSyncEngine?
    // Supply a verified server identity and refreshable access-token provider when
    // enabling networking. Leaving the arguments unset is a fully offline app.
    init(store: LocalStore, serverURL: URL? = nil, token: (@Sendable () async throws -> String)? = nil) {
        if let serverURL, let token {
            let engine = FeatureSyncEngine(store: store, transport: HTTPFeatureTransport(baseURL: serverURL, token: token))
            sync = engine; social = SyncedSocialRepository(store: store, engine: engine)
        } else { sync = nil; social = LocalSocialRepository(store: store) }
    }
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
