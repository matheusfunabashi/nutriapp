import SwiftUI

struct ScannerHomeView: View {
    @EnvironmentObject var store: AppStore
    let onTapScan: () -> Void
    let onTapHistory: () -> Void
    let onOpenProduct: (String) -> Void

    var body: some View {
        let dark = store.darkMode
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                header(dark: dark)
                // Split + stagger: greeting → hero → quick action → recent → tip.
                // Each chunk fades, blurs, and lifts independently, matching
                // the skill's "don't animate one big container" rule.
                StaggeredAppear(index: 0) { greeting(dark: dark) }
                StaggeredAppear(index: 1) {
                    heroCard(dark: dark)
                        .padding(.horizontal, 16)
                        .padding(.top, 12).padding(.bottom, 6)
                }
                StaggeredAppear(index: 2) {
                    quickAction(dark: dark)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                }
                StaggeredAppear(index: 3) { recentSection(dark: dark) }
                StaggeredAppear(index: 4) { tip(dark: dark) }
                Spacer().frame(height: 120)
            }
        }
        .background(Theme.bg(dark).ignoresSafeArea())
    }

    private func header(dark: Bool) -> some View {
        HStack {
            HStack(spacing: 8) {
                SageMark(size: 26, color: store.accent)
                Text("Sage")
                    .font(.system(size: 22, weight: .heavy)).tracking(-0.6)
                    .foregroundColor(Theme.textPrimary(dark))
            }
            .debugMenuTap()
            Spacer()
            Button(action: onTapHistory) {
                ZStack {
                    Circle().fill(dark ? Color.white.opacity(0.08) : Color.white)
                    Image(systemName: "list.bullet")
                        .foregroundColor(Theme.textPrimary(dark))
                        .font(.system(size: 15, weight: .semibold))
                }
                .frame(width: 38, height: 38)
                .cardShadow(dark)
                .minHitArea(44) // visible 38pt; tap target lifts to 44 (WCAG)
            }
            .buttonStyle(.pressable)
        }
        // Top padding = 12pt above the system safe-area inset. The parent
        // ZStack in ContentView does NOT ignoreSafeArea for its content,
        // so the inset already accounts for the status bar / Dynamic Island.
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 4)
    }

    private func greeting(dark: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Good morning, \(store.user.name)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.textSecondary(dark))
            Text("What are you eating?")
                .font(.system(size: 26, weight: .bold)).tracking(-0.6)
                .foregroundColor(Theme.textPrimary(dark))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 8)
    }

    private func heroCard(dark: Bool) -> some View {
        Button(action: onTapScan) {
            ZStack(alignment: .topTrailing) {
                ZStack(alignment: .topLeading) {
                    LinearGradient(
                        colors: [store.accent, Color(hex: "0C5A3B")],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 6) {
                            Circle().fill(Color.white).frame(width: 6, height: 6)
                            Text("READY")
                                .font(.system(size: 10, weight: .heavy)).tracking(1.4)
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.18)))

                        Text("Tap to scan")
                            .font(.system(size: 32, weight: .heavy)).tracking(-1)
                            .foregroundColor(.white)
                            .padding(.top, 16)
                        Text("Point your camera at any food barcode for an instant rating.")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.8))
                            .lineSpacing(2)
                            .padding(.top, 6)
                            .frame(maxWidth: 230, alignment: .leading)

                        HStack(spacing: 10) {
                            ZStack {
                                Circle().fill(store.accent)
                                Image(systemName: "viewfinder")
                                    .font(.system(size: 12, weight: .heavy))
                                    .foregroundColor(.white)
                            }
                            .frame(width: 24, height: 24)
                            Text("Open scanner")
                                .font(.system(size: 14, weight: .heavy))
                                .tracking(-0.2)
                                .foregroundColor(.black)
                        }
                        .padding(.leading, 4).padding(.trailing, 18)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(Color.white))
                        .padding(.top, 22)
                    }
                    .padding(24)
                }
                ScanBrackets(color: Color.white.opacity(0.4))
                    .frame(width: 64, height: 64).padding(18)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: store.accent.opacity(0.25), radius: 24, x: 0, y: 14)
        }
        .buttonStyle(.pressable)
    }

    private func quickAction(dark: Bool) -> some View {
        Button(action: onTapScan) {
            HStack(spacing: 12) {
                Text("✏️").font(.system(size: 22))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Manual entry")
                        .font(.system(size: 13, weight: .heavy)).tracking(-0.2)
                        .foregroundColor(Theme.textPrimary(dark))
                    Text("Can't find it? Enter it yourself")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary(dark))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.textSecondary(dark))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface(dark))
            )
            .cardShadow(dark)
        }
        .buttonStyle(.pressable)
    }

    private func recentSection(dark: Bool) -> some View {
        let recent = Array(store.history.prefix(5))
        return VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent scans")
                    .font(.system(size: 18, weight: .bold)).tracking(-0.4)
                    .foregroundColor(Theme.textPrimary(dark))
                Spacer()
                if !recent.isEmpty {
                    Button(action: onTapHistory) {
                        Text("See all")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Theme.textSecondary(dark))
                            .padding(.vertical, 8).padding(.leading, 12) // larger hit area
                    }
                    .buttonStyle(.pressable)
                }
            }
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 10)

            if recent.isEmpty {
                VStack(spacing: 4) {
                    Text("No scans yet")
                        .font(.system(size: 14, weight: .heavy)).tracking(-0.2)
                        .foregroundColor(Theme.textPrimary(dark))
                    Text("Your scanned products will appear here.")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary(dark))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28).padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface(dark))
                )
                .cardShadow(dark)
                .padding(.horizontal, 16)
            } else {
                VStack(spacing: 8) {
                    ForEach(recent) { h in
                        if let p = store.products[h.productId] {
                            RecentRow(product: p, dark: dark) {
                                onOpenProduct(p.id)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func tip(dark: Bool) -> some View {
        Text("Sage looks up the same barcode in our public database, then re-scores it for your profile.")
            .font(.system(size: 12))
            .foregroundColor(Theme.textSecondary(dark))
            .lineSpacing(2)
            .padding(.horizontal, 24).padding(.top, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RecentRow: View {
    let product: Product
    let dark: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ProductThumb(glyph: product.glyph, score: product.yourScore, size: 48,
                             imageURL: product.imageURL)
                Text(product.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Theme.textPrimary(dark))
                    .lineLimit(1)
                Spacer(minLength: 8)
                CompactScoreRing(score: product.yourScore, dark: dark)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.textSecondary(dark))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface(dark))
            )
            .cardShadow(dark)
        }
        .buttonStyle(.pressable)
    }
}

struct ScanBrackets: View {
    let color: Color
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            Path { p in
                p.move(to: CGPoint(x: 4, y: 18)); p.addLine(to: CGPoint(x: 4, y: 8))
                p.addQuadCurve(to: CGPoint(x: 8, y: 4), control: CGPoint(x: 4, y: 4))
                p.addLine(to: CGPoint(x: 18, y: 4))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            Path { p in
                p.move(to: CGPoint(x: w - 4, y: 18)); p.addLine(to: CGPoint(x: w - 4, y: 8))
                p.addQuadCurve(to: CGPoint(x: w - 8, y: 4), control: CGPoint(x: w - 4, y: 4))
                p.addLine(to: CGPoint(x: w - 18, y: 4))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            Path { p in
                p.move(to: CGPoint(x: 4, y: h - 18)); p.addLine(to: CGPoint(x: 4, y: h - 8))
                p.addQuadCurve(to: CGPoint(x: 8, y: h - 4), control: CGPoint(x: 4, y: h - 4))
                p.addLine(to: CGPoint(x: 18, y: h - 4))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            Path { p in
                p.move(to: CGPoint(x: w - 4, y: h - 18)); p.addLine(to: CGPoint(x: w - 4, y: h - 8))
                p.addQuadCurve(to: CGPoint(x: w - 8, y: h - 4), control: CGPoint(x: w - 4, y: h - 4))
                p.addLine(to: CGPoint(x: w - 18, y: h - 4))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
    }
}
