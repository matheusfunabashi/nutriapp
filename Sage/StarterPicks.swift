import SwiftUI

// MARK: - Starter content for first-run empty states
//
// A blank "nothing here yet" screen is the weakest moment in the funnel, and
// Sage never has to show one: the bundle already carries ~1,700 scored
// products across the Top Rated shelves. These helpers turn that into
// goal-aware starter content (Spotify's genre cards, Gemini's suggestion
// cards) so Home, History and Favorites always have something real to tap
// before the first scan.

enum StarterPicks {
    /// Shelves ordered by relevance to what the user told us in onboarding.
    /// Merged in goal order, deduped, so two goals interleave sensibly.
    static func shelves(for profile: UserProfile) -> [SageCategory] {
        let byGoal: [String: [SageCategory]] = [
            "More protein":   [.eggs, .yogurt, .nutButtersAndSpreads, .cheese, .milks, .snackBars, .bread],
            "Heart health":   [.fatsAndOils, .bread, .cereal, .pasta, .nutButtersAndSpreads, .yogurt],
            "Less sugar":     [.yogurt, .cereal, .snackBars, .nutButtersAndSpreads, .bread, .chocolate],
            "Less processed": [.eggs, .bread, .pasta, .cheese, .nutButtersAndSpreads, .yogurt, .fatsAndOils],
        ]
        let fallback: [SageCategory] = [.yogurt, .eggs, .fatsAndOils, .nutButtersAndSpreads,
                                        .bread, .cereal, .cheese, .pasta, .snackBars]
        var out: [SageCategory] = []
        for goal in profile.healthGoals ?? [] {
            for shelf in byGoal[goal] ?? [] where !out.contains(shelf) { out.append(shelf) }
        }
        for shelf in fallback where !out.contains(shelf) { out.append(shelf) }
        return out
    }

    /// The best product with a photo from each relevant shelf, up to `limit`.
    /// Scoring reads the bundled ruleset, so call from a `.task`, not a body.
    @MainActor
    static func picks(for profile: UserProfile, limit: Int = 6) -> [Alternative] {
        var out: [Alternative] = []
        for shelf in shelves(for: profile) where out.count < limit {
            let ranked = TopRated.items(for: shelf, profile: profile)
            if let pick = ranked.first(where: { $0.product.listImageURL != nil }) ?? ranked.first {
                out.append(pick)
            }
        }
        return out
    }

    /// What the user asked Sage to watch for — avoid-list first (the sharpest
    /// signal), then goals. Empty when they skipped both steps.
    static func watchlist(for profile: UserProfile) -> [String] {
        var items = profile.avoidList ?? []
        for goal in profile.healthGoals ?? [] where !items.contains(goal) { items.append(goal) }
        return items
    }
}

// MARK: - Compact intro card
//
// Replaces the centered icon-in-a-void. Sits at the top of the list where the
// eye lands, says what the screen *will* be, and hands off to real content
// directly below it.

struct StarterIntroCard: View {
    let symbol: String
    let title: String
    let message: String
    var cta: (title: String, action: () -> Void)? = nil

    @EnvironmentObject private var store: AppStore

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.sageSemiBold(16))
                .foregroundStyle(store.accent)
                .frame(width: 40, height: 40)
                .background(Circle().fill(store.accent.opacity(0.12)))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.sageBold(15)).tracking(-0.2)
                    .foregroundStyle(Theme.ink)
                Text(message)
                    .font(.sageRegular(13))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let cta {
                    Button(cta.title, action: cta.action)
                        .font(.sageSemiBold(13))
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                        .tint(store.accent)
                        .padding(.top, 6)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.card)
        )
        .cardShadow()
    }
}

// MARK: - Carousel card (Home)

struct StarterPickCard: View {
    let pick: Alternative
    let onTap: () -> Void

    @EnvironmentObject private var store: AppStore
    @State private var heartTick = 0

