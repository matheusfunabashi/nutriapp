import SwiftUI

// MARK: - SubHeader

struct SubHeader: View {
    let title: String
    let onBack: () -> Void
    var body: some View {
        ZStack {
            Text(title)
                .font(.sageBold(16)).tracking(-0.2)
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.sageSemiBold(15))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color.black.opacity(0.06)))
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
        .padding(.horizontal, 16).padding(.top, 60).padding(.bottom, 18)
    }
}

// MARK: - Personal Details

struct PersonalDetailsView: View {
    @EnvironmentObject var store: AppStore
    let onBack: () -> Void
    @State private var name: String = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        let dark = store.darkMode
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                SubHeader(title: "Personal Details", onBack: onBack)
                    .foregroundColor(Theme.textPrimary(dark))

                CardView(dark: dark) {
                    VStack(spacing: 0) {
                        editableNameRow(dark: dark)
                        editableRow(label: "Current weight",
                                    value: "\(store.user.weightLb) lb", divider: true, dark: dark)
                        editableRow(label: "Height",
                                    value: formatHeight(inches: store.user.heightIn), divider: true, dark: dark)
                        editableRow(label: "Date of birth",
                                    value: store.user.dob, divider: true, dark: dark)
                        editableRow(label: "Gender",
                                    value: store.user.sex.capitalized, divider: true, dark: dark)
                        editableRow(label: "Objective",
                                    value: store.user.objective.capitalized, divider: true, dark: dark)
                        editableRow(label: "Units",
                                    value: store.user.unitSystem.capitalized, divider: true, dark: dark)
                    }
                }
                .padding(.horizontal, 16)

                Spacer().frame(height: 60)
            }
        }
        .background(Theme.bg(dark).ignoresSafeArea())
        .onAppear { name = store.user.name }
    }

    private func editableNameRow(dark: Bool) -> some View {
        HStack(spacing: 12) {
            Text("Name")
                .font(.sageSemiBold(15)).tracking(-0.2)
                .foregroundColor(Theme.textPrimary(dark))
            TextField("", text: $name)
                .focused($nameFocused)
                .multilineTextAlignment(.trailing)
                .font(.sageBold(15)).tracking(-0.2)
                .foregroundColor(Theme.textPrimary(dark))
                .onSubmit { store.user.name = name }
            Image(systemName: "pencil")
                .font(.sageRegular(12))
                .foregroundColor(Theme.textSecondary(dark))
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }

    private func editableRow(label: String, value: String, divider: Bool, dark: Bool) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.sageSemiBold(15))
                .foregroundColor(Theme.textPrimary(dark))
            Spacer()
            Text(value)
                .font(.sageBold(15)).monospacedDigit()
                .foregroundColor(Theme.textPrimary(dark))
            Image(systemName: "pencil")
                .font(.sageRegular(12))
                .foregroundColor(Theme.textSecondary(dark))
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .overlay(alignment: .top) {
            if divider { Theme.divider(dark).frame(height: 0.5).padding(.horizontal, 8) }
        }
    }

    private func formatHeight(inches: Int) -> String {
        let ft = inches / 12, inch = inches % 12
        return "\(ft)'\(inch)\""
    }
}

// MARK: - Preferences

struct PreferencesView: View {
    @EnvironmentObject var store: AppStore
    let onBack: () -> Void

