import UIKit
import CoreImage

/// Produces a single image with increasing blur toward its lower edge.
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
                var output = input
                let steps: [(radius: CGFloat, start: CGFloat, end: CGFloat)] = [
                    (8, 0.28, 0.56), (20, 0.42, 0.72), (36, 0.56, 0.88)
                ]
                let scale = max(extent.width, extent.height) / 1024
                for step in steps {
                    let blurred = input.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [
                        kCIInputRadiusKey: step.radius * scale
                    ]).cropped(to: extent)
                    // Core Image's Y axis starts at the bottom: black at the top,
                    // white below, so only the lower portion receives each blur.
                    guard let mask = CIFilter(name: "CISmoothLinearGradient", parameters: [
                        "inputPoint0": CIVector(x: extent.midX, y: extent.maxY - extent.height * step.start),
                        "inputPoint1": CIVector(x: extent.midX, y: extent.maxY - extent.height * step.end),
                        "inputColor0": CIColor.black,
                        "inputColor1": CIColor.white
                    ])?.outputImage else { return nil }
                    output = blurred.applyingFilter("CIBlendWithMask", parameters: [
                        kCIInputBackgroundImageKey: output, kCIInputMaskImageKey: mask
                    ]).cropped(to: extent)
                }
                guard let rendered = context.createCGImage(output, from: extent) else { return nil }
                return UIImage(cgImage: rendered, scale: image.scale, orientation: .up)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }
}
