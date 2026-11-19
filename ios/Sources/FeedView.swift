import AVFoundation
import SwiftUI
import UIKit

struct FeedView: View {
    let store: LocalStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var selectedID: String?
    @State private var section = FeedSection.recommended
    @State private var paused = false
    @State private var muted = true
    @State private var sheet: FeedSheet?

    private var clips: [Clip] { store.feed(section) }
    private var selected: Clip? { clips.first { $0.id == selectedID } ?? clips.first }

    var body: some View {
        GeometryReader { geometry in
            let insets = geometry.safeAreaInsets
            ZStack {
                Color.black
                if clips.isEmpty {
                    if section == .saved {
                        ContentUnavailableView("Немає збережених відео", systemImage: "bookmark")
                    } else {
                        ContentUnavailableView("Немає відео від підписок", systemImage: "person.2")
                    }
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(clips) { clip in
                                videoPage(clip)
                                    .id(clip.id)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollIndicators(.hidden)
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $selectedID)
                    .onChange(of: selectedID) { _, _ in paused = false }
                }

                VStack {
                    header
                    Spacer()
                    if let clip = selected {
                        actions(clip)
                        caption(clip)
                    }
                    navigation
                }
                .padding(.horizontal, 18)
                .padding(.top, insets.top + 8)
                .padding(.bottom, insets.bottom + 10)
            }
            .ignoresSafeArea()
        }
        .background(Color.black)
        .onAppear {
            if !hasSeenWelcome && store.active == nil {
                hasSeenWelcome = true
                sheet = .account
            }
        }
        .onChange(of: store.active?.id) { _, _ in
            section = .recommended
            selectedID = clips.first?.id
            paused = false
        }
        .sheet(item: $sheet) { destination in
            switch destination {
            case .account:
                AccountSheet(store: store)
            case let .comments(clip):
                CommentsSheet(store: store, clip: clip)
                    .presentationDetents([.medium, .large])
            case .search:
                SearchSheet(store: store)
            case .profile:
                if let profile = store.active {
                    NavigationStack {
                        ProfileView(store: store, profile: profile, isOwnProfile: true)
                    }
                }
            case .publish:
                PublishSheet { url, caption in
                    if let clip = store.publish(url, caption: caption) {
                        section = .recommended
                        selectedID = clip.id
                        return true
                    }
                    return false
                }
            }
        }
        .alert("Локальні дані", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("Гаразд", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private func videoPage(_ clip: Clip) -> some View {
        ZStack {
            Color.black
            if let url = clip.url {
                LoopingVideo(url: url, playing: selected?.id == clip.id && !paused
                             && sheet == nil && scenePhase == .active, muted: muted)
            }
            LinearGradient(colors: [.black.opacity(0.50), .clear, .clear, .black.opacity(0.78)],
                           startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
            if paused && selected?.id == clip.id {
                Image(systemName: "play.fill")
                    .font(.system(size: 34))
                    .frame(width: 76, height: 76)
                    .glassEffect(in: .circle)
                    .allowsHitTesting(false)
            }
        }
        .containerRelativeFrame([.horizontal, .vertical])
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { paused.toggle() }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(paused ? "Відтворити" : "Призупинити")
        .accessibilityAction { paused.toggle() }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 2) {
                feedTab("Для тебе", destination: .recommended)
                feedTab("Підписки", destination: .following)
            }
            .padding(4)
            .glassEffect(in: .capsule)
            Spacer()
            roundButton("magnifyingglass", label: "Пошук") { sheet = .search }
        }
    }

    private func feedTab(_ title: String, destination: FeedSection) -> some View {
        Button {
            if destination == .following {
                withAccount { changeFeed(to: destination) }
            } else {
                changeFeed(to: destination)
            }
        } label: {
            Text(title)
                .font(.subheadline.weight(section == destination ? .semibold : .medium))
                .padding(.horizontal, 10)
                .frame(height: 44)
                .background(section == destination ? Color.peach.opacity(0.22) : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(section == destination ? .isSelected : [])
    }

    private func actions(_ clip: Clip) -> some View {
        HStack {
            Spacer()
            VStack(spacing: 10) {
                actionButton(store.liked(clip) ? "heart.fill" : "heart", label: "Подобається",
                             count: store.likes(clip), active: store.liked(clip)) {
                    withAccount {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.58)) {
                            store.toggleReaction(clip)
                        }
                    }
                }
                actionButton("bubble", label: "Коментарі", count: store.comments(clip).count) {
                    sheet = .comments(clip)
                }
                actionButton(store.bookmarked(clip) ? "bookmark.fill" : "bookmark",
                             label: "Зберегти", active: store.bookmarked(clip)) {
                    withAccount { store.toggleReaction(clip, bookmark: true) }
                }
            }
            .padding(.vertical, 8)
            .glassEffect(in: .capsule)
        }
    }

    private func caption(_ clip: Clip) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(store.profile(clip.authorID).map { "@\($0.handle)" } ?? clip.credit)
                .font(.headline)
            Text(clip.caption)
                .font(.subheadline)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .shadow(color: .black.opacity(0.8), radius: 4)
        .padding(.bottom, 12)
    }

    private var navigation: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                navButton("house.fill", label: "Стрічка", active: section != .saved) {
                    changeFeed(to: .recommended)
                }
                navButton("bookmark", label: "Збережені відео", active: section == .saved) {
                    withAccount { changeFeed(to: .saved) }
                }
                navButton("person.crop.circle", label: "Профіль", active: false) {
                    withAccount { sheet = .profile }
                }
            }
            .padding(5)
            .glassEffect(in: .capsule)
            roundButton("plus", label: "Додати відео") { withAccount { sheet = .publish } }
            roundButton(muted ? "speaker.slash" : "speaker.wave.2", label: muted ? "Увімкнути звук" : "Вимкнути звук") {
                muted.toggle()
            }
        }
    }

    private func actionButton(_ symbol: String, label: String, count: Int? = nil,
                              active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 23, weight: .medium))
                    .scaleEffect(active ? 1.12 : 1)
                    .contentTransition(.symbolEffect(.replace))
                if let count { Text(count.formatted()).font(.caption2.weight(.semibold)) }
            }
            .frame(width: 58, height: 48)
            .foregroundStyle(active ? Color.peach : .white)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(count.map { $0.formatted() } ?? ""))
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func navButton(_ symbol: String, label: String, active: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(active ? Color.peach : .white)
                .frame(width: 56, height: 44)
                .background(active ? Color.peach.opacity(0.20) : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func roundButton(_ symbol: String, label: String,
                             action: @escaping () -> Void) -> some View {
        GlassIconButton(symbol: symbol, label: label, action: action)
            .frame(width: 48, height: 48)
    }

    private func changeFeed(to destination: FeedSection) {
        withAnimation(.easeInOut(duration: 0.22)) {
            section = destination
            selectedID = clips.first?.id
            paused = false
        }
    }

    private func withAccount(_ action: () -> Void) {
        if store.active == nil { sheet = .account } else { action() }
    }
}

private struct GlassIconButton: UIViewRepresentable {
    let symbol: String
    let label: String
    let action: () -> Void

    final class Coordinator {
        var action: () -> Void

        init(action: @escaping () -> Void) { self.action = action }
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeUIView(context: Context) -> UIButton {
        let coordinator = context.coordinator
        return UIButton(configuration: .glass(), primaryAction: UIAction { _ in coordinator.action() })
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.action = action
        var configuration = UIButton.Configuration.glass()
        configuration.image = UIImage(systemName: symbol,
                                     withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold))
        configuration.cornerStyle = .capsule
        configuration.baseForegroundColor = .white
        button.configuration = configuration
        button.accessibilityLabel = label
    }
}

private enum FeedSheet: Identifiable {
    case account, comments(Clip), search, profile, publish

    var id: String {
        switch self {
        case .account: "account"
        case let .comments(clip): "comments-\(clip.id)"
        case .search: "search"
        case .profile: "profile"
        case .publish: "publish"
        }
    }
}

struct LoopingVideo: UIViewRepresentable {
    let url: URL
    let playing: Bool
    let muted: Bool

    func makeUIView(context: Context) -> VideoSurface { VideoSurface() }

    func updateUIView(_ view: VideoSurface, context: Context) {
        view.update(url: url, playing: playing, muted: muted)
    }

    static func dismantleUIView(_ view: VideoSurface, coordinator: ()) { view.stop() }
}

final class VideoSurface: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    private var url: URL?
    private var looper: AVPlayerLooper?

    func update(url: URL, playing: Bool, muted: Bool) {
        if url != self.url {
            stop()
            self.url = url
            let player = AVQueuePlayer()
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            playerLayer.videoGravity = .resizeAspectFill
            playerLayer.player = player
        }
        playerLayer.player?.isMuted = muted
        if playing { playerLayer.player?.play() } else { playerLayer.player?.pause() }
    }

    func stop() {
        playerLayer.player?.pause()
        looper?.disableLooping()
        looper = nil
        playerLayer.player = nil
        url = nil
    }
}