    var body: some View {
        let dark = store.darkMode
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                SubHeader(title: "Preferences", onBack: onBack)
                    .foregroundColor(Theme.textPrimary(dark))

                appearanceCard(dark: dark)
                togglesCard(dark: dark)
                Spacer().frame(height: 60)
            }
            .padding(.horizontal, 16)
        }
        .background(Theme.bg(dark).ignoresSafeArea())
    }

    private func appearanceCard(dark: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Appearance")
                .font(.sageBold(17)).tracking(-0.4)
                .foregroundColor(Theme.textPrimary(dark))
            Text("Choose light, dark, or system appearance")
                .font(.sageRegular(12))
                .foregroundColor(Theme.textSecondary(dark))
            HStack(spacing: 10) {
                AppearanceTile(id: "system", label: "System",
                               selected: store.user.appearance == "system",
                               onSelect: select)
                AppearanceTile(id: "light", label: "Light",
                               selected: store.user.appearance == "light",
                               onSelect: select)
                AppearanceTile(id: "dark", label: "Dark",
                               selected: store.user.appearance == "dark",
                               onSelect: select)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.surface(dark))
        )
        .cardShadow(dark)
    }

    private func togglesCard(dark: Bool) -> some View {
        CardView(dark: dark) {
            VStack(spacing: 0) {
                ToggleRowView(
                    title: "Badge celebrations",
                    desc: "Show a full-screen badge animation when you unlock a new badge",
                    isOn: Binding(get: { store.user.badgeCelebrations },
                                  set: { store.user.badgeCelebrations = $0 }),
                    divider: false, dark: dark)
                ToggleRowView(
                    title: "Live activity",
                    desc: "Show your daily scans and warnings on your lock screen and dynamic island",
                    isOn: Binding(get: { store.user.liveActivity },
                                  set: { store.user.liveActivity = $0 }),
                    divider: true, dark: dark)
                ToggleRowView(
                    title: "Auto-flag restrictions",
                    desc: "Always show a warning banner when a scan contains an ingredient you've restricted",
                    isOn: Binding(get: { store.user.autoFlagRestrictions },
                                  set: { store.user.autoFlagRestrictions = $0 }),
                    divider: true, dark: dark)
                ToggleRowView(
                    title: "Save scans to history",
                    desc: "Keep every product you scan in your history feed automatically",
                    isOn: Binding(get: { store.user.saveScansToHistory },
                                  set: { store.user.saveScansToHistory = $0 }),
                    divider: true, dark: dark)
                ToggleRowView(
                    title: "Personalize scoring",
                    desc: "Use your profile to compute Your Score in addition to the Overall score",
                    isOn: Binding(get: { store.user.personalizeScoring },
                                  set: { store.user.personalizeScoring = $0 }),
                    divider: true, dark: dark)
            }
        }
    }

    private func select(id: String) {
        store.user.appearance = id
        if id == "dark" { store.darkMode = true }
        else if id == "light" { store.darkMode = false }
    }
}

struct ToggleRowView: View {
    let title: String
    let desc: String
    @Binding var isOn: Bool
    let divider: Bool
    let dark: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.sageBold(15)).tracking(-0.2)
                    .foregroundColor(Theme.textPrimary(dark))
                Text(desc)
                    .font(.sageRegular(12))
                    .foregroundColor(Theme.textSecondary(dark))
                    .lineSpacing(2)
            }
            Spacer(minLength: 6)
            CustomToggle(isOn: $isOn, dark: dark).padding(.top, 2)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .overlay(alignment: .top) {
            if divider { Theme.divider(dark).frame(height: 0.5).padding(.horizontal, 8) }
        }
    }
}

struct AppearanceTile: View {
    let id: String
    let label: String
    let selected: Bool
    let onSelect: (String) -> Void
    var body: some View {
        Button { onSelect(id) } label: {
            VStack(spacing: 8) {
                preview
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.sageSemiBold(11))
                    Text(label)
                        .font(.sageBold(13)).tracking(-0.2)
                }
                .foregroundColor(Color(hex: "111111"))
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? Color(hex: "111111") : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
    private var icon: String {
        switch id {
        case "light": return "sun.max"
        case "dark":  return "moon.fill"
        default:      return "circle.lefthalf.filled"
        }
    }
    @ViewBuilder private var preview: some View {
        switch id {
        case "system":
            ZStack {
                Color(hex: "F5F4F0")
                Color(hex: "1F1F1F").clipShape(WedgeShape())
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        case "dark":
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: "1F1F1F"))
        default:
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: "F5F4F0"))
        }
    }
}

private struct WedgeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.width * 0.6, y: 0))
        p.addLine(to: CGPoint(x: rect.width, y: 0))
        p.addLine(to: CGPoint(x: rect.width, y: rect.height))
        p.addLine(to: CGPoint(x: rect.width * 0.6, y: rect.height))
        p.closeSubpath()
        return p
    }
}

// MARK: - Nutrition Goals (Objective)

