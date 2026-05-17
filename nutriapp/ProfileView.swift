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
        let dark = store.darkMode
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Profile")
                    .font(.system(size: 34, weight: .heavy)).tracking(-1)
                    .foregroundColor(Theme.textPrimary(dark))
                    .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 12)

                identityCard(dark: dark).padding(.horizontal, 16).padding(.top, 8)

                sectionLabel("Account", dark: dark)
                CardView(dark: dark) {
                    VStack(spacing: 0) {
                        ProfileRow(systemImage: "person.text.rectangle",
                                   label: "Personal Details", divider: false,
                                   dark: dark, onTap: onOpenPersonal)
                        ProfileRow(systemImage: "target", label: "Objective",
                                   value: store.user.objective.capitalized,
                                   divider: true, dark: dark, onTap: onOpenNutritionGoals)
                        ProfileRow(systemImage: "flag", label: "Dietary preferences",
                                   divider: true, dark: dark, onTap: onOpenDietary)
                        ProfileRow(systemImage: "character.book.closed", label: "Language",
                                   value: "English", divider: true, dark: dark)
                        ProfileRow(systemImage: "slider.horizontal.3", label: "Preferences",
                                   divider: true, dark: dark, onTap: onOpenPreferences)
                    }
                }
                .padding(.horizontal, 16)

                sectionLabel("Help", dark: dark)
                CardView(dark: dark) {
                    VStack(spacing: 0) {
                        ProfileRow(systemImage: "info.circle", label: "How we score",
                                   divider: false, dark: dark, onTap: onOpenMethodology)
                        ProfileRow(systemImage: "shield", label: "Disclaimer",
                                   divider: true, dark: dark, onTap: onOpenDisclaimer)
                        ProfileRow(systemImage: "lifepreserver", label: "Support",
                                   divider: true, dark: dark)
                    }
                }
                .padding(.horizontal, 16)

                Text("Sage v1.0.3 · Database from Open Food Facts")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary(dark))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 24).padding(.top, 32).padding(.bottom, 24)

                Spacer().frame(height: 120)
            }
        }
        .background(Theme.bg(dark).ignoresSafeArea())
    }

    private func identityCard(dark: Bool) -> some View {
        let isPremium = store.user.subscriptionStatus != "expired"
        let subLabel: String = {
            switch store.user.subscriptionStatus {
            case "trial":  return "Trial · \(store.user.subscriptionDaysLeft)d"
            case "active": return "Premium"
            default:       return "Expired"
            }
        }()
        return Button(action: onOpenPersonal) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(LinearGradient(
                        colors: [store.accent, store.accent.opacity(0.6)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text(initials(store.user.name))
                        .font(.system(size: 19, weight: .heavy)).tracking(-0.5)
                        .foregroundColor(.white)
                }
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 2) {
                    if isPremium {
                        HStack(spacing: 5) {
                            Image(systemName: "crown.fill")
                                .foregroundColor(Color(hex: "D4A437"))
                                .font(.system(size: 11))
                            Text(subLabel)
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundColor(Theme.textSecondary(dark))
                        }
                    }
                    Text(store.user.name)
                        .font(.system(size: 17, weight: .heavy)).tracking(-0.4)
                        .foregroundColor(Theme.textPrimary(dark))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(Theme.textSecondary(dark))
                    .font(.system(size: 12, weight: .bold))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.surface(dark))
            )
            .cardShadow(dark)
        }
        .buttonStyle(.plain)
    }

    private func sectionLabel(_ text: String, dark: Bool) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(Theme.textSecondary(dark))
            .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ProfileRow: View {
    let systemImage: String?
    let label: String
    var value: String? = nil
    let divider: Bool
    let dark: Bool
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 12) {
                if let n = systemImage {
                    Image(systemName: n)
                        .foregroundColor(Theme.textPrimary(dark))
                        .frame(width: 22)
                }
                Text(label)
                    .font(.system(size: 15, weight: .heavy)).tracking(-0.2)
                    .foregroundColor(Theme.textPrimary(dark))
                Spacer()
                if let v = value {
                    Text(v)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.textSecondary(dark))
                }
                if onTap != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Theme.textSecondary(dark))
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .overlay(alignment: .top) {
                if divider {
                    Theme.divider(dark).frame(height: 0.5).padding(.horizontal, 12)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
    }
}

func initials(_ s: String) -> String {
    s.split(separator: " ").prefix(2).map { $0.first.map(String.init) ?? "" }.joined().uppercased()
}
