import Foundation
import Observation

struct Profile: Codable, Identifiable {
    let id: UUID
    let handle: String
    let name: String
    let bio: String
    let avatar: Data?
}

struct Clip: Codable, Identifiable {
    let id: String
    let authorID: UUID?
    let caption: String
    let file: String
    let credit: String

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
    let text: String
}

@Observable
final class LocalStore {
    struct State: Codable {
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
    private var state: State

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
    var allClips: [Clip] { state.clips + Clip.samples }

    func profile(_ id: UUID?) -> Profile? { state.profiles.first { $0.id == id } }

    func feed(_ section: FeedSection) -> [Clip] {
        switch section {
        case .saved:
            guard let id = state.activeID else { return [] }
            return allClips.filter { state.bookmarks[$0.id]?.contains(id) == true }
        case .following:
            guard let id = state.activeID else { return [] }
            let followed = state.following[id, default: []]
            return state.clips.filter { $0.authorID.map(followed.contains) ?? false }
        case .recommended:
            guard let id = state.activeID else { return allClips }
            let followed = state.following[id, default: []]
            let preferred = state.clips.filter { $0.authorID.map(followed.contains) ?? false }
            let others = state.clips.filter { !($0.authorID.map(followed.contains) ?? false) }
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
        }
        _ = save(next)
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
        if users.remove(id) == nil { users.insert(id) }
        next[keyPath: keyPath][clip.id] = users
        _ = save(next)
    }

    @discardableResult
    func addComment(_ text: String, to clip: Clip) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = state.activeID, !text.isEmpty, text.count <= 500 else { return false }
        var next = state
        next.comments[clip.id, default: []].append(Comment(id: UUID(), authorID: id, text: text))
        return save(next)
    }

    func publish(_ movie: URL, caption: String) -> Clip? {
        guard let authorID = state.activeID else { return nil }
        let id = UUID().uuidString
        let file = id + "." + movie.pathExtension
        let destination = Self.directory.appending(path: file)
        var next = state
        let clip = Clip(id: id, authorID: authorID, caption: caption, file: file, credit: "")
        next.clips.insert(clip, at: 0)
        do {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: movie, to: destination)
            if save(next) { return clip }
            try? FileManager.default.removeItem(at: destination)
        } catch {
            errorMessage = "Не вдалося зберегти відео."
        }
        return nil
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
