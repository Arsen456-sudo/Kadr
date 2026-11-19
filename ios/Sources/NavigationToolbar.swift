import SwiftUI
import UIKit

@MainActor
final class KadrToolbarState: ObservableObject {
    enum Screen {
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

    @Published var screen = Screen.feed
    @Published var canSignOut = false
    @Published var immersive = false
    var onSearch: (() -> Void)?
    var onSignOut: (() -> Void)?
    var onBanner: (() -> Void)?
    var onImmersive: (() -> Void)?
}

struct KadrNavigationShell: View {
    let tabs: KadrTabs
    @ObservedObject var state: KadrToolbarState

    var body: some View {
        NavigationStack {
            KadrTabContent(tabs: tabs)
                .ignoresSafeArea(.container)
                .navigationTitle(state.screen.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(id: "header.action", placement: .topBarTrailing) {
                        Button {
                            if state.canSignOut { state.onSignOut?() }
                            else { state.onSearch?() }
                        } label: {
                            if state.canSignOut {
                                Text("Вийти")
                            } else {
                                Image(systemName: "magnifyingglass")
                            }
                        }
                        .accessibilityLabel(state.canSignOut ? "Вийти" : "Пошук")
                        .accessibilityIdentifier("header.action")
                    }
                    if state.screen == .feed {
                        ToolbarItem(placement: .principal) {
                            FeedPickerContent(picker: tabs.feedSectionPicker)
                                .frame(width: 184, height: 44)
                        }
                        .sharedBackgroundVisibility(.hidden)
                        ToolbarItem(placement: .topBarLeading) {
                            immersiveButton
                        }
                    } else if state.canSignOut {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                state.onBanner?()
                            } label: {
                                Image(systemName: "photo.on.rectangle")
                            }
                            .accessibilityLabel("Змінити банер")
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
        controller.viewIfLoaded?.setNeedsLayout()
    }
}

private struct FeedPickerContent: UIViewRepresentable {
    let picker: FeedSectionPicker

    func makeUIView(context: Context) -> FeedSectionPicker { picker }
    func updateUIView(_ view: FeedSectionPicker, context: Context) { view.matchSearchHeight(44) }
}
