import UIKit
import ImageIO

enum PhotoLoader {
    static func image(_ url: URL, maxPixel: CGFloat = 1800) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixel
                  ] as CFDictionary) else { return nil }
            return UIImage(cgImage: image)
        }.value
    }
}

final class PhotoAlbumController: UIPageViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    private let media: [PostMedia]
    private let counter = UILabel()
    private var index = 0
    private var immersive = false
    private let compact: Bool

    init(media: [PostMedia], index: Int = 0, compact: Bool = false) {
        self.compact = compact
        self.media = media
        self.index = min(max(0, index), max(0, media.count - 1))
        super.init(transitionStyle: .scroll, navigationOrientation: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError("Use init(media:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        dataSource = self
        delegate = self
        if !media.isEmpty { setViewControllers([page(index)], direction: .forward, animated: false) }
        counter.textAlignment = .center
        counter.font = .preferredFont(forTextStyle: .caption1)
        counter.textColor = .white
        counter.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        counter.layer.cornerRadius = 14
        counter.clipsToBounds = true
        counter.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(counter)
        NSLayoutConstraint.activate([
            counter.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            counter.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: compact ? -12 : -82),
            counter.widthAnchor.constraint(greaterThanOrEqualToConstant: 72),
            counter.heightAnchor.constraint(equalToConstant: 28)
        ])
        updateCounter()
    }

    func setImmersive(_ enabled: Bool) {
        immersive = enabled
        counter.isHidden = enabled || media.count < 2
    }

    private func page(_ index: Int) -> PhotoPage { PhotoPage(url: media[index].url, index: index) }
    private func updateCounter() {
        counter.text = "  \(index + 1) / \(media.count)  "
        counter.isHidden = media.count < 2 || immersive
        counter.accessibilityLabel = "Фото \(index + 1) із \(media.count)"
    }
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore controller: UIViewController) -> UIViewController? {
        guard let current = controller as? PhotoPage, current.index > 0 else { return nil }
        return page(current.index - 1)
    }
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter controller: UIViewController) -> UIViewController? {
        guard let current = controller as? PhotoPage, current.index + 1 < media.count else { return nil }
        return page(current.index + 1)
    }
    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool,
                            previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard completed, let current = viewControllers?.first as? PhotoPage else { return }
        index = current.index
        updateCounter()
    }
}

private final class PhotoPage: UIViewController, UIScrollViewDelegate {
    let index: Int
    private let url: URL
    private let scroll = UIScrollView()
    private let image = UIImageView()
    private let backdrop = UIImageView()
    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private var task: Task<Void, Never>?
    init(url: URL, index: Int) {
        self.url = url
        self.index = index
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(url:index:)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        backdrop.contentMode = .scaleAspectFill
        backdrop.clipsToBounds = true
        backdrop.pin(to: view)
        blur.pin(to: view)
        backdrop.isHidden = true
        blur.isHidden = true
        scroll.pin(to: view)
        scroll.backgroundColor = .clear
        scroll.delegate = self
        scroll.maximumZoomScale = 4
        scroll.contentInsetAdjustmentBehavior = .never
        image.contentMode = .scaleAspectFit
        scroll.addSubview(image)
        task = Task { [weak self, url] in
            let result = await PhotoLoader.image(url)
            guard !Task.isCancelled else { return }
            self?.image.image = result
            self?.backdrop.image = result
            let wide = (result?.size.width ?? 0) > (result?.size.height ?? 0)
            self?.backdrop.isHidden = !wide
            self?.blur.isHidden = !wide
        }
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if scroll.zoomScale == 1 {
            image.frame = scroll.bounds
            scroll.contentSize = scroll.bounds.size
        }
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { image }
    deinit { task?.cancel() }
}
