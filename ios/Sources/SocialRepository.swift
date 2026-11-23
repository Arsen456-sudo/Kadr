import Foundation

struct ChatMessage: Codable, Identifiable {
    let id: UUID
    let senderID: UUID
    let recipientID: UUID
    var text: String
    let createdAt: Date
    var replyTo: UUID? = nil
    var reactions: [String: String]? = nil
    var edited: Bool? = nil
    var attachmentFile: String? = nil
    var attachmentKind: String? = nil
    var postID: String? = nil
}

struct ConversationSummary: Codable, Identifiable {
    let profile: Profile
    let lastMessage: ChatMessage
    var id: UUID { profile.id }
}

enum SocialError: LocalizedError {
    case accountRequired, followRequired, unavailable, invalidMessage
    var errorDescription: String? {
        switch self {
        case .accountRequired: return "Спочатку увійди в акаунт."
        case .followRequired: return "Підпишись на користувача, щоб почати чат."
        case .unavailable: return "Не вдалося завантажити дані. Спробуй ще раз."
        case .invalidMessage: return "Повідомлення має містити від 1 до 4000 символів."
        }
    }
}

@MainActor
protocol SocialRepository {
    func search(handle: String) async throws -> [Profile]
    func setFollowing(_ following: Bool, profileID: UUID) async throws
    func conversations() async throws -> [ConversationSummary]
    func messages(with profileID: UUID) async throws -> [ChatMessage]
    func send(text: String, to profileID: UUID, id: UUID) async throws -> ChatMessage
}

@MainActor
final class LocalSocialRepository: SocialRepository {
    let store: LocalStore
    init(store: LocalStore) { self.store = store }
    func search(handle: String) async throws -> [Profile] { store.searchProfiles(handle) }
    func setFollowing(_ following: Bool, profileID: UUID) async throws {
        guard store.active != nil else { throw SocialError.accountRequired }
        guard let profile = store.profile(profileID) else { throw SocialError.unavailable }
        if store.follows(profile) != following { store.toggleFollow(profile) }
        if let error = store.errorMessage { throw NSError(domain: "Kadr.Storage", code: 1, userInfo: [NSLocalizedDescriptionKey: error]) }
    }
    func conversations() async throws -> [ConversationSummary] {
        guard store.active != nil else { throw SocialError.accountRequired }
        return store.conversations()
    }
    func messages(with profileID: UUID) async throws -> [ChatMessage] {
        guard store.active != nil else { throw SocialError.accountRequired }
        return store.messages(with: profileID)
    }
    func send(text: String, to profileID: UUID, id: UUID) async throws -> ChatMessage {
        let message = try store.sendMessage(text, to: profileID, id: id)
        try await store.flush()
        return message
    }
}

// Inject this implementation after server authentication is enabled. Tokens are
// supplied by the account session, never embedded in the public app or repository.
@MainActor
final class RemoteSocialRepository: SocialRepository {
    private struct Failure: Decodable { let error: String }
    private let baseURL: URL
    private let token: () async throws -> String
    private let session: URLSession
    init(baseURL: URL, session: URLSession = .shared, token: @escaping () async throws -> String) {
        self.baseURL = baseURL
        self.session = session
        self.token = token
    }
    private func request<T: Decodable>(_ path: String, method: String = "GET", body: Data? = nil,
                                       query: [URLQueryItem] = []) async throws -> T {
        guard baseURL.scheme == "https" else { throw SocialError.unavailable }
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 20
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw SocialError.unavailable }
        guard (200..<300).contains(response.statusCode) else {
            let message = (try? JSONDecoder().decode(Failure.self, from: data))?.error ?? SocialError.unavailable.localizedDescription
            throw NSError(domain: "Kadr.API", code: response.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }
    func search(handle: String) async throws -> [Profile] {
        try await request("users", query: [URLQueryItem(name: "handle", value: handle)])
    }
    func setFollowing(_ following: Bool, profileID: UUID) async throws {
        struct Result: Decodable { let following: Bool }
        let _: Result = try await request("users/\(profileID.uuidString)/follow", method: following ? "PUT" : "DELETE")
    }
    func conversations() async throws -> [ConversationSummary] { try await request("conversations") }
    func messages(with profileID: UUID) async throws -> [ChatMessage] {
        try await request("conversations/\(profileID.uuidString)/messages")
    }
    func send(text: String, to profileID: UUID, id: UUID) async throws -> ChatMessage {
        struct Body: Encodable { let id: UUID; let text: String }
        return try await request("conversations/\(profileID.uuidString)/messages", method: "POST",
                                 body: JSONEncoder().encode(Body(id: id, text: text)))
    }
}
