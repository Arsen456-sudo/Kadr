import UIKit

enum AppAccent {
    static var current = UIColor(red: 1, green: 0.69, blue: 0.51, alpha: 1)
    static func color(_ key: String) -> UIColor {
        switch key {
        case "mint": return .systemMint
        case "violet": return .systemPurple
        case "blue": return .systemBlue
        case "rose": return .systemPink
        default: return UIColor(red: 1, green: 0.69, blue: 0.51, alpha: 1)
        }
    }
}

@MainActor final class AppAccentCoordinator {
    private let store: LocalStore
    private weak var window: UIWindow?
    private var observer: NSObjectProtocol?
    private var task: Task<Void, Never>?
    private var key = ""
    init(store: LocalStore, window: UIWindow) {
        self.store = store; self.window = window
        observer = NotificationCenter.default.addObserver(forName: .kadrLocalDidChange, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }
    private func refresh() {
        let appearance = store.studio.appearance
        let profile = store.active
        let file = appearance.theme == "atmosphere" ? profile?.portraitFile : profile?.bannerFile
        let nextKey = [profile?.id.uuidString ?? "guest", appearance.accent, appearance.accentMode ?? "fixed", file ?? "", profile?.avatarRevision?.uuidString ?? ""].joined(separator: ":")
        guard nextKey != key else { return }; key = nextKey; task?.cancel()
        guard appearance.accentMode == "background" else { apply(AppAccent.color(appearance.accent)); return }
        task = Task { [weak self] in
            var image: UIImage?
            if let file {
                let url = LocalStore.directory.appendingPathComponent(file)
                if ["mov", "mp4", "m4v"].contains(url.pathExtension.lowercased()) {
                    if let cg = await VideoPoster.image(for: url, at: 0) { image = UIImage(cgImage: cg) }
                } else { image = await PhotoLoader.image(url, maxPixel: 480) }
            }
            if image == nil { image = profile?.avatar.flatMap { UIImage(data: $0) } }
            guard !Task.isCancelled, let self, self.key == nextKey else { return }
            guard let image else { self.apply(AppAccent.color(appearance.accent)); return }
            ProfilePhotoRenderer.render(image, includeBlur: false) { [weak self] _, color in
                guard let self, self.key == nextKey else { return }; self.apply(color)
            }
        }
    }
    private func apply(_ color: UIColor) {
        AppAccent.current = color
        window?.tintColor = color
        // Refresh explicit tint assignments as well as inherited UIKit tint.
        func refresh(_ view: UIView) {
            view.tintColorDidChange(); view.setNeedsDisplay()
            if let tab = view as? UITabBar { tab.tintColor = color }
            if let control = view as? UISegmentedControl { control.selectedSegmentTintColor = color.withAlphaComponent(0.24) }
            view.subviews.forEach(refresh)
        }
        if let window { refresh(window) }
        NotificationCenter.default.post(name: .kadrAccentDidChange, object: nil)
    }
    deinit { task?.cancel(); if let observer { NotificationCenter.default.removeObserver(observer) } }
}

extension Notification.Name { static let kadrAccentDidChange = Notification.Name("Kadr.accentDidChange") }

final class AccentSettingsController: ActionListController {
    private let store: LocalStore
    init(store: LocalStore) { self.store = store; super.init("Акцент застосунку") }
    required init?(coder: NSCoder) { fatalError("Use init(store:)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        reloadRows = { [weak self] in
            guard let self else { return [] }; let appearance = self.store.studio.appearance
            let modes = [StudioRow(title: "Колір фону профілю", detail: appearance.accentMode == "background" ? "Увімкнено · оновлюється зі зміною фото" : "Автоматично з фото або банера", icon: "photo", action: { [weak self] in self?.store.changeStudio { $0.appearance.accentMode = "background" }; self?.reload() })]
            return modes + ["peach", "mint", "violet", "blue", "rose"].map { key in
                StudioRow(title: StudioLabels.title(key), detail: appearance.accentMode != "background" && appearance.accent == key ? "Обрано" : "Фіксований акцент", icon: "circle.lefthalf.filled", action: { [weak self] in self?.store.changeStudio { $0.appearance.accent = key; $0.appearance.accentMode = "fixed" }; self?.reload() })
            }
        }
    }
}
