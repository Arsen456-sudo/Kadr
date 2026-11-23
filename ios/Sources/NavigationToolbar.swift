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
    var onProfileSectionHost: ((UIView, Bool) -> Void)?
}

struct KadrNavigationShell: View {
    let tabs: KadrTabs
    @ObservedObject var state: KadrToolbarState

    var body: some View {
        NavigationStack {
            KadrTabContent(tabs: tabs)
                .ignoresSafeArea(.container)
                .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { navigationItems }
                .toolbar(state.immersive ? .hidden : .visible, for: .navigationBar)
        }
        .overlay(alignment: .topLeading) { immersiveOverlay }
        .statusBarHidden(state.immersive)
        .symbolRenderingMode(.hierarchical)
        .buttonStyle(.automatic)
        .tint(Color(uiColor: .label))
    }

    private var navigationTitle: String {
        guard state.screen == .profile else { return state.screen.title }
        return state.usesPortrait ? "" : (state.compactTitle ?? state.screen.title)
    }

    @ToolbarContentBuilder private var navigationItems: some ToolbarContent {
        ToolbarItem(id: "header.action", placement: .topBarTrailing) { headerAction }
        ToolbarItem(id: "header.principal", placement: .principal) {
            KadrPrincipalContent(state: state, availableWidth: tabs.view.bounds.width, fallbackTitle: navigationTitle)
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(id: "header.leading", placement: .topBarLeading) { leadingAction }
    }

    private var headerAction: some View {
        Button {
            if state.canSignOut { state.onSignOut?() } else { state.onSearch?() }
        } label: { headerActionLabel }
        .accessibilityLabel(state.canSignOut ? "Вийти" : "Пошук")
        .accessibilityIdentifier("header.action")
    }

    @ViewBuilder private var headerActionLabel: some View {
        if state.canSignOut && state.usesPortrait { Image(systemName: "rectangle.portrait.and.arrow.right") }
        else if state.canSignOut { Text("Вийти") }
        else { Image(systemName: "magnifyingglass") }
    }

    @ViewBuilder private var leadingAction: some View {
        if state.screen == .feed { immersiveButton }
        else if state.canSignOut { profileMenu }
    }

    private var profileMenu: some View {
        Menu {
            Button { state.onStudio?() } label: { Label("Студія та налаштування", systemImage: "slider.horizontal.3") }
            Button { state.onChooseBanner?() } label: {
                Label(state.usesPortrait ? "Вибрати фото профілю" : "Вибрати фото або відео", systemImage: AppSymbol.name("photo.on.rectangle"))
            }
            if state.hasBanner && !state.usesPortrait {
                Button(role: .destructive) { state.onRemoveBanner?() } label: { Label("Прибрати банер", systemImage: "trash") }
            }
        } label: { Image(systemName: AppSymbol.name("photo.on.rectangle")) }
        .accessibilityLabel(state.usesPortrait ? "Змінити фото профілю" : "Змінити банер")
    }

    @ViewBuilder private var immersiveOverlay: some View {
        if state.immersive {
            immersiveButton
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .frame(width: 44, height: 44)
                .padding(.leading, 16)
        }
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

private struct KadrPrincipalContent: View {
    @ObservedObject var state: KadrToolbarState
    let availableWidth: CGFloat
    let fallbackTitle: String
    private var regularWidth: CGFloat { min(216, max(132, availableWidth - 172)) }

    @ViewBuilder var body: some View {
        if state.screen == .feed {
            FeedPickerContent(state: state).frame(width: 236, height: 44)
        } else if state.screen == .profile && state.usesPortrait {
            AtmosphereToolbarTitle(state: state, availableWidth: availableWidth)
        } else if state.screen == .profile && state.profileDocked {
            ProfilePickerContent(state: state).frame(width: regularWidth, height: 44)
        } else {
            Text(fallbackTitle).font(.headline)
        }
    }
}

private struct AtmosphereToolbarTitle: View {
    @ObservedObject var state: KadrToolbarState
    let availableWidth: CGFloat
    private var transitionAnimation: Animation? {
        UIAccessibility.isReduceMotionEnabled ? nil : .smooth(duration: 0.22)
    }
    var body: some View {
        ZStack {
            Text("Профіль").font(.headline)
                .offset(y: state.profileDocked ? -100 : 0)
                .opacity(state.profileDocked ? 0 : 1)
                .accessibilityHidden(state.profileDocked)
            ProfileToolbarHost(state: state)
                .opacity(state.profileDocked ? 1 : 0)
                .allowsHitTesting(state.profileDocked)
        }
        .frame(width: min(260, max(160, availableWidth - 128)), height: 44)
        .animation(transitionAnimation, value: state.profileDocked)
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
        let picker = ProfileSectionPicker(atmosphere: state.usesPortrait)
        picker.onSelection = { section in state.onProfileSection?(section) }
        return picker
    }
    func updateUIView(_ view: ProfileSectionPicker, context: Context) {
        view.select(state.profileSection)
    }
}

// A placeholder for the profile's existing picker, never a second picker.
private struct ProfileToolbarHost: UIViewRepresentable {
    @ObservedObject var state: KadrToolbarState
    func makeUIView(context: Context) -> ProfileToolbarHostView {
        let host = ProfileToolbarHostView()
        host.onLayout = { view in state.onProfileSectionHost?(view, false) }
        host.onDetach = { view in state.onProfileSectionHost?(view, true) }
        return host
    }
    func updateUIView(_ view: ProfileToolbarHostView, context: Context) {
        state.onProfileSectionHost?(view, false)
    }
    static func dismantleUIView(_ view: ProfileToolbarHostView, coordinator: ()) { view.onDetach?(view) }
}

private final class ProfileToolbarHostView: UIView {
    var onLayout: ((UIView) -> Void)?
    var onDetach: ((UIView) -> Void)?
    override func layoutSubviews() { super.layoutSubviews(); onLayout?(self) }
}
