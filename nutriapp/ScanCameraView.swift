import SwiftUI

struct ScanCameraView: View {
    @EnvironmentObject var store: AppStore
    let onClose: () -> Void
    let onHistory: () -> Void
    let onScanComplete: () -> Void

    enum Mode { case barcode, label }
    @State private var scanning = false
    @State private var mode: Mode = .barcode
    @State private var progress: Double = 0
    @State private var timer: Timer? = nil

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "34281C"), Color(hex: "1A120C"), Color(hex: "0A0705")],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()

            RadialGradient(colors: [Color(hex: "FFC88C").opacity(0.16), .clear],
                           center: .topLeading, startRadius: 30, endRadius: 320)
                .ignoresSafeArea()

            ProductMock()
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
        }
        .onDisappear { stop() }
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
            if !scanning {
                Text("Align the barcode")
                    .font(.system(size: 20, weight: .heavy)).tracking(-0.4)
                    .foregroundColor(.white)
                Text("We'll detect it automatically")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: store.accent))
                        .scaleEffect(0.7)
                    Text("Looking up… \(Int(progress))%")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(Capsule().fill(Color.black.opacity(0.65)))
            }
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
                if !scanning { start() }
            } label: {
                Circle()
                    .fill(scanning ? store.accent : Color.white)
                    .frame(width: 70, height: 70)
                    .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 4))
                    .scaleEffect(scanning ? 0.92 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: scanning)
            }
            .buttonStyle(.plain)
            Spacer()
            CameraCircleBtn(systemName: "questionmark", size: 42)
        }
        .padding(.horizontal, 32)
    }

    private func start() {
        scanning = true
        progress = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { _ in
            progress += 5 + Double.random(in: 0...6)
            if progress >= 100 {
                progress = 100
                stop()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { onScanComplete() }
            }
        }
    }
    private func stop() {
        timer?.invalidate()
        timer = nil
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

private struct ProductMock: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("HILLTOP CREAMERY")
                .font(.system(size: 9, weight: .heavy)).tracking(1.4)
                .foregroundColor(Color(hex: "1F8A5B"))
            Text("PLAIN GREEK YOGURT")
                .font(.system(size: 14, weight: .heavy)).tracking(-0.3)
                .foregroundColor(Color(hex: "222222"))
                .padding(.top, 4)

            HStack(spacing: 1) {
                ForEach([2,1,3,1,2,1,1,3,2,1,3,1,2,1,1,2,3,1,2,1,3,2,1,2,3,1,1,2], id: \.self) { _ in
                    Rectangle().fill(Color(hex: "222222")).frame(width: 2, height: 40)
                    Rectangle().fill(Color.clear).frame(width: 1, height: 40)
                }
            }
            .padding(.top, 24)
            Text("0 41234 56789 2")
                .font(.system(size: 7, weight: .semibold))
                .foregroundColor(Color(hex: "666666"))
                .tracking(1)
        }
        .padding(16)
        .frame(width: 240, height: 200)
        .background(LinearGradient(colors: [Color(hex: "F8F3E8"), Color(hex: "DDD2BD")],
                                   startPoint: .top, endPoint: .bottom))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.5), radius: 18, x: 0, y: 18)
        .offset(y: -60)
    }
}
