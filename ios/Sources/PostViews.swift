import AVFoundation
import CoreTransferable
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct CommentsSheet: View {
    let store: LocalStore
    let clip: Clip
    @State private var draft = ""
    @State private var showAccount = false
    @FocusState private var composing: Bool

    var body: some View {
        NavigationStack {
            List {
                if store.comments(clip).isEmpty {
                    ContentUnavailableView("Коментарів ще немає", systemImage: "bubble")
                }
                ForEach(store.comments(clip)) { comment in
                    if let author = store.profile(comment.authorID) {
                        HStack(alignment: .top, spacing: 10) {
                            Avatar(data: author.avatar, size: 34)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("@\(author.handle)").font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.peach)
                                Text(comment.text)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Коментарі")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Group {
                    if store.active == nil {
                        Button("Створи акаунт, щоб коментувати") { showAccount = true }
                            .buttonStyle(.borderedProminent)
                    } else {
                        HStack {
                            TextField("Написати коментар", text: $draft, axis: .vertical)
                                .lineLimit(1...4)
                                .focused($composing)
                            Button {
                                if store.addComment(draft, to: clip) {
                                    draft = ""
                                    composing = false
                                }
                            } label: {
                                Image(systemName: "arrow.up.circle.fill").font(.title2)
                            }
                            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                      || draft.count > 500)
                            .accessibilityLabel("Надіслати коментар")
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(.regularMaterial)
            }
        }
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showAccount) { AccountSheet(store: store) }
    }
}

struct PublishSheet: View {
    let publish: (URL, String) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var picker: PhotosPickerItem?
    @State private var movie: ImportedMovie?
    @State private var caption = ""
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        NavigationStack {
            Form {
                PhotosPicker(selection: $picker, matching: .videos) {
                    Label(movie == nil ? "Вибрати відео" : "Замінити відео", systemImage: "film")
                }
                if loading {
                    ProgressView("Відкриваємо відео…")
                } else if let movie {
                    LoopingVideo(url: movie.url, playing: true, muted: true)
                        .frame(height: 225)
                        .clipShape(.rect(cornerRadius: 16))
                }
                TextField("Опис відео", text: $caption, axis: .vertical)
                    .lineLimit(2...4)
                if let error { Text(error).foregroundStyle(.red) }
                Button("Опублікувати на пристрої") {
                    guard let movie else { return }
                    let description = caption.trimmingCharacters(in: .whitespacesAndNewlines)
                    if publish(movie.url, description.isEmpty ? "Нове відео" : String(description.prefix(200))) {
                        dismiss()
                    } else {
                        error = "Не вдалося опублікувати відео."
                    }
                }
                .disabled(movie == nil || loading)
            }
            .navigationTitle("Нове відео")
            .toolbar { Button("Скасувати", role: .cancel) { dismiss() } }
        }
        .task(id: picker) {
            guard let picker else { return }
            loading = true
            movie = nil
            error = nil
            do {
                guard let imported = try await picker.loadTransferable(type: ImportedMovie.self) else {
                    if !Task.isCancelled {
                        error = "Не вдалося імпортувати відео."
                        loading = false
                    }
                    return
                }
                let asset = AVURLAsset(url: imported.url)
                let isPlayable = try await asset.load(.isPlayable)
                let tracks = try await asset.loadTracks(withMediaType: .video)
                guard !Task.isCancelled else { return }
                if isPlayable && !tracks.isEmpty {
                    movie = imported
                } else {
                    error = "Цей відеофайл не підтримується."
                }
                loading = false
            } catch {
                if !Task.isCancelled {
                    self.error = "Не вдалося імпортувати відео."
                    loading = false
                }
            }
        }
    }
}

private final class ImportedMovie: Transferable, Sendable {
    let url: URL

    private init(url: URL) { self.url = url }

    deinit { try? FileManager.default.removeItem(at: url) }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let suffix = received.file.pathExtension
            let destination = FileManager.default.temporaryDirectory
                .appending(path: UUID().uuidString)
                .appendingPathExtension(suffix.isEmpty ? "mov" : suffix)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return ImportedMovie(url: destination)
        }
    }
}
