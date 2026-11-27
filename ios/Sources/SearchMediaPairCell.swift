import UIKit

final class SearchMediaPairCell: UITableViewCell {
    private let row = UIStackView()
    private let previews = [ClipThumbnailCell(frame: .zero), ClipThumbnailCell(frame: .zero)]
    private let buttons = [UIButton(type: .system), UIButton(type: .system)]
    private var clips: [Clip] = []
    private var onOpen: ((Clip) -> Void)?
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear; selectionStyle = .none
        row.distribution = .fillEqually; row.spacing = 10
        row.pin(to: contentView, insets: .init(top: 6, leading: 0, bottom: 6, trailing: 0))
        for index in 0..<2 {
            let host = UIView(); row.addArrangedSubview(host)
            previews[index].layer.cornerRadius = 18; previews[index].clipsToBounds = true
            previews[index].isUserInteractionEnabled = false; previews[index].pin(to: host)
            buttons[index].pin(to: host)
            host.heightAnchor.constraint(equalTo: host.widthAnchor, multiplier: 1.35).isActive = true
            buttons[index].addAction(UIAction { [weak self] _ in
                guard let self, self.clips.indices.contains(index) else { return }
                self.onOpen?(self.clips[index])
            }, for: .primaryActionTriggered)
        }
    }
    required init?(coder: NSCoder) { fatalError("Use init(style:reuseIdentifier:)") }
    func show(_ clips: [Clip], onOpen: @escaping (Clip) -> Void) {
        self.clips = clips; self.onOpen = onOpen
        for index in 0..<2 {
            previews[index].prepareForReuse()
            let exists = clips.indices.contains(index)
            previews[index].isHidden = !exists; buttons[index].isHidden = !exists
            if exists {
                previews[index].show(clips[index], modern: true)
                buttons[index].accessibilityLabel = (clips[index].isPhoto ? "Фото. " : "Відео. ") + clips[index].caption
            }
        }
    }
    override func prepareForReuse() {
        super.prepareForReuse(); previews.forEach { $0.prepareForReuse() }; clips = []; onOpen = nil
    }
}
