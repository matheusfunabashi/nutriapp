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

    enum Mode { case barcode, label }
    @State private var mode: Mode = .barcode
    @State private var showToast = false
    @State private var toastTimer: Timer? = nil
    @State private var didEmit = false

    var body: some View {
        ZStack {
            CameraPreview(onBarcode: handleBarcode)
                .ignoresSafeArea()
                .background(Color.black.ignoresSafeArea())

            // Vignette so the chrome stays readable over any scene
            LinearGradient(
                colors: [Color.black.opacity(0.55), .clear, Color.black.opacity(0.75)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            CutoutMask(mode: mode)
            CornerBrackets(mode: mode)

            VStack {
                topBar
                Spacer()
                hintArea
                Spacer().frame(height: 30)
                modeSegments.padding(.bottom, 20)
                shutterRow.padding(.bottom, 40)
            }

            if showToast {
                VStack {
                    Spacer()
                    Text("Database coming soon")
                        .font(.system(size: 14, weight: .heavy)).tracking(-0.2)
                        .foregroundColor(.white)
                        .padding(.horizontal, 18).padding(.vertical, 11)
                        .background(Capsule().fill(Color.black.opacity(0.78)))
                        .padding(.bottom, 180)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: showToast)
        .onDisappear { toastTimer?.invalidate() }
    }

    private var topBar: some View {
        HStack {
            CameraCircleBtn(systemName: "xmark", action: onClose)
            Spacer()
            Text(mode == .barcode ? "Scan barcode" : "Scan label")
                .font(.system(size: 14, weight: .semibold)).tracking(-0.2)
                .foregroundColor(.white)
            Spacer()
            CameraCircleBtn(systemName: "list.bullet", action: onHistory)
        }
        .padding(.horizontal, 16).padding(.top, 60)
    }

    private var hintArea: some View {
        VStack(spacing: 6) {
            Text("Align the barcode")
                .font(.system(size: 20, weight: .heavy)).tracking(-0.4)
                .foregroundColor(.white)
            Text("Hold steady — we'll detect it automatically")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
        .offset(y: -80)
    }

    private var modeSegments: some View {
        HStack(spacing: 8) {
            ForEach([(Mode.barcode, "Barcode"), (Mode.label, "Manual entry")], id: \.1) { (m, label) in
                let active = mode == m
                Button { mode = m } label: {
                    Text(label)
                        .font(.system(size: 13, weight: .heavy)).tracking(-0.1)
                        .foregroundColor(active ? Color(hex: "111111") : .white.opacity(0.95))
                        .padding(.vertical, 11)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(active ? Color.white : Color.black.opacity(0.5))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }

    private var shutterRow: some View {
        HStack {
            CameraCircleBtn(systemName: "bolt", size: 42)
            Spacer()
            Button {
                flashToast()
            } label: {
                Circle()
                    .fill(Color.white)
                    .frame(width: 70, height: 70)
                    .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 4))
            }
            .buttonStyle(.plain)
            Spacer()
            CameraCircleBtn(systemName: "questionmark", size: 42)
        }
        .padding(.horizontal, 32)
    }

    private func flashToast() {
        showToast = true
        toastTimer?.invalidate()
        toastTimer = Timer.scheduledTimer(withTimeInterval: 1.6, repeats: false) { _ in
            showToast = false
        }
    }

    private func handleBarcode(_ code: String) {
        // Only act in barcode mode, and only fire once per camera session.
        guard mode == .barcode, !didEmit else { return }
        didEmit = true
        onScanComplete(code)
    }
}

private struct CameraCircleBtn: View {
    let systemName: String
    var size: CGFloat = 38
    var action: () -> Void = {}
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.black.opacity(0.45)))
        }
        .buttonStyle(.plain)
    }
}

private struct CutoutMask: View {
    let mode: ScanCameraView.Mode
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let dims: (CGFloat, CGFloat) = mode == .barcode ? (290, 180) : (280, 320)
            let rectW = dims.0, rectH = dims.1
            let topY = h * 0.46
            let cx = w / 2

            Color.black.opacity(0.55)
                .mask(
                    ZStack {
                        Rectangle().fill(Color.white)
                        RoundedRectangle(cornerRadius: 22)
                            .fill(Color.black)
                            .frame(width: rectW, height: rectH)
                            .position(x: cx, y: topY)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                )
                .allowsHitTesting(false)
        }
    }
}

private struct CornerBrackets: View {
    let mode: ScanCameraView.Mode
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let dims: (CGFloat, CGFloat) = mode == .barcode ? (290, 180) : (280, 320)
            let rectW = dims.0, rectH = dims.1
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
        Path { p in
            p.move(to: CGPoint(x: x, y: y + 32 * y2))
            p.addLine(to: CGPoint(x: x, y: y))
            p.addLine(to: CGPoint(x: x + 32 * x2, y: y))
        }
        .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
    }
}

// MARK: - Live camera preview

#if canImport(UIKit) && canImport(AVFoundation)

private struct CameraPreview: UIViewRepresentable {
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
    private let sessionQueue = DispatchQueue(label: "nutriapp.camera.session")
    private let metadataOutput = AVCaptureMetadataOutput()
    private var didEmit = false

    var onBarcode: ((String) -> Void)?

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
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }
}

#else

// Fallback on platforms without UIKit/AVFoundation (e.g. previews on macOS without camera)
private struct CameraPreview: View {
    var onBarcode: (String) -> Void = { _ in }
    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 6) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.white.opacity(0.5))
                Text("Camera unavailable")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }
}

#endif