struct NutritionGoalsView: View {
    @EnvironmentObject var store: AppStore
    let onBack: () -> Void

    struct Objective: Identifiable {
        let id: String, title: String, desc: String, systemImage: String, color: Color
    }
    let objectives: [Objective] = [
        Objective(id: "lose weight", title: "Lose weight",
                  desc: "Lower calorie density, higher protein, watch added sugars.",
                  systemImage: "chart.line.downtrend.xyaxis", color: Color(hex: "5793D6")),
        Objective(id: "maintain", title: "Maintain",
                  desc: "Balanced macros. Sage flags meaningful drift either direction.",
                  systemImage: "equal", color: Color(hex: "D9913C")),
        Objective(id: "build muscle", title: "Build muscle",
                  desc: "Bonus weight on protein and recovery carbs.",
                  systemImage: "chart.line.uptrend.xyaxis", color: Color(hex: "E16B5E")),
        Objective(id: "eat healthier", title: "Eat healthier",
                  desc: "Penalize ultra-processed, reward whole-food ingredients.",
                  systemImage: "leaf.fill", color: Color(hex: "1F8A5B")),
    ]

    var body: some View {
        let dark = store.darkMode
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                SubHeader(title: "Objective", onBack: onBack)
                    .foregroundColor(Theme.textPrimary(dark))
                Text("Pick the goal Sage should weigh against when scoring scans. You can change this anytime, your scores will recalculate.")
                    .font(.sageRegular(13))
                    .foregroundColor(Theme.textSecondary(dark))
                    .lineSpacing(2)
                    .padding(.horizontal, 24)
                VStack(spacing: 10) {
                    ForEach(objectives) { o in
                        let selected = store.user.objective == o.id
                        Button { store.user.objective = o.id } label: {
                            HStack(spacing: 14) {
                                Image(systemName: o.systemImage)
                                    .font(.sageSemiBold(18))
                                    .foregroundColor(o.color)
                                    .frame(width: 44, height: 44)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(o.color.opacity(0.10))
                                    )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(o.title)
                                        .font(.sageBold(15)).tracking(-0.2)
                                        .foregroundColor(Theme.textPrimary(dark))
                                    Text(o.desc)
                                        .font(.sageRegular(12))
                                        .foregroundColor(Theme.textSecondary(dark))
                                        .lineSpacing(2)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer()
                                Circle()
                                    .stroke(Theme.textPrimary(dark), lineWidth: selected ? 7 : 1.5)
                                    .frame(width: 22, height: 22)
                                    .background(Circle().fill(Color.white))
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(Theme.surface(dark))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(selected ? Theme.textPrimary(dark) : .clear, lineWidth: 1.5)
                            )
                            .cardShadow(dark)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 18)
                Spacer().frame(height: 60)
            }
        }
        .background(Theme.bg(dark).ignoresSafeArea())
    }
}

// MARK: - Dietary

struct DietaryView: View {
    @EnvironmentObject var store: AppStore
    let onBack: () -> Void

    @State private var customAllergy = ""
    @FocusState private var allergyFocused: Bool

    let restrictions = [
        "Vegan", "Vegetarian", "Pescatarian", "Low-sugar diet",
        "Low-sodium diet", "Gluten-free", "Dairy-free",
    ]
    let preferences = [
        "Low sugar", "Low sodium", "Low fat",
        "High protein", "High fiber", "Organic", "Minimally processed",
    ]

