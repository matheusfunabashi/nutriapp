import SwiftUI

// MARK: - Act 2 · How it works
//
// Three chained cards on the inverted background. The middle card is Your
// Score rather than a generic "we rate it" step, so the product model the
// user learns here is the one the demo pays off two acts later.

struct OnboardingHowItWorksScreen: View {
    struct Stage: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let blurb: String
    }

    let accent: Color

    private let stages: [Stage] = [
        .init(symbol: "barcode.viewfinder",
              title: "Scan anything",
              blurb: "1.2M products, or point the camera at any ingredient list."),
        .init(symbol: "person.crop.circle.badge.checkmark",
              title: "Get Your Score",
              blurb: "Not just the label's grade. A second score, recalculated from your goals."),
        .init(symbol: "arrow.triangle.swap",
              title: "Swap it",
              blurb: "A cleaner option from the same shelf, ranked for you."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            StaggeredAppear(index: 0) {
                OnboardingInvertedTitle(
                    title: "How Sage works",
                    subtitle: "Three steps, about ten seconds in the aisle."
                )
            }

            VStack(spacing: 0) {
                ForEach(Array(stages.enumerated()), id: \.element.id) { idx, stage in
                    StaggeredAppear(index: idx + 1) {
                        stageCard(stage)
                    }
                    if idx < stages.count - 1 {
                        StaggeredAppear(index: idx + 1) {
                            Image(systemName: "arrow.down")
                                .font(.sageSemiBold(14))
                                .foregroundStyle(OnboardingInverted.inkSecondary)
                                .padding(.vertical, 10)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)

            Spacer()
        }
    }

    private func stageCard(_ stage: Stage) -> some View {
        HStack(spacing: 14) {
            Image(systemName: stage.symbol)
                .font(.sageSemiBold(17))
                .foregroundStyle(accent)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.white.opacity(0.10)))

            VStack(alignment: .leading, spacing: 4) {
                Text(stage.title)
                    .font(.sageBold(16)).tracking(-0.3)
                    .foregroundStyle(OnboardingInverted.ink)
                Text(stage.blurb)
                    .font(.sageRegular(13))
                    .lineSpacing(2)
                    .foregroundStyle(OnboardingInverted.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(OnboardingInverted.surface)
        )
    }
}

// MARK: - Act 2 · The pledge
//
// Every competitor runs some version of this screen, and it's the cheapest
// trust we can buy: one sentence, no illustration. Sage's version is
// specific about the failure mode it rules out (paid placement) rather than
// a vague promise to be honest.

struct OnboardingPledgeScreen: View {
    let accent: Color

    private let commitments: [(String, String)] = [
        ("dollarsign.circle", "No brand can pay to change a score, appear as an alternative, or be left out of one."),
        ("doc.text.magnifyingglass", "Every score traces back to a published ruleset you can read."),
        ("hand.raised", "Your scans and profile stay on your device."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            StaggeredAppear(index: 0) {
                OnboardingInvertedTitle(title: "The Sage pledge")
            }

            StaggeredAppear(index: 1) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("We will never take a cent\nfrom a brand we score.")
                        .font(.sageBold(24)).tracking(-0.6)
                        .foregroundStyle(OnboardingInverted.ink)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(OnboardingInverted.surface)
                        )
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.sageBold(26))
                                .foregroundStyle(accent)
                                .padding(10)
                                .background(Circle().fill(OnboardingInverted.background))
                                .offset(x: 10, y: -14)
                        }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
            }

            StaggeredAppear(index: 2) {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(commitments.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: item.0)
                                .font(.sageSemiBold(14))
                                .foregroundStyle(accent)
                                .frame(width: 22)
                            Text(item.1)
                                .font(.sageRegular(14))
                                .lineSpacing(2)
                                .foregroundStyle(OnboardingInverted.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
            }

            Spacer()
        }
    }
}
