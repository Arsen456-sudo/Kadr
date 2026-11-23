import UIKit
import AVFoundation

final class VoiceRecorderController: FormController {
    private let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a")
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private let status = makeLabel(.title2, text: "Голосове повідомлення")
    var onSend: ((URL) -> Void)?
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Голосове повідомлення"
        content.addArrangedSubview(status)
        content.addArrangedSubview(textButton("Почати запис", symbol: "mic.fill") { [weak self] in self?.record() })
        content.addArrangedSubview(textButton("Зупинити запис", symbol: "stop.fill") { [weak self] in
            self?.recorder?.stop(); self?.status.text = "Записано. Можна прослухати перед надсиланням."
        })
        content.addArrangedSubview(textButton("Прослухати", symbol: "play.fill") { [weak self] in
            guard let self else { return }; self.recorder?.stop()
            do { self.player = try AVAudioPlayer(contentsOf: self.file); self.player?.play() } catch { self.showMessage(error.localizedDescription) }
        })
        content.addArrangedSubview(textButton("Надіслати", symbol: "paperplane", prominent: true) { [weak self] in
            guard let self else { return }; self.recorder?.stop(); self.player?.stop()
            guard FileManager.default.fileExists(atPath: self.file.path) else { return }
            self.onSend?(self.file)
        })
    }
    private func record() {
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                guard granted else { self.showMessage("Дозволь доступ до мікрофона в налаштуваннях iOS."); return }
                do {
                    self.player?.stop()
                    try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
                    try AVAudioSession.sharedInstance().setActive(true)
                    self.recorder = try AVAudioRecorder(url: self.file, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue])
                    self.recorder?.record(forDuration: 180)
                    self.status.text = "Запис… До 3 хвилин"
                } catch { self.showMessage(error.localizedDescription) }
            }
        }
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated); recorder?.stop(); player?.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    deinit { try? FileManager.default.removeItem(at: file) }
}

extension LocalStore {
    func attachMessage(_ id: UUID, source: URL?, kind: String?, reply: UUID?, postID: String?) throws {
        var name: String?
        if let source {
            let suffix = source.pathExtension.lowercased()
            guard ["jpg", "jpeg", "png", "heic", "m4a"].contains(suffix) else { throw CocoaError(.fileReadUnsupportedScheme) }
            let file = UUID().uuidString + "." + suffix
            try FileManager.default.copyItem(at: source, to: Self.directory.appendingPathComponent(file))
            name = file
        }
        guard updateState({ state in
            guard let index = state.messages?.firstIndex(where: { $0.id == id && $0.senderID == state.activeID }) else { return }
            state.messages?[index].attachmentFile = name
            state.messages?[index].attachmentKind = kind
            state.messages?[index].replyTo = reply
            state.messages?[index].postID = postID
        }) else { throw CocoaError(.fileWriteUnknown) }
        NotificationCenter.default.post(name: .kadrMessagesDidChange, object: self)
    }
}
