import UIKit

// One rendering style for UIKit symbols throughout the app; callers can retain
// their existing point sizes. SF Symbols stay vector-based and accessibility-aware.
enum AppSymbol {
    private static let cache = NSCache<NSString, UIImage>()
    static func name(_ name: String) -> String {
        switch name {
        case "house": return "play.rectangle.on.rectangle"
        case "house.fill": return "play.rectangle.on.rectangle.fill"
        case "tray": return "bubble.left.and.bubble.right"
        case "tray.fill": return "bubble.left.and.bubble.right.fill"
        case "plus.circle.fill": return "plus.app.fill"
        case "bubble": return "bubble.left"
        case "photo.on.rectangle": return "photo.stack"
        case "square.grid.3x3": return "rectangle.grid.3x2"
        default: return name
        }
    }

    static func image(_ symbol: String, withConfiguration configuration: UIImage.Configuration? = nil) -> UIImage? {
        let resolved = name(symbol)
        let key = resolved as NSString
        let base: UIImage
        if let cached = cache.object(forKey: key) { base = cached }
        else {
            let style = UIImage.SymbolConfiguration(weight: .semibold)
                .applying(UIImage.SymbolConfiguration.preferringHierarchical())
            guard let image = UIImage(systemName: resolved, withConfiguration: style)
                ?? UIImage(systemName: symbol, withConfiguration: style) else { return nil }
            cache.setObject(image, forKey: key)
            base = image
        }
        guard let configuration = configuration as? UIImage.SymbolConfiguration else { return base }
        return base.applyingSymbolConfiguration(configuration) ?? base
    }
}
