import UIKit

final class PhotoCropController: UIViewController, UIScrollViewDelegate {
    enum Shape { case banner(CGFloat), avatar }
    private let image: UIImage
    private let shape: Shape
    private let scroll = UIScrollView()
    private let artwork = UIImageView()
    private let overlay = UIView()
    private let maskLayer = CAShapeLayer()
    private let border = CAShapeLayer()
    private var crop = CGRect.zero
    private var lastLayout = CGRect.zero
    var onCrop: ((UIImage) -> Void)?

    init(image: UIImage, shape: Shape) {
        self.image = image
        self.shape = shape
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(image:shape:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        title = "Вибери ділянку фото"
        scroll.pin(to: view)
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.delegate = self
        scroll.decelerationRate = .fast
        artwork.image = image
        artwork.frame = CGRect(origin: .zero, size: image.size)
        scroll.addSubview(artwork)
        scroll.contentSize = image.size
        overlay.pin(to: view)
        overlay.isUserInteractionEnabled = false
        maskLayer.fillRule = .evenOdd
        maskLayer.fillColor = UIColor.black.withAlphaComponent(0.65).cgColor
        overlay.layer.addSublayer(maskLayer)
        border.fillColor = UIColor.clear.cgColor
        border.strokeColor = UIColor.white.cgColor
        border.lineWidth = 1.5
        overlay.layer.addSublayer(border)
        let hint = makeLabel(.subheadline, text: "Перетягуй фото й змінюй масштаб двома пальцями.", color: .white)
        hint.textAlignment = .center
        hint.isUserInteractionEnabled = false
        hint.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hint)
        NSLayoutConstraint.activate([
            hint.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            hint.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            hint.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24)
        ])
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in self?.finish() })
        isModalInPresentation = true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let safe = view.safeAreaLayoutGuide.layoutFrame
        guard lastLayout != safe else { return }
        lastLayout = safe
        let width = max(1, min(view.bounds.width - 32, safe.height - 100))
        let ratio: CGFloat
        switch shape {
        case .avatar: ratio = 1
        case .banner(let value): ratio = max(0.1, value)
        }
        let height = min(width / ratio, max(1, safe.height - 100))
        let actualWidth = height * ratio
        crop = CGRect(x: (view.bounds.width - actualWidth) / 2, y: safe.midY - height / 2 - 20,
                      width: actualWidth, height: height)
        let minimumScale = max(crop.width / image.size.width, crop.height / image.size.height)
        scroll.maximumZoomScale = max(minimumScale * 8, 1)
        scroll.minimumZoomScale = minimumScale
        scroll.zoomScale = minimumScale
        scroll.contentInset = UIEdgeInsets(top: crop.minY, left: crop.minX,
                                          bottom: view.bounds.height - crop.maxY, right: view.bounds.width - crop.maxX)
        scroll.setContentOffset(CGPoint(x: (scroll.contentSize.width - crop.width) / 2 - crop.minX,
                                       y: (scroll.contentSize.height - crop.height) / 2 - crop.minY), animated: false)
        let hole: UIBezierPath
        switch shape {
        case .avatar: hole = UIBezierPath(ovalIn: crop)
        case .banner: hole = UIBezierPath(rect: crop)
        }
        let mask = UIBezierPath(rect: view.bounds)
        mask.append(hole)
        maskLayer.path = mask.cgPath
        border.path = hole.cgPath
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { artwork }

    private func finish() {
        let inset = scroll.contentInset
        let minimum = CGPoint(x: -inset.left, y: -inset.top)
        let maximum = CGPoint(x: max(minimum.x, scroll.contentSize.width - scroll.bounds.width + inset.right),
                              y: max(minimum.y, scroll.contentSize.height - scroll.bounds.height + inset.bottom))
        scroll.setContentOffset(CGPoint(x: min(maximum.x, max(minimum.x, scroll.contentOffset.x)),
                                       y: min(maximum.y, max(minimum.y, scroll.contentOffset.y))), animated: false)
        let rect = artwork.convert(crop, from: view).intersection(artwork.bounds)
        guard rect.width > 0, rect.height > 0 else { return }
        let limit: CGFloat
        switch shape { case .avatar: limit = 1024; case .banner: limit = 4096 }
        let scale = min(image.scale, limit / max(rect.width, rect.height))
        let size = CGSize(width: max(1, floor(rect.width * scale)), height: max(1, floor(rect.height * scale)))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let result = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(x: -rect.minX * scale, y: -rect.minY * scale,
                                  width: image.size.width * scale, height: image.size.height * scale))
        }
        let callback = onCrop
        dismiss(animated: true) { callback?(result) }
    }
}

final class AvatarMenuController: UIViewController {
    private let data: Data?
    private let editable: Bool
    var onChoose: (() -> Void)?

    init(data: Data?, editable: Bool) {
        self.data = data
        self.editable = editable
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(data:editable:)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Фото профілю"
        view.backgroundColor = .black
        let image = UIImageView(image: data.flatMap { UIImage(data: $0) } ?? UIImage(systemName: "person.crop.circle"))
        image.contentMode = .scaleAspectFit
        image.tintColor = .secondaryLabel
        image.pin(to: view, insets: .init(top: 100, leading: 16, bottom: 120, trailing: 16))
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        if editable {
            let choose = textButton("Вибрати фотографію", symbol: "photo", prominent: true) { [weak self] in
                guard let self else { return }
                let callback = self.onChoose
                self.dismiss(animated: true) { callback?() }
            }
            choose.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(choose)
            NSLayoutConstraint.activate([
                choose.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                choose.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24)
            ])
        }
    }
}
