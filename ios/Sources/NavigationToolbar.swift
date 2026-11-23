import SwiftUI
import UIKit

@MainActor
final class KadrToolbarState: ObservableObject {
    enum Screen: Equatable {
        case feed, saved, inbox, profile

        var title: String {
            switch self {
            case .feed: return ""
            case .saved: return "Збережене"
            case .inbox: return "Вхідні"
            case .profile: return "Профіль"
            }
        }
    }

    struct Context: Equatable {
        var screen: Screen
        var canSignOut: Bool
        var hasBanner: Bool = false
        var usesPortrait: Bool = false
    }

    @Published var context = Context(screen: .feed, canSignOut: false)
    var screen: Screen { context.screen }
    var canSignOut: Bool { context.canSignOut }
    var hasBanner: Bool { context.hasBanner }
    var usesPortrait: Bool { context.usesPortrait }
    @Published var immersive = false
    @Published var feedSection = FeedSection.recommended
    @Published var overview = false
    @Published var compactTitle: String?
    @Published var profileDocked = false
    @Published var profileSection = ProfileSection.posts
    var onSection: ((FeedSection) -> Void)?
    var onOverview: (() -> Void)?
    var onStudio: (() -> Void)?
    var onSearch: (() -> Void)?
    var onSignOut: (() -> Void)?
    var onChooseBanner: (() -> Void)?
    var onRemoveBanner: (() -> Void)?
    var onImmersive: (() -> Void)?
    var onProfileSection: ((ProfileSection) -> Void)?
}

struct KadrNavigationShell: View {
    let tabs: KadrTabs
    @ObservedObject var state: KadrToolbarState

    var body: some View {
        NavigationStack {
            KadrTabContent(tabs: tabs)
                .ignoresSafeArea(.container)
                .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
                .navigationTitle(state.screen == .profile ? (state.compactTitle ?? state.screen.title) : state.screen.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(id: "header.action", placement: .topBarTrailing) {
                        Button {
                            if state.canSignOut { state.onSignOut?() } else { state.onSearch?() }
                        } label: {
                            if state.canSignOut { Text("Вийти") }
                            else { Image(systemName: "magnifyingglass") }
                        }
                        .accessibilityLabel(state.canSignOut ? "Вийти" : "Пошук")
                        .accessibilityIdentifier("header.action")
                    }
                    if state.screen == .feed {
                        ToolbarItem(placement: .principal) {
                            FeedPickerContent(state: state)
                                .frame(width: 236, height: 44)
                        }
                        .sharedBackgroundVisibility(.hidden)
                    } else if state.screen == .profile && state.profileDocked {
                        ToolbarItem(placement: .principal) {
                            ProfilePickerContent(state: state)
                                .frame(width: min(216, max(132, tabs.view.bounds.width - 172)), height: 44)
                        }
                        .sharedBackgroundVisibility(.hidden)
                    }
                    ToolbarItem(id: "header.leading", placement: .topBarLeading) {
                        if state.screen == .feed {
                            immersiveButton
                        } else if state.canSignOut {
                            Menu {
                                Button { state.onStudio?() } label: { Label("Студія та налаштування", systemImage: "slider.horizontal.3") }
                                Button {
                                    state.onChooseBanner?()
                                } label: {
                                    Label(state.usesPortrait ? "Вибрати фото профілю" : "Вибрати фото або відео", systemImage: AppSymbol.name("photo.on.rectangle"))
                                }
                                if state.hasBanner && !state.usesPortrait {
                                    Button(role: .destructive) {
                                        state.onRemoveBanner?()
                                    } label: {
                                        Label("Прибрати банер", systemImage: "trash")
                                    }
                                }
                            } label: {
                                Image(systemName: AppSymbol.name("photo.on.rectangle"))
                            }
                            .accessibilityLabel(state.usesPortrait ? "Змінити фото профілю" : "Змінити банер")
                        }
                    }
                }
                .toolbar(state.immersive ? .hidden : .visible, for: .navigationBar)
        }
        .overlay(alignment: .topLeading) {
            if state.immersive {
                immersiveButton
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .frame(width: 44, height: 44)
                    .padding(.leading, 16)
            }
        }
        .statusBarHidden(state.immersive)
        .symbolRenderingMode(.hierarchical)
        .buttonStyle(.automatic)
        .tint(Color(uiColor: .label))
    }

    private var immersiveButton: some View {
        Button {
            state.onImmersive?()
        } label: {
            Image(systemName: state.immersive ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .contentTransition(.symbolEffect(.replace))
        }
        .accessibilityLabel("Безкінечний екран")
        .accessibilityValue(state.immersive ? "Увімкнено" : "Вимкнено")
        .accessibilityIdentifier("feed.immersive")
    }
}

private struct KadrTabContent: UIViewControllerRepresentable {
    let tabs: KadrTabs

    func makeUIViewController(context: Context) -> KadrTabs { tabs }

    func updateUIViewController(_ controller: KadrTabs, context: Context) {
        // Containment and layout are managed by UIKit; state-only toolbar updates
        // must not invalidate the entire video/profile subtree.
    }
}

private struct FeedPickerContent: UIViewRepresentable {
    @ObservedObject var state: KadrToolbarState

    func makeUIView(context: Context) -> FeedSectionPicker {
        let picker = FeedSectionPicker()
        picker.onSelection = { [weak picker] section in
            state.onSection?(section)
            picker?.updateSelection(state.feedSection, overview: state.overview)
        }
        picker.onOverview = { state.onOverview?() }
        return picker
    }

    func updateUIView(_ view: FeedSectionPicker, context: Context) {
        view.matchSearchHeight(44)
        view.updateSelection(state.feedSection, overview: state.overview)
    }
}

private struct ProfilePickerContent: UIViewRepresentable {
    @ObservedObject var state: KadrToolbarState
    func makeUIView(context: Context) -> ProfileSectionPicker {
        let picker = ProfileSectionPicker()
        picker.onSelection = { section in state.onProfileSection?(section) }
        return picker
    }
    func updateUIView(_ view: ProfileSectionPicker, context: Context) {
        view.select(state.profileSection)
    }
}
