import UIKit
import AVFoundation

final class ProfileScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "kadr.qr-camera", qos: .userInitiated)
    private var preview: AVCaptureVideoPreviewLayer?
    private var completed = false
    var onCode: ((String) -> Void)?
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Сканувати QR-код"; view.backgroundColor = .black
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard let self else { return }
            guard granted else { DispatchQueue.main.async { self.showMessage("Дозволь доступ до камери в налаштуваннях iOS.") }; return }
            self.queue.async {
                guard let camera = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: camera), self.session.canAddInput(input) else { return }
                self.session.beginConfiguration(); self.session.addInput(input)
                let output = AVCaptureMetadataOutput()
                guard self.session.canAddOutput(output) else { self.session.commitConfiguration(); return }
                self.session.addOutput(output); output.setMetadataObjectsDelegate(self, queue: .main); output.metadataObjectTypes = [.qr]
                self.session.commitConfiguration()
                DispatchQueue.main.async {
                    let preview = AVCaptureVideoPreviewLayer(session: self.session); preview.videoGravity = .resizeAspectFill
                    preview.frame = self.view.bounds; self.view.layer.addSublayer(preview); self.preview = preview
                }
                self.session.startRunning()
            }
        }
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); preview?.frame = view.bounds }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); queue.async { [session] in session.stopRunning() } }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !completed, let value = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue,
              URL(string: value)?.scheme == "kadr" else { return }
        completed = true; queue.async { [session] in session.stopRunning() }; onCode?(value)
    }
}
