import UIKit
import AVFoundation
import ImageIO

final class EditorToolsController: ActionListController {
    private var collageTask: Task<Void, Never>?
    var extras: PostExtras
    private let media: [(URL, MediaKind)]
    var onChange: ((PostExtras) -> Void)?
    var onCollage: ((URL) -> Void)?
    init(media: [(URL, MediaKind)], extras: PostExtras) { self.media = media; self.extras = extras; super.init("Інструменти публікації") }
    required init?(coder: NSCoder) { fatalError("Use init(media:extras:)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        reloadRows = { [weak self] in
            guard let self else { return [] }
            var rows = [StudioRow(title: "Приховати кількість лайків", detail: self.extras.hideLikes ? "Так" : "Ні", icon: "heart.slash", action: {
                self.extras.hideLikes.toggle(); self.changed()
            })]
            if self.media.first?.1 == .photo {
                rows += [StudioRow(title: "Формат альбому", detail: StudioLabels.title(self.extras.albumLayout), icon: "aspectratio", action: {
                    self.options("Формат", values: ["fit", "square", "portrait"].map(StudioLabels.title)) { value in self.extras.albumLayout = StudioLabels.key(value, among: ["fit", "square", "portrait"]); self.changed() }
                }), StudioRow(title: "Створити колаж", icon: "square.grid.2x2", action: {
                    self.options("Шаблон", values: ["Сітка", "Вертикальна стрічка", "Мозаїка"]) { template in self.collage(template) }
                })]
                rows.append(StudioRow(title: "Відступи колажу", detail: "\(Int(self.extras.collageGap ?? 3))", icon: "arrow.left.and.right", action: {
                    self.prompt("Відступ 0–32", value: String(self.extras.collageGap ?? 3)) { text in
                        if let value = Double(text), value.isFinite { self.extras.collageGap = min(32, max(0, value)); self.changed() }
                    }
                }))
                rows += self.media.indices.map { index in StudioRow(title: "Підпис фото \(index + 1)", detail: self.extras.photoCaptions[String(index)] ?? "", icon: "text.below.photo", action: {
                    self.prompt("Підпис", value: self.extras.photoCaptions[String(index)] ?? "") { text in self.extras.photoCaptions[String(index)] = text; self.changed() }
                }) }
            } else {
                rows += [StudioRow(title: "Вибрати кадр обкладинки", detail: "\(self.extras.coverTime) с", icon: "photo", action: {
                    self.prompt("Кадр у секундах", value: String(self.extras.coverTime)) { value in
                        if let time = Double(value), time.isFinite, time >= 0 { self.extras.coverTime = time; self.changed() }
                    }
                }), StudioRow(title: "Обрізати відео", detail: "Оригінал зберігається", icon: "crop.rotate", action: {
                    let alert = UIAlertController(title: "Діапазон відео", message: "Початок і кінець у секундах", preferredStyle: .alert)
                    alert.addTextField { $0.placeholder = "Початок"; $0.keyboardType = .decimalPad; $0.text = String(self.extras.trimStart) }
                    alert.addTextField { $0.placeholder = "Кінець"; $0.keyboardType = .decimalPad; $0.text = self.extras.trimEnd.map { String($0) } }
                    alert.addAction(UIAlertAction(title: "Застосувати", style: .default) { _ in
                        guard let start = Double(alert.textFields?[0].text ?? ""), let end = Double(alert.textFields?[1].text ?? ""), start.isFinite, end.isFinite, start >= 0, end > start else { self.showMessage("Перевір діапазон."); return }
                        self.extras.trimStart = start; self.extras.trimEnd = end; self.changed()
                    })
                    alert.addAction(UIAlertAction(title: "Скасувати", style: .cancel)); self.present(alert, animated: true)
                })]
            }
            return rows
        }
    }
    private func changed() { onChange?(extras); reload() }
    private func collage(_ template: String) {
        guard media.count >= 2 else { showMessage("Для колажу потрібно щонайменше два фото."); return }
        guard collageTask == nil else { return }
        let urls = media.map { $0.0 }, gap = extras.collageGap ?? 3
        tableView.isUserInteractionEnabled = false
        collageTask = Task { [weak self] in
            guard let self else { return }
            defer { self.collageTask = nil; self.tableView.isUserInteractionEnabled = true }
            do {
                let url = try await Task.detached(priority: .userInitiated) { () throws -> URL in
                    let columns = template == "Вертикальна стрічка" ? 1 : template == "Мозаїка" ? 3 : 2
                    let rows = Int(ceil(Double(urls.count) / Double(columns)))
                    let side = min(512, max(1, 4096 / max(columns, rows)))
                    let width = columns * side, height = rows * side
                    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CocoaError(.fileWriteOutOfSpace) }
                    context.setFillColor(CGColor(gray: 0, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))); context.interpolationQuality = .high
                    for (index, url) in urls.enumerated() {
                        try Task.checkCancellation()
                        try autoreleasepool {
                            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                      kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: side] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
                            let inset = CGFloat(gap) * CGFloat(side) / 512
                            let rect = CGRect(x: CGFloat(index % columns * side) + inset, y: CGFloat((rows - 1 - index / columns) * side) + inset,
                                              width: CGFloat(side) - 2 * inset, height: CGFloat(side) - 2 * inset)
                            let scale = min(rect.width / CGFloat(image.width), rect.height / CGFloat(image.height))
                            let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
                            context.draw(image, in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
                        }
                    }
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
                    guard let image = context.makeImage(), let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
                    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 1] as CFDictionary)
                    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
                    return url
                }.value
                guard !Task.isCancelled else { try? FileManager.default.removeItem(at: url); return }
                self.onCollage?(url); self.navigationController?.popViewController(animated: true)
            } catch { if !Task.isCancelled { self.showMessage(error.localizedDescription) } }
        }
    }
}
