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
    /// Start/stop are blocking calls that must not overlap; keep them on one serial queue.
    private let sessionQueue = DispatchQueue(label: "com.nakamura196.kotenocr.camera.session")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let photoOutput = AVCapturePhotoOutput()
    private var shutterButton: UIButton?
    private var flashButton: UIButton?
    private var focusIndicator: UIView?
    private var zoomLabel: UILabel?
    private var isFlashOn = false
    private var captureDevice: AVCaptureDevice?
    private var currentDeviceOrientation: UIDeviceOrientation = .portrait
    private var isCapturing = false
    private var messageView: UIView?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
        setupUI()
        setupTapFocus()
        setupPinchZoom()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // The user may have granted access in Settings since the last time we looked
        if !cameraAvailable { setupCamera() }
        guard cameraAvailable else { return }
        let session = captureSession
        sessionQueue.async {
            if !session.isRunning { session.startRunning() }
        }
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(
            self, selector: #selector(deviceOrientationChanged),
            name: UIDevice.orientationDidChangeNotification, object: nil
        )
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard cameraAvailable else { return }
        let session = captureSession
        sessionQueue.async {
            if session.isRunning { session.stopRunning() }
        }
        if isFlashOn {
            toggleTorch(on: false)
        }
        NotificationCenter.default.removeObserver(self, name: UIDevice.orientationDidChangeNotification, object: nil)
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    private var cameraAvailable = false

    // MARK: - Device Orientation

    @objc private func deviceOrientationChanged() {
        let orientation = UIDevice.current.orientation
        // Only track portrait/landscape orientations, ignore faceUp/faceDown
        switch orientation {
        case .portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight:
            currentDeviceOrientation = orientation
        default:
            break
        }
    }

    private func videoOrientation(for deviceOrientation: UIDeviceOrientation) -> AVCaptureVideoOrientation {
        switch deviceOrientation {
        case .landscapeLeft:
            return .landscapeRight  // UIDevice and AVCapture use opposite conventions
        case .landscapeRight:
            return .landscapeLeft
        case .portraitUpsideDown:
            return .portraitUpsideDown
        default:
            return .portrait
        }
    }

    // MARK: - Camera Setup

    private func setupCamera() {
        messageView?.removeFromSuperview()
        messageView = nil

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted:
            showPermissionDenied()
            return
        default:
            break
        }

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
        showMessage(String(localized: "camera_no_camera", defaultValue: "No Camera"), showSettingsButton: false)
    }

    private func showPermissionDenied() {
        showMessage(
            String(localized: "camera_permission_denied",
                   defaultValue: "カメラが許可されていません。設定アプリでカメラへのアクセスを許可してください。写真ライブラリから画像を選ぶこともできます。"),
            showSettingsButton: true
        )
    }

    private func showMessage(_ text: String, showSettingsButton: Bool) {
        messageView?.removeFromSuperview()

        let label = UILabel()
        label.text = text
        label.textColor = .lightGray
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 16)
        label.accessibilityIdentifier = "camera_message"

        let stack = UIStackView(arrangedSubviews: [label])
        stack.axis = .vertical
        stack.spacing = 20
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        if showSettingsButton {
            var config = UIButton.Configuration.filled()
            config.title = String(localized: "camera_open_settings", defaultValue: "設定を開く")
            config.baseBackgroundColor = .white
            config.baseForegroundColor = .black
            let button = UIButton(configuration: config)
            button.accessibilityIdentifier = "camera_open_settings_button"
            button.addAction(UIAction { _ in
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }, for: .touchUpInside)
            stack.addArrangedSubview(button)
        }

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])
        messageView = stack
        view.bringSubviewToFront(stack)
    }

    // MARK: - UI

    private func setupUI() {
        // Shutter button
        // White ring with a white disc inside (hybrid storyboard b); press shrinks it.
        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = .clear
        button.layer.cornerRadius = 35
        button.layer.borderWidth = 4
        button.layer.borderColor = UIColor.white.cgColor
        let disc = UIView(frame: CGRect(x: 7, y: 7, width: 56, height: 56))
        disc.backgroundColor = .white
        disc.layer.cornerRadius = 28
        disc.isUserInteractionEnabled = false
        button.addSubview(disc)
        button.addTarget(self, action: #selector(shutterDown), for: [.touchDown, .touchDragEnter])
        button.addTarget(self, action: #selector(shutterUp), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
        button.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)
        button.accessibilityLabel = String(localized: "capture_button", defaultValue: "Capture")
        button.accessibilityIdentifier = "shutter_button"
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
        flash.backgroundColor = UIColor(red: 0.17, green: 0.165, blue: 0.157, alpha: 0.85)
        flash.layer.cornerRadius = 22
        flash.addTarget(self, action: #selector(toggleFlash), for: .touchUpInside)
        flash.accessibilityLabel = String(localized: "flash_off", defaultValue: "Flash Off")
        view.addSubview(flash)

        NSLayoutConstraint.activate([
            flash.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            flash.bottomAnchor.constraint(equalTo: button.topAnchor, constant: -20),
            flash.widthAnchor.constraint(equalToConstant: 44),
            flash.heightAnchor.constraint(equalToConstant: 44)
        ])

        self.flashButton = flash

        // Zoom label
        let zl = UILabel()
        zl.translatesAutoresizingMaskIntoConstraints = false
        zl.text = "1.0x"
        zl.textColor = .white
        zl.font = .systemFont(ofSize: 13, weight: .medium)
        zl.textAlignment = .center
        zl.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        zl.layer.cornerRadius = 14
        zl.clipsToBounds = true
        zl.isHidden = true
        view.addSubview(zl)

        NSLayoutConstraint.activate([
            zl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            zl.bottomAnchor.constraint(equalTo: button.topAnchor, constant: -16),
            zl.widthAnchor.constraint(equalToConstant: 56),
            zl.heightAnchor.constraint(equalToConstant: 28)
        ])
        self.zoomLabel = zl

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
        } catch {
            print("Failed to configure focus: \(error)")
        }

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

    // MARK: - Pinch to Zoom

    private var initialZoomFactor: CGFloat = 1.0

    private func setupPinchZoom() {
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinchZoom(_:)))
        view.addGestureRecognizer(pinch)
    }

    @objc private func handlePinchZoom(_ gesture: UIPinchGestureRecognizer) {
        guard let device = captureDevice else { return }

        switch gesture.state {
        case .began:
            initialZoomFactor = device.videoZoomFactor
        case .changed:
            let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 10.0)
            let newZoom = min(max(initialZoomFactor * gesture.scale, 1.0), maxZoom)
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = newZoom
                device.unlockForConfiguration()
            } catch {
                print("Failed to configure zoom: \(error)")
            }
            updateZoomLabel(newZoom)
        case .ended, .cancelled:
            hideZoomLabelAfterDelay()
        default:
            break
        }
    }

    private func updateZoomLabel(_ factor: CGFloat) {
        zoomLabel?.text = String(format: "%.1fx", factor)
        zoomLabel?.isHidden = false
        zoomLabel?.alpha = 1.0
    }

    private func hideZoomLabelAfterDelay() {
        UIView.animate(withDuration: 0.3, delay: 1.5, options: [], animations: { [weak self] in
            self?.zoomLabel?.alpha = 0
        }) { [weak self] _ in
            self?.zoomLabel?.isHidden = true
        }
    }

    // MARK: - Flash

    @objc private func toggleFlash() {
        isFlashOn.toggle()
        toggleTorch(on: isFlashOn)
        let imageName = isFlashOn ? "bolt.fill" : "bolt.slash.fill"
        flashButton?.setImage(UIImage(systemName: imageName), for: .normal)
        flashButton?.tintColor = isFlashOn ? .yellow : .white
        flashButton?.accessibilityLabel = isFlashOn
            ? String(localized: "flash_on", defaultValue: "Flash On")
            : String(localized: "flash_off", defaultValue: "Flash Off")
    }

    private func toggleTorch(on: Bool) {
        guard let device = captureDevice, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        } catch {
            print("Failed to configure torch: \(error)")
        }
    }

    @objc private func shutterDown() {
        UIView.animate(withDuration: 0.1) { self.shutterButton?.transform = CGAffineTransform(scaleX: 0.88, y: 0.88) }
    }

    @objc private func shutterUp() {
        UIView.animate(withDuration: 0.15) { self.shutterButton?.transform = .identity }
    }

    /// White flash for 120 ms with a firm haptic (storyboard b).
    private func playShutterFeedback() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        let flash = UIView(frame: view.bounds)
        flash.backgroundColor = UIColor.white.withAlphaComponent(0.85)
        flash.isUserInteractionEnabled = false
        view.addSubview(flash)
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        UIView.animate(withDuration: reduceMotion ? 0.2 : 0.12, delay: 0, options: [.curveEaseOut]) {
            flash.alpha = 0
        } completion: { _ in
            flash.removeFromSuperview()
        }
    }

    @objc private func capturePhoto() {
        guard cameraAvailable, !isCapturing else { return }
        setCapturing(true)
        playShutterFeedback()
        // Set video orientation based on current device orientation
        if let connection = photoOutput.connection(with: .video) {
            connection.videoOrientation = videoOrientation(for: currentDeviceOrientation)
        }
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    private func setCapturing(_ capturing: Bool) {
        isCapturing = capturing
        shutterButton?.isEnabled = !capturing
        shutterButton?.alpha = capturing ? 0.5 : 1.0
    }

    private func showCaptureError() {
        let alert = UIAlertController(
            title: nil,
            message: String(localized: "camera_capture_failed", defaultValue: "撮影に失敗しました。もう一度お試しください。"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "ok", defaultValue: "OK"), style: .default))
        present(alert, animated: true)
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        var result: CGImage?
        // Decode straight to an upright image of at most ImageIntake.maxLongSide px, so a 24/48 MP
        // capture never exists as a full-size bitmap.
        if error == nil, let data = photo.fileDataRepresentation() {
            result = ImageIntake.decode(data)
        }
        // Delegate callbacks arrive on an arbitrary queue; UI state must change on main.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.setCapturing(false)
            if let result {
                self.onCapture?(result)
            } else {
                self.showCaptureError()
            }
        }
    }
}
