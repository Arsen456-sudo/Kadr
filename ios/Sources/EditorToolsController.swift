import UIKit
import AVFoundation

final class EditorToolsController: ActionListController {
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
                rows += [StudioRow(title: "Формат альбому", detail: self.extras.albumLayout, icon: "aspectratio", action: {
                    self.options("Формат", values: ["fit", "square", "portrait"]) { value in self.extras.albumLayout = value; self.changed() }
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
        Task { [weak self] in
            guard let self else { return }
            var images: [UIImage] = []
            for item in self.media { if let image = await PhotoLoader.image(item.0, maxPixel: 1600) { images.append(image) } }
            guard images.count == self.media.count else { self.showMessage("Не вдалося відкрити всі фотографії."); return }
            let columns = template == "Вертикальна стрічка" ? 1 : template == "Мозаїка" ? 3 : 2
            let rows = Int(ceil(Double(images.count) / Double(columns)))
            let side: CGFloat = 512
            let size = CGSize(width: side * CGFloat(columns), height: side * CGFloat(rows))
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
            let gap = CGFloat(self.extras.collageGap ?? 3)
            let result = UIGraphicsImageRenderer(size: size, format: format).image { context in
                UIColor.black.setFill(); context.fill(CGRect(origin: .zero, size: size))
                for (index, image) in images.enumerated() {
                    let rect = CGRect(x: CGFloat(index % columns) * side + gap, y: CGFloat(index / columns) * side + gap, width: side - 2 * gap, height: side - 2 * gap)
                    let ratio = min(rect.width / image.size.width, rect.height / image.size.height)
                    let fit = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
                    image.draw(in: CGRect(x: rect.midX - fit.width / 2, y: rect.midY - fit.height / 2, width: fit.width, height: fit.height))
                }
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
            do { try result.jpegData(compressionQuality: 1)?.write(to: url); self.onCollage?(url); self.navigationController?.popViewController(animated: true) }
            catch { self.showMessage(error.localizedDescription) }
        }
    }
}
