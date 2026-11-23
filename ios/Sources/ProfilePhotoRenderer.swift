import UIKit
import CoreImage

/// Produces the blurred image for the independently scrolling lower backdrop.
/// The expensive work runs once per photo, never during scrolling.
enum ProfilePhotoRenderer {
    private static let queue = DispatchQueue(label: "kadr.profile-photo", qos: .userInitiated)
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func render(_ image: UIImage, completion: @escaping @MainActor (UIImage?, UIColor) -> Void) {
        queue.async {
            var background = UIColor.secondarySystemBackground
            let result: UIImage? = autoreleasepool {
                guard let input = CIImage(image: image), !input.extent.isEmpty else { return nil }
                // Keep the sharp portion at the resolution loaded by PhotoLoader.
                let extent = input.extent
                let lowerHalf = CGRect(x: extent.minX, y: extent.minY, width: extent.width, height: extent.height * 0.5)
                let average = input.applyingFilter("CIAreaAverage", parameters: ["inputExtent": CIVector(cgRect: lowerHalf)])
                var pixel = [UInt8](repeating: 0, count: 4)
                context.render(average, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
                let sampled = UIColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1)
                var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
                sampled.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
                background = UIColor(hue: hue, saturation: min(0.62, saturation * 0.9), brightness: max(0.13, min(0.29, brightness * 0.42)), alpha: 1)
                let scale = max(extent.width, extent.height) / 1024
                let output = input.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [
                    kCIInputRadiusKey: 12 * scale
                ]).cropped(to: extent)
                guard let rendered = context.createCGImage(output, from: extent) else { return nil }
                return UIImage(cgImage: rendered, scale: image.scale, orientation: .up)
            }
            let color = background
            DispatchQueue.main.async { completion(result, color) }
        }
    }
}
