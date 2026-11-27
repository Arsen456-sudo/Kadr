import UIKit
import AVFoundation

/// Full-length original video, muted and looped; no per-frame image extraction.
final class VideoAvatarView: UIImageView {
    private let videoLayer = AVPlayerLayer()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var file: String?
    override init(frame: CGRect) {
        super.init(frame: frame)
        contentMode = .scaleAspectFill; clipsToBounds = true
        videoLayer.videoGravity = .resizeAspectFill; layer.addSublayer(videoLayer)
        NotificationCenter.default.addObserver(self, selector: #selector(updatePlayback), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(pause), name: UIApplication.willResignActiveNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
    func show(_ profile: Profile, animate: Bool = true) {
        image = profile.avatar.flatMap { UIImage(data: $0) } ?? AppSymbol.image("person.crop.circle")
        let file = animate ? profile.avatarVideoFile : nil
        guard self.file != file else { updatePlayback(); return }
        self.file = file; player?.pause(); looper?.disableLooping(); videoLayer.player = nil; player = nil; looper = nil
        updatePlayback()
    }
    override func layoutSubviews() { super.layoutSubviews(); CATransaction.begin(); CATransaction.setDisableActions(true); videoLayer.frame = bounds; CATransaction.commit() }
    override func didMoveToWindow() { super.didMoveToWindow(); updatePlayback() }
    @objc private func updatePlayback() {
        var responder: UIResponder? = self
        var preview = false
        while let next = responder { if let profile = next as? ProfileController { preview = profile.isPreview; break }; responder = next.next }
        if !preview && window != nil && UIApplication.shared.applicationState == .active && !UIAccessibility.isReduceMotionEnabled {
            if player == nil, let file {
                let url = LocalStore.directory.appendingPathComponent(file)
                if FileManager.default.fileExists(atPath: url.path) {
                    let queue = AVQueuePlayer(); queue.isMuted = true
                    looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url)); player = queue; videoLayer.player = queue
                }
            }
            player?.play()
        } else { player?.pause() }
    }
    @objc private func pause() { player?.pause() }
    deinit { player?.pause(); looper?.disableLooping(); NotificationCenter.default.removeObserver(self) }
}
