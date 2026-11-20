import UIKit

// The flexible spacer keeps the action next to short text; long text truncates
// before the button, so the action remains on the same line at every width.
final class InlineCaptionView: UIStackView {
    private let label = makeLabel(.subheadline)
    private let more = UIButton(configuration: .plain())
    var onMore: (() -> Void)?

    init() {
        super.init(frame: .zero)
        axis = .horizontal
        alignment = .firstBaseline
        spacing = 4
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        more.configuration?.title = "ще"
        more.configuration?.contentInsets = .zero
        more.configuration?.baseForegroundColor = .secondaryLabel
        more.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = .preferredFont(forTextStyle: .subheadline)
            return attributes
        }
        more.setContentHuggingPriority(.required, for: .horizontal)
        more.setContentCompressionResistancePriority(.required, for: .horizontal)
        more.accessibilityLabel = "Відкрити повний опис"
        more.addAction(UIAction { [weak self] _ in self?.onMore?() }, for: .primaryActionTriggered)
        let spacer = UIView()
        spacer.setContentHuggingPriority(UILayoutPriority(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(UILayoutPriority(1), for: .horizontal)
        [label, more, spacer].forEach(addArrangedSubview)
    }
    required init(coder: NSCoder) { fatalError("Use init()") }

    func show(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if label.text != text { label.text = text }
        isHidden = text.isEmpty
        more.isHidden = text.isEmpty
    }
}

class FeedMediaCell: UICollectionViewCell {
    var representedID: String?
    var mediaHost: UIView { contentView }
    var onRelease: ((FeedMediaCell) -> Void)?
    override func prepareForReuse() {
        onRelease?(self)
        representedID = nil
        onRelease = nil
        super.prepareForReuse()
    }
}
