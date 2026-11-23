import UIKit
import CoreImage

/// Produces the blurred image for the independently scrolling lower backdrop.
/// The expensive work runs once per photo, never during scrolling.
enum ProfilePhotoRenderer {
    private static let queue = DispatchQueue(label: "kadr.profile-photo", qos: .userInitiated)
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func render(_ image: UIImage, completion: @escaping @MainActor (UIImage?) -> Void) {
        queue.async {
            let result: UIImage? = autoreleasepool {
                guard let input = CIImage(image: image), !input.extent.isEmpty else { return nil }
                // Keep the sharp portion at the resolution loaded by PhotoLoader.
                let extent = input.extent
                let scale = max(extent.width, extent.height) / 1024
                let output = input.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [
                    kCIInputRadiusKey: 12 * scale
                ]).cropped(to: extent)
                guard let rendered = context.createCGImage(output, from: extent) else { return nil }
                return UIImage(cgImage: rendered, scale: image.scale, orientation: .up)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }
}
