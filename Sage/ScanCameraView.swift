import SwiftUI
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(UIKit)
import UIKit
#endif

struct ScanCameraView: View {
    @EnvironmentObject var store: AppStore
    let onClose: () -> Void
    let onHistory: () -> Void
    let onScanComplete: (String) -> Void

    @State private var isTorchOn = false
    @State private var didEmit = false

    var body: some View {
        ZStack {
            CameraPreview(isTorchOn: isTorchOn, onBarcode: handleBarcode)
                .ignoresSafeArea()
                .background(Color.black.ignoresSafeArea())

            // Vignette so the chrome stays readable over any scene
            LinearGradient(
                colors: [Color.black.opacity(0.55), .clear, Color.black.opacity(0.75)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            CornerBrackets()

            VStack {
                topBar
                Spacer()
                hintArea
                Spacer().frame(height: 30)
                bottomButtonsRow.padding(.bottom, 40)
            }
        }
        .onDisappear {
            isTorchOn = false
        }
    }

    private var topBar: some View {
        HStack {
            CameraCircleBtn(systemName: "xmark", action: onClose)
            Spacer()
            Text("Scan barcode")
                .font(.sageSemiBold(14)).tracking(-0.2)
                .foregroundColor(.white)
            Spacer()
            CameraCircleBtn(systemName: "list.bullet", action: onHistory)
        }
        .padding(.horizontal, 16).padding(.top, 8)
    }

    private var hintArea: some View {
        VStack(spacing: 6) {
            Text("Align the barcode")
                .font(.sageRegular(20)).tracking(-0.4)
                .foregroundColor(.white)
            Text("Hold steady — we'll detect it automatically")
                .font(.sageMedium(13))
                .foregroundColor(.white.opacity(0.7))
        }
        .offset(y: -80)
    }

    private var bottomButtonsRow: some View {
        HStack {
            CameraCircleBtn(systemName: isTorchOn ? "bolt.fill" : "bolt", size: 44) {
                isTorchOn.toggle()
            }
            Spacer()
            CameraCircleBtn(systemName: "questionmark", size: 44)
        }
        .padding(.horizontal, 32)
    }

    private func handleBarcode(_ code: String) {
        guard !didEmit else { return }
        didEmit = true
        onScanComplete(code)
    }
}

private struct CameraCircleBtn: View {
    let systemName: String
    // Visible size; hit area below always lifts to at least 44.
    var size: CGFloat = 44
    var action: () -> Void = {}
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.sageSemiBold(15))
                .foregroundColor(.white)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.black.opacity(0.45)))
                .minHitArea(44)
        }
        .buttonStyle(.pressable)
    }
}

private struct CornerBrackets: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let rectW: CGFloat = 290, rectH: CGFloat = 180
            let topY = h * 0.46
            let cx = w / 2
            let left = cx - rectW / 2, right = cx + rectW / 2
            let top = topY - rectH / 2, bottom = topY + rectH / 2

            ZStack {
                bracket(x: left, y: top, x2: 1, y2: 1)
                bracket(x: right, y: top, x2: -1, y2: 1)
                bracket(x: left, y: bottom, x2: 1, y2: -1)
                bracket(x: right, y: bottom, x2: -1, y2: -1)
            }
        }
        .allowsHitTesting(false)
    }
    private func bracket(x: CGFloat, y: CGFloat, x2: CGFloat, y2: CGFloat) -> some View {
        let arm: CGFloat = 32
        let cornerRadius: CGFloat = 8
        return Path { p in
            p.move(to: CGPoint(x: x, y: y + arm * y2))
            p.addLine(to: CGPoint(x: x, y: y + cornerRadius * y2))
            p.addQuadCurve(
                to: CGPoint(x: x + cornerRadius * x2, y: y),
                control: CGPoint(x: x, y: y)
            )
            p.addLine(to: CGPoint(x: x + arm * x2, y: y))
        }
        .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
    }
}

// MARK: - Live camera preview

#if canImport(UIKit) && canImport(AVFoundation)

private struct CameraPreview: UIViewRepresentable {
    var isTorchOn: Bool = false
    var onBarcode: (String) -> Void = { _ in }

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.backgroundColor = .black
        view.onBarcode = onBarcode
        view.requestAccessAndStart()
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        uiView.onBarcode = onBarcode
        uiView.setTorchEnabled(isTorchOn)
    }

    static func dismantleUIView(_ uiView: CameraPreviewView, coordinator: ()) {
        uiView.stop()
    }
}

final class CameraPreviewView: UIView, AVCaptureMetadataOutputObjectsDelegate {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    private var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "sage.camera.session")
    private let metadataOutput = AVCaptureMetadataOutput()
    private var captureDevice: AVCaptureDevice?
    private var torchEnabled = false
    private var didEmit = false

    var onBarcode: ((String) -> Void)?

    func setTorchEnabled(_ enabled: Bool) {
        guard torchEnabled != enabled else { return }
        torchEnabled = enabled
        sessionQueue.async { [weak self] in
            self?.applyTorch(enabled)
        }
    }

    private func applyTorch(_ enabled: Bool) {
        guard let device = captureDevice, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if enabled {
                try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
            } else {
                device.torchMode = .off
            }
        } catch {}
    }

    func requestAccessAndStart() {
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.session = session

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted else { return }
                self?.configureAndStart()
            }
        default:
            break
        }
    }

    private func configureAndStart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .high

            if self.session.inputs.isEmpty,
               let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
               let input = try? AVCaptureDeviceInput(device: device),
               self.session.canAddInput(input) {
                self.session.addInput(input)
                self.captureDevice = device
            }

            if self.session.outputs.isEmpty, self.session.canAddOutput(self.metadataOutput) {
                self.session.addOutput(self.metadataOutput)
                self.metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
            }

            self.session.commitConfiguration()

            // availableMetadataObjectTypes is only valid after the output is
            // attached and configuration committed — set the types here.
            let desired: [AVMetadataObject.ObjectType] =
                [.ean13, .ean8, .upce, .code128, .code39, .code93, .itf14]
            self.metadataOutput.metadataObjectTypes =
                desired.filter { self.metadataOutput.availableMetadataObjectTypes.contains($0) }

            if !self.session.isRunning {
                self.session.startRunning()
            }
            if self.torchEnabled {
                self.applyTorch(true)
            }
        }
    }

    // AVCaptureMetadataOutputObjectsDelegate — called on the main queue.
    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !didEmit,
              let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let code = obj.stringValue,
              !code.isEmpty else { return }
        didEmit = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onBarcode?(code)
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.applyTorch(false)
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }
}

#else

// Fallback on platforms without UIKit/AVFoundation (e.g. previews on macOS without camera)
private struct CameraPreview: View {
    var isTorchOn: Bool = false
    var onBarcode: (String) -> Void = { _ in }
    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 6) {
                Image(systemName: "camera.fill")
                    .font(.sageRegular(32))
                    .foregroundColor(.white.opacity(0.5))
                Text("Camera unavailable")
                    .font(.sageSemiBold(13))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }
}

#endif
