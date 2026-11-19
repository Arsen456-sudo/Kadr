import SwiftUI

@main
struct KadrApp: App {
    @State private var store = LocalStore()

    var body: some Scene {
        WindowGroup {
            FeedView(store: store)
                .preferredColorScheme(.dark)
                .tint(.peach)
        }
    }
}

extension Color {
    static let peach = Color(red: 1, green: 0.69, blue: 0.51)
}
