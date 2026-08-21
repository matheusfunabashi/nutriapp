import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var store: AppStore
    let onOpenPersonal: () -> Void
    let onOpenPreferences: () -> Void
    let onOpenNutritionGoals: () -> Void
    let onOpenDietary: () -> Void
    let onOpenMethodology: () -> Void
    let onOpenDisclaimer: () -> Void

    var body: some View {
        List {
            Section {
                Button(action: onOpenPersonal) { identityRow }
                    .buttonStyle(.plain)
            }

            Section("Account") {
                ProfileRow(systemImage: "person.text.rectangle",
                           label: "Personal Details", action: onOpenPersonal)
                ProfileRow(systemImage: "target", label: "Objective",
                           value: store.user.objective.capitalized,
                           action: onOpenNutritionGoals)
                ProfileRow(systemImage: "wand.and.stars", label: "Personalize",
                           action: onOpenDietary)
                ProfileRow(systemImage: "character.book.closed", label: "Language",
                           value: "English")
                ProfileRow(systemImage: "slider.horizontal.3", label: "Preferences",
                           action: onOpenPreferences)
            }

            Section("Help") {
                ProfileRow(systemImage: "info.circle", label: "How we score",
                           action: onOpenMethodology)
                ProfileRow(systemImage: "shield", label: "Disclaimer",
                           action: onOpenDisclaimer)
                ProfileRow(systemImage: "lifepreserver", label: "Support")
            }

            Section {
                Text("Sage \(Self.appVersion) · Database from Open Food Facts")
                    .font(.sageRegular(11))
                    .foregroundColor(Theme.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            }
        }
        .sageListStyle()
        .navigationTitle("Profile")
    }

    private static var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return "v\(v ?? "1.0")"
    }

    private var identityRow: some View {
        let isPremium = store.user.subscriptionStatus != "expired"
        let subLabel: String = {
            switch store.user.subscriptionStatus {
            case "trial":  return "Trial · \(store.user.subscriptionDaysLeft)d"
            case "active": return "Premium"
            default:       return "Expired"
            }
        }()
        return HStack(spacing: 14) {
            ZStack {
                Circle().fill(LinearGradient(
                    colors: [store.accent, store.accent.opacity(0.6)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                Text(initials(store.user.name))
                    .font(.sageBold(20)).tracking(-0.5)
                    .foregroundColor(.white)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 2) {
                if isPremium {
                    HStack(spacing: 4) {
                        Image(systemName: "crown.fill")
                            .foregroundColor(Color(hex: ScoreBandColor.okMid))
                            .font(.sageRegular(11))
                        Text(subLabel)
                            .font(.sageBold(11))
                            .monospacedDigit() // "5d" countdown stays aligned
                            .foregroundColor(Theme.inkSecondary)
                    }
                }
                Text(displayName(store.user.name))
                    .font(.sageBold(16)).tracking(-0.4)
                    .foregroundColor(Theme.ink)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(Theme.inkSecondary)
                .font(.sageBold(12))
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

/// A settings row. Inside a `List` the system supplies the separator, the press
/// highlight, and the full-width hit area — so this only describes content.
struct ProfileRow: View {
    let systemImage: String?
    let label: String
    var value: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 12) {
            if let n = systemImage {
                Image(systemName: n)
                    .foregroundColor(Theme.ink)
                    .frame(width: 22)
            }
            Text(label)
                .font(.sageBold(15)).tracking(-0.2)
                .foregroundColor(Theme.ink)
            Spacer()
            if let v = value {
                Text(v)
                    .font(.sageSemiBold(13))
                    .foregroundColor(Theme.inkSecondary)
            }
            if action != nil {
                Image(systemName: "chevron.right")
                    .font(.sageBold(12))
                    .foregroundColor(Theme.inkSecondary)
            }
        }
        .contentShape(Rectangle())
    }
}

func displayName(_ s: String) -> String {
    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "You" : trimmed
}

func initials(_ s: String) -> String {
    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "?" }
    return trimmed.split(separator: " ").prefix(2)
        .map { $0.first.map(String.init) ?? "" }
        .joined()
        .uppercased()
}
