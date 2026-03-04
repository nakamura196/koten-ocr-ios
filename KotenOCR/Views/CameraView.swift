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
    private var flashButton: UIButton?
    private var focusIndicator: UIView?
    private var isFlashOn = false
    private var captureDevice: AVCaptureDevice?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
        setupUI()
        setupTapFocus()
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
        // Turn off torch when leaving
        if isFlashOn {
            toggleTorch(on: false)
        }
    }

    private var cameraAvailable = false

    // MARK: - Camera Setup

    private func setupCamera() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            showNoCameraLabel()
            return
        }

        self.captureDevice = device
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
        label.text = NSLocalizedString("camera_no_camera", comment: "")
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
        // Shutter button
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = .white
        button.layer.cornerRadius = 35
        button.layer.borderWidth = 4
        button.layer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor
        button.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)
        button.accessibilityLabel = NSLocalizedString("capture_button", comment: "")
        view.addSubview(button)

        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            button.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            button.widthAnchor.constraint(equalToConstant: 70),
            button.heightAnchor.constraint(equalToConstant: 70)
        ])

        self.shutterButton = button

        // Flash button
        let flash = UIButton(type: .system)
        flash.translatesAutoresizingMaskIntoConstraints = false
        flash.setImage(UIImage(systemName: "bolt.slash.fill"), for: .normal)
        flash.tintColor = .white
        flash.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        flash.layer.cornerRadius = 22
        flash.addTarget(self, action: #selector(toggleFlash), for: .touchUpInside)
        flash.accessibilityLabel = NSLocalizedString("flash_off", comment: "")
        view.addSubview(flash)

        NSLayoutConstraint.activate([
            flash.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            flash.bottomAnchor.constraint(equalTo: button.topAnchor, constant: -20),
            flash.widthAnchor.constraint(equalToConstant: 44),
            flash.heightAnchor.constraint(equalToConstant: 44)
        ])

        self.flashButton = flash

        // Focus indicator
        let indicator = UIView(frame: CGRect(x: 0, y: 0, width: 70, height: 70))
        indicator.layer.borderColor = UIColor.yellow.cgColor
        indicator.layer.borderWidth = 2
        indicator.backgroundColor = .clear
        indicator.isHidden = true
        indicator.isUserInteractionEnabled = false
        view.addSubview(indicator)
        self.focusIndicator = indicator
    }

    // MARK: - Tap to Focus

    private func setupTapFocus() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTapFocus(_:)))
        tapGesture.numberOfTapsRequired = 1
        view.addGestureRecognizer(tapGesture)
    }

    @objc private func handleTapFocus(_ gesture: UITapGestureRecognizer) {
        guard cameraAvailable,
              let device = captureDevice,
              let previewLayer = previewLayer else { return }

        let point = gesture.location(in: view)

        // Don't focus if tapping on buttons
        if let shutter = shutterButton, shutter.frame.contains(point) { return }
        if let flash = flashButton, flash.frame.contains(point) { return }

        let focusPoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)

        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = focusPoint
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = focusPoint
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
        } catch {}

        // Show focus indicator
        showFocusIndicator(at: point)
    }

    private func showFocusIndicator(at point: CGPoint) {
        guard let indicator = focusIndicator else { return }
        indicator.center = point
        indicator.isHidden = false
        indicator.alpha = 1.0
        indicator.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)

        UIView.animate(withDuration: 0.3, animations: {
            indicator.transform = .identity
        }) { _ in
            UIView.animate(withDuration: 0.5, delay: 0.5, options: [], animations: {
                indicator.alpha = 0
            }) { _ in
                indicator.isHidden = true
            }
        }
    }

    // MARK: - Flash

    @objc private func toggleFlash() {
        isFlashOn.toggle()
        toggleTorch(on: isFlashOn)
        let imageName = isFlashOn ? "bolt.fill" : "bolt.slash.fill"
        flashButton?.setImage(UIImage(systemName: imageName), for: .normal)
        flashButton?.tintColor = isFlashOn ? .yellow : .white
        flashButton?.accessibilityLabel = NSLocalizedString(isFlashOn ? "flash_on" : "flash_off", comment: "")
    }

    private func toggleTorch(on: Bool) {
        guard let device = captureDevice, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        } catch {}
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
