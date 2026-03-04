import SwiftUI
import AVFoundation

struct CameraView: UIViewControllerRepresentable {
    let onCapture: (CGImage) -> Void

    func makeUIViewController(context: Context) -> CameraViewController {
        let vc = CameraViewController()
        vc.onCapture = onCapture
        return vc
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {}
}

class CameraViewController: UIViewController {
    var onCapture: ((CGImage) -> Void)?

    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let photoOutput = AVCapturePhotoOutput()
    private var shutterButton: UIButton?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
        setupUI()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard cameraAvailable else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard cameraAvailable else { return }
        captureSession.stopRunning()
    }

    private var cameraAvailable = false

    // MARK: - Camera Setup

    private func setupCamera() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            showNoCameraLabel()
            return
        }

        captureSession.sessionPreset = .photo

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }

        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        self.previewLayer = previewLayer
        cameraAvailable = true
    }

    private func showNoCameraLabel() {
        let label = UILabel()
        label.text = "Camera not available\nUse the photo picker to select an image"
        label.textColor = .gray
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 16)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
        ])
    }

    // MARK: - UI

    private func setupUI() {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = .white
        button.layer.cornerRadius = 35
        button.layer.borderWidth = 4
        button.layer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor
        button.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)
        view.addSubview(button)

        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            button.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            button.widthAnchor.constraint(equalToConstant: 70),
            button.heightAnchor.constraint(equalToConstant: 70)
        ])

        self.shutterButton = button
    }

    @objc private func capturePhoto() {
        guard cameraAvailable else { return }
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let uiImage = UIImage(data: data) else { return }

        // Apply the image orientation to get correctly oriented CGImage
        let correctedImage = correctOrientation(uiImage)
        onCapture?(correctedImage)
    }

    private func correctOrientation(_ image: UIImage) -> CGImage {
        // If already up, return as-is
        if image.imageOrientation == .up, let cg = image.cgImage {
            return cg
        }

        // Redraw with correct orientation
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let normalized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return normalized?.cgImage ?? image.cgImage!
    }
}