    /// The engine's strongest positive drivers for *this* user — the reason
    /// the pick is on their Home, not a generic "great choice".
    private var whyLine: String? {
        let positives = ScoringEngine.signedFactors(pick.product, profile: store.user)
            .filter { $0.hasPrefix("+ ") }
            .map { String($0.dropFirst(2)) }
            .prefix(2)
        guard !positives.isEmpty else { return nil }
        return "+ " + positives.joined(separator: " · ")
    }

    var body: some View {
        let formatted = ProductNameFormatter.format(pick.product)
        let saved = store.isFavorite(pick.product.id)
        return Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                ProductThumb(glyph: pick.product.glyph, score: pick.score, size: 72,
                             neutral: true,
                             imageURL: pick.product.listImageURL,
                             fallbackImageURL: pick.product.imageFallbackURL,
                             processCutout: pick.product.shouldProcessCutout)
                    .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 2) {
                    if let brand = formatted.brand {
                        Text(brand)
                            .font(.sageBold(10)).tracking(0.4)
                            .foregroundStyle(Theme.inkSecondary)
                            .lineLimit(1)
                    }
                    Text(formatted.name)
                        .font(.sageSemiBold(13)).tracking(-0.2)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(minHeight: 34, alignment: .top)
                }
                VStack(alignment: .leading, spacing: 6) {
                    YourScorePill(score: pick.score, isUnscored: false)
                    Text(whyLine ?? " ")
                        .font(.sageSemiBold(11))
                        .foregroundStyle(Color.scoreGood)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(minHeight: 28, alignment: .top)
                }
            }
            .padding(12)
            .frame(width: 164, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.card)
            )
            .cardShadow()
        }
        .buttonStyle(.pressable)
        .overlay(alignment: .topTrailing) {
            // Save without leaving Home — the same heart as the product page.
            Button {
                store.toggleFavorite(pick.product)
                heartTick &+= 1
            } label: {
                Image(systemName: saved ? "heart.fill" : "heart")
                    .font(.sageSemiBold(13))
                    .foregroundStyle(saved ? store.accent : Theme.inkSecondary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Theme.fillQuiet))
            }
            .buttonStyle(.plain)
            .padding(8)
            .sensoryFeedback(.selection, trigger: heartTick)
            .accessibilityLabel(saved ? "Remove from favorites" : "Add to favorites")
        }
        .accessibilityLabel("\(formatted.accessibilityLabel), scored \(pick.score)")
    }
}

// MARK: - List row (Pantry)

/// A starter product row for the History / Favorites empty states. Same
/// anatomy as `ProductRow`, with an optional trailing heart so Favorites can
/// be seeded without leaving the screen.
struct StarterProductRow: View {
    let pick: Alternative
    var showsHeart: Bool = false
    let onOpen: () -> Void

    @EnvironmentObject private var store: AppStore
    @State private var tick = 0

    var body: some View {
        let formatted = ProductNameFormatter.format(pick.product)
        let saved = store.isFavorite(pick.product.id)
        return HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    ProductThumb(glyph: pick.product.glyph, score: pick.score, size: 56,
                                 imageURL: pick.product.listImageURL,
                                 fallbackImageURL: pick.product.imageFallbackURL,
                                 processCutout: pick.product.shouldProcessCutout)
                    VStack(alignment: .leading, spacing: 1) {
                        if let brand = formatted.brand {
                            Text(brand.uppercased())
                                .font(.sageBold(10)).tracking(1.2)
                                .foregroundColor(Theme.inkSecondary)
                                .lineLimit(1)
                        }
                        Text(formatted.name)
                            .font(.sageBold(14)).tracking(-0.2)
                            .foregroundColor(Theme.ink)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    YourScorePill(score: pick.score, isUnscored: false)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsHeart {
                Button {
                    store.toggleFavorite(pick.product)
                    tick &+= 1
                } label: {
                    Image(systemName: saved ? "heart.fill" : "heart")
                        .font(.sageSemiBold(16))
                        .foregroundStyle(saved ? store.accent : Theme.inkSecondary)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: tick)
                .accessibilityLabel(saved ? "Remove from favorites" : "Add to favorites")
            } else {
                Image(systemName: "chevron.right")
                    .font(.sageBold(12))
                    .foregroundColor(Theme.inkSecondary)
            }
        }
    }
}
