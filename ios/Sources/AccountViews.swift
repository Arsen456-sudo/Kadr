import PhotosUI
import SwiftUI
import UIKit

struct AccountSheet: View {
    let store: LocalStore
    @Environment(\.dismiss) private var dismiss
    @State private var signingUp = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 65))
                        .foregroundStyle(Color.peach)
                        .accessibilityHidden(true)
                    Text("Профіль у Кадрі").font(.largeTitle.bold())
                    Text("Створи локальний профіль, щоб ставити лайки, коментувати й додавати відео на цьому пристрої.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Створити локальний акаунт") { signingUp = true }
                        .buttonStyle(.borderedProminent)
                    ForEach(store.profiles) { profile in
                        Button("Продовжити як @\(profile.handle)") {
                            store.select(profile.id)
                            if store.active?.id == profile.id { dismiss() }
                        }
                        .buttonStyle(.bordered)
                    }
                    Button("Дивитися без акаунта") { dismiss() }
                }
                .frame(maxWidth: .infinity)
                .padding(28)
            }
            .navigationDestination(isPresented: $signingUp) {
                SetupProfileView(store: store) { dismiss() }
            }
        }
    }
}

private struct SetupProfileView: View {
    enum Step { case avatar, handle, name }

    let store: LocalStore
    let finished: () -> Void
    @State private var step = Step.avatar
    @State private var picker: PhotosPickerItem?
    @State private var avatar: Data?
    @State private var handle = ""
    @State private var name = ""
    @State private var bio = ""
    @State private var error: String?

    var body: some View {
        Form {
            switch step {
            case .avatar:
                Section {
                    Avatar(data: avatar, size: 94)
                        .frame(maxWidth: .infinity)
                    PhotosPicker(selection: $picker, matching: .images) {
                        Label("Вибрати фото", systemImage: "photo")
                    }
                }
                Button(avatar == nil ? "Пропустити" : "Далі") { advance(to: .handle) }
            case .handle:
                HStack {
                    Text("@").foregroundStyle(Color.peach)
                    TextField("нікнейм", text: $handle)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                }
                Button("Далі", action: validateHandle)
                Button("Назад") { advance(to: .avatar) }
            case .name:
                TextField("Імʼя", text: $name)
                TextField("Опис профілю", text: $bio, axis: .vertical)
                    .lineLimit(2...4)
                Button("Завершити", action: create)
                Button("Назад") { advance(to: .handle) }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle(title)
        .task(id: picker) {
            guard let picker else { return }
            do {
                guard let data = try await picker.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    error = "Не вдалося відкрити фото."
                    return
                }
                guard !Task.isCancelled else { return }
                let size = CGSize(width: 300, height: 300)
                let scale = max(size.width / image.size.width, size.height / image.size.height)
                let fitted = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                avatar = UIGraphicsImageRenderer(size: size).jpegData(withCompressionQuality: 0.82) { _ in
                    image.draw(in: CGRect(x: (size.width - fitted.width) / 2,
                                          y: (size.height - fitted.height) / 2,
                                          width: fitted.width, height: fitted.height))
                }
                error = nil
            } catch {
                if !Task.isCancelled { self.error = "Не вдалося відкрити фото." }
            }
        }
    }

    private var title: String {
        switch step {
        case .avatar: "Фото профілю"
        case .handle: "Нікнейм"
        case .name: "Твоє імʼя"
        }
    }

    private func advance(to next: Step) {
        error = nil
        withAnimation(.easeInOut(duration: 0.2)) { step = next }
    }

    private func validateHandle() {
        error = store.validate(handle: handle)
        if error == nil { advance(to: .name) }
    }

    private func create() {
        error = store.register(handle: handle, name: String(name.prefix(60)),
                               bio: String(bio.prefix(200)), avatar: avatar)
        if error == nil { finished() }
    }
}

struct Avatar: View {
    let data: Data?
    let size: CGFloat

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(Color.peach)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

struct SearchSheet: View {
    let store: LocalStore
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                if matches.isEmpty {
                    ContentUnavailableView("Немає профілів", systemImage: "magnifyingglass")
                }
                ForEach(matches) { profile in
                    NavigationLink {
                        ProfileView(store: store, profile: profile,
                                    isOwnProfile: profile.id == store.active?.id)
                    } label: {
                        HStack {
                            Avatar(data: profile.avatar, size: 38)
                            VStack(alignment: .leading) {
                                Text(profile.name)
                                Text("@\(profile.handle)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Пошук профілів")
            .searchable(text: $query, prompt: "@нікнейм")
        }
    }

    private var matches: [Profile] {
        let handle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        return store.profiles.filter { handle.isEmpty || $0.handle.hasPrefix(handle) }
            .sorted { $0.handle < $1.handle }
    }
}

struct ProfileView: View {
    let store: LocalStore
    let profile: Profile
    let isOwnProfile: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Clip?

    private var posts: [Clip] { store.allClips.filter { $0.authorID == profile.id } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                RoundedRectangle(cornerRadius: 26)
                    .fill(LinearGradient(colors: [.peach.opacity(0.8), .indigo.opacity(0.65), .black],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(height: 136)
                    .overlay(alignment: .bottomLeading) {
                        Avatar(data: profile.avatar, size: 76)
                            .overlay(Circle().stroke(.white.opacity(0.55), lineWidth: 2))
                            .padding(12)
                    }
                    .accessibilityHidden(true)
                Text(profile.name).font(.title.bold())
                Text("@\(profile.handle)").foregroundStyle(.secondary)
                if !profile.bio.isEmpty { Text(profile.bio) }
                if !isOwnProfile && store.active != nil {
                    Button(store.follows(profile) ? "Відписатися" : "Підписатися") {
                        store.toggleFollow(profile)
                    }
                    .buttonStyle(.borderedProminent)
                }
                Divider().padding(.vertical, 6)
                Text("Публікації").font(.headline)
                if posts.isEmpty { Text("Поки немає відео").foregroundStyle(.secondary) }
                ForEach(posts) { clip in
                    Button {
                        selected = clip
                    } label: {
                        Label(clip.caption, systemImage: "play.rectangle.fill")
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(18)
        }
        .navigationTitle("Профіль")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isOwnProfile {
                Button("Вийти") {
                    store.select(nil)
                    if store.active == nil { dismiss() }
                }
            }
        }
        .sheet(item: $selected) { clip in
            if let url = clip.url {
                LoopingVideo(url: url, playing: true, muted: false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black)
                    .ignoresSafeArea()
            }
        }
    }
}