    var body: some View {
        let dark = store.darkMode
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                SubHeader(title: "Dietary preferences", onBack: onBack)
                    .foregroundColor(Theme.textPrimary(dark))

                card(title: "Restrictions",
                     desc: "Hard rules. Sage flags these as warnings on every scan.",
                     dark: dark) {
                    chipFlow(items: restrictions,
                             active: store.user.restrictions,
                             dark: dark) { v in toggle(\.restrictions, v) }
                }
                card(title: "Preferences",
                     desc: "Soft signals. They nudge Your Score, no warnings.",
                     dark: dark) {
                    chipFlow(items: preferences,
                             active: store.user.preferences,
                             dark: dark) { v in toggle(\.preferences, v) }
                }
                allergensCard(dark: dark)
                Spacer().frame(height: 60)
            }
            .padding(.horizontal, 16)
        }
        .background(Theme.bg(dark).ignoresSafeArea())
    }

    @ViewBuilder
    private func card<C: View>(title: String, desc: String, dark: Bool,
                               @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.sageBold(17)).tracking(-0.4)
                .foregroundColor(Theme.textPrimary(dark))
            Text(desc)
                .font(.sageRegular(12))
                .foregroundColor(Theme.textSecondary(dark))
                .lineSpacing(2)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.surface(dark))
        )
        .cardShadow(dark)
    }

    private func chipFlow(items: [String], active: [String], dark: Bool,
                          tap: @escaping (String) -> Void) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { item in
                ChipView(label: item, active: active.contains(item),
                         dark: dark, accent: store.accent) {
                    tap(item)
                }
            }
        }
    }

    private func toggle(_ keyPath: WritableKeyPath<UserProfile, [String]>, _ value: String) {
        var arr = store.user[keyPath: keyPath]
        if let i = arr.firstIndex(of: value) { arr.remove(at: i) } else { arr.append(value) }
        store.user[keyPath: keyPath] = arr
    }

    // MARK: Allergens

    private var allergies: [String] { store.user.allergies ?? [] }

    private var customAllergies: [String] {
        let presets = Set(AllergenCatalog.labels.map { $0.lowercased() })
        return allergies.filter { !presets.contains($0.lowercased()) }
    }

    private func allergensCard(dark: Bool) -> some View {
        card(title: "Allergens",
             desc: "We'll flag scans that may contain these. Data can be incomplete — always check the packaging.",
             dark: dark) {
            VStack(alignment: .leading, spacing: 14) {
                chipFlow(items: AllergenCatalog.labels, active: allergies, dark: dark) { v in
                    toggleAllergen(v)
                }

                HStack(spacing: 8) {
                    Image(systemName: "plus.circle")
                        .font(.sageRegular(15))
                        .foregroundColor(Theme.textSecondary(dark))
                    TextField("Add another allergy", text: $customAllergy)
                        .focused($allergyFocused)
                        .font(.sageMedium(14))
                        .foregroundColor(Theme.textPrimary(dark))
                        .submitLabel(.done)
                        .onSubmit { addCustomAllergy() }
                    if !customAllergy.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button("Add", action: addCustomAllergy)
                            .font(.sageBold(13))
                            .foregroundColor(store.accent)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(dark ? Color.white.opacity(0.05) : Theme.bgLight)
                )

                if !customAllergies.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(customAllergies, id: \.self) { a in
                            removableChip(a, dark: dark)
                        }
                    }
                }
            }
        }
    }

    private func removableChip(_ label: String, dark: Bool) -> some View {
        Button { removeAllergy(label) } label: {
            HStack(spacing: 5) {
                Text(label.capitalized)
                    .font(.sageBold(12)).tracking(-0.1)
                    .foregroundColor(store.accent)
                Image(systemName: "xmark")
                    .font(.sageBold(9))
                    .foregroundColor(store.accent)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Capsule().fill(store.accent.opacity(0.10)))
            .overlay(Capsule().stroke(store.accent, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func setAllergies(_ arr: [String]) { store.user.allergies = arr }

    private func toggleAllergen(_ value: String) {
        var arr = allergies
        if let i = arr.firstIndex(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) {
            arr.remove(at: i)
        } else {
            arr.append(value)
        }
        setAllergies(arr)
    }

    private func addCustomAllergy() {
        let t = customAllergy.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var arr = allergies
        if !arr.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) { arr.append(t) }
        setAllergies(arr)
        customAllergy = ""
        allergyFocused = false
    }

    private func removeAllergy(_ value: String) {
        setAllergies(allergies.filter { $0 != value })
    }
}

// MARK: - FlowLayout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x + s.width > maxW { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
            maxX = max(maxX, x)
        }
        return CGSize(width: maxW.isFinite ? maxW : maxX, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        let maxW = bounds.width
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x + s.width > maxW { x = 0; y += rowH + spacing; rowH = 0 }
            sub.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                      proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}
