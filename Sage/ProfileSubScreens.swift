import SwiftUI

// MARK: - Personal Details

struct PersonalDetailsView: View {
    @EnvironmentObject var store: AppStore
    @State private var name: String = ""

    var body: some View {
        Form {
            Section {
                LabeledContent("Name") {
                    TextField("Name", text: $name)
                        .multilineTextAlignment(.trailing)
                        .submitLabel(.done)
                        .onSubmit { store.user.name = name }
                }
            }
            Section {
                LabeledContent("Current weight", value: "\(store.user.weightLb) lb")
                LabeledContent("Height", value: formatHeight(inches: store.user.heightIn))
                LabeledContent("Date of birth", value: store.user.dob)
                LabeledContent("Gender", value: store.user.sex.capitalized)
                LabeledContent("Objective", value: store.user.objective.capitalized)
                LabeledContent("Units", value: store.user.unitSystem.capitalized)
            }
        }
        .monospacedDigit()
        .sageListStyle()
        .navigationTitle("Personal Details")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { name = store.user.name }
        .onDisappear { store.user.name = name }
    }

    private func formatHeight(inches: Int) -> String {
        let ft = inches / 12, inch = inches % 12
        return "\(ft)'\(inch)\""
    }
}

// MARK: - Preferences

struct PreferencesView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        Form {
            Section {
                // Label hidden: the section header already says "Appearance",
                // and an inline picker would otherwise repeat it as a row.
                Picker("Appearance", selection: appearance) {
                    Label("System", systemImage: "circle.lefthalf.filled").tag("system")
                    Label("Light", systemImage: "sun.max").tag("light")
                    Label("Dark", systemImage: "moon.fill").tag("dark")
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Appearance")
            } footer: {
                Text("Choose light, dark, or system appearance.")
            }

            Section {
                toggle("Badge celebrations",
                       "Show a full-screen badge animation when you unlock a new badge",
                       \.badgeCelebrations)
                toggle("Live activity",
                       "Show your daily scans and warnings on your lock screen and dynamic island",
                       \.liveActivity)
                toggle("Auto-flag restrictions",
                       "Always show a warning banner when a scan contains an ingredient you've restricted",
                       \.autoFlagRestrictions)
                toggle("Save scans to history",
                       "Keep every product you scan in your history feed automatically",
                       \.saveScansToHistory)
                toggle("Personalize scoring",
                       "Use your profile to compute Your Score in addition to the Overall score",
                       \.personalizeScoring)
            }
        }
        .sageListStyle()
        .navigationTitle("Preferences")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var appearance: Binding<String> {
        Binding(get: { store.user.appearance }, set: { store.user.appearance = $0 })
    }

    /// A native `Toggle` with a description — the standard iOS settings row.
    private func toggle(_ title: String, _ desc: String,
                        _ keyPath: WritableKeyPath<UserProfile, Bool>) -> some View {
        Toggle(isOn: Binding(get: { store.user[keyPath: keyPath] },
                             set: { store.user[keyPath: keyPath] = $0 })) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.sageBold(15)).tracking(-0.2)
                    .foregroundColor(Theme.ink)
                Text(desc)
                    .font(.sageRegular(12))
                    .foregroundColor(Theme.inkSecondary)
                    .lineSpacing(2)
            }
        }
        .tint(store.accent)
    }
}

// MARK: - Nutrition Goals (Objective)

struct NutritionGoalsView: View {
    @EnvironmentObject var store: AppStore

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
        List {
            Section {
                ForEach(objectives) { o in
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
                                    .foregroundColor(Theme.ink)
                                Text(o.desc)
                                    .font(.sageRegular(12))
                                    .foregroundColor(Theme.inkSecondary)
                                    .lineSpacing(2)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 8)
                            // The system checkmark is how iOS shows a chosen
                            // row; a custom radio would only look foreign here.
                            if store.user.objective == o.id {
                                Image(systemName: "checkmark")
                                    .font(.sageBold(14))
                                    .foregroundStyle(store.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(store.user.objective == o.id ? .isSelected : [])
                }
            } footer: {
                Text("Pick the goal Sage should weigh against when scoring scans. You can change this anytime — your scores will recalculate.")
            }
        }
        .sageListStyle()
        .navigationTitle("Objective")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Dietary

struct DietaryView: View {
    @EnvironmentObject var store: AppStore

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
    let goals = ["Blood sugar", "Heart", "Gut health", "Pregnancy", "Young child"]
    let avoids = ["Carrageenan", "Aspartame", "Sucralose", "Seed oils", "Palm oil",
                  "Caffeine", "Artificial colors", "Added phosphates", "HFCS", "Titanium dioxide"]
    let priorities: [(String, WritableKeyPath<UserProfile, Int?>)] = [
        ("Clean ingredients", \.sliderCleanIngredients),
        ("Nutrition", \.sliderNutrition),
    ]

    var body: some View {
        List {
            chipSection("Health goals",
                        "Emphasizes the parts of Your Score that matter for each goal.",
                        items: goals, active: store.user.healthGoals ?? []) { v in
                toggleOptional(\.healthGoals, v)
            }
            chipSection("Restrictions",
                        "Hard rules. Sage flags these as warnings on every scan.",
                        items: restrictions, active: store.user.restrictions) { v in
                toggle(\.restrictions, v)
            }
            chipSection("Avoid list",
                        "Products containing any of these are capped and flagged for you.",
                        items: avoids, active: store.user.avoidList ?? []) { v in
                toggleOptional(\.avoidList, v)
            }
            chipSection("Preferences",
                        "Soft signals. Most nudge Your Score; Organic shows a label check.",
                        items: preferences, active: store.user.preferences) { v in
                toggle(\.preferences, v)
            }

            Section {
                ForEach(priorities, id: \.0) { label, kp in
                    priorityPicker(label: label, keyPath: kp)
                }
            } header: {
                Text("Priorities")
            } footer: {
                Text("What Your Score should weigh most.")
            }

            allergensSection
        }
        .sageListStyle()
        .navigationTitle("Personalize")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func chipSection(_ title: String, _ desc: String, items: [String],
                             active: [String],
                             tap: @escaping (String) -> Void) -> some View {
        Section {
            chipFlow(items: items, active: active, tap: tap)
                .padding(.vertical, 4)
        } header: {
            Text(title)
        } footer: {
            Text(desc)
        }
    }

    private func chipFlow(items: [String], active: [String],
                          tap: @escaping (String) -> Void) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { item in
                ChipView(label: item, active: active.contains(item),
                         accent: store.accent) {
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

    private func toggleOptional(_ keyPath: WritableKeyPath<UserProfile, [String]?>, _ value: String) {
        var arr = store.user[keyPath: keyPath] ?? []
        if let i = arr.firstIndex(of: value) { arr.remove(at: i) } else { arr.append(value) }
        store.user[keyPath: keyPath] = arr.isEmpty ? nil : arr
    }

    /// Low · Balanced · High, as the segmented control iOS already ships.
    private func priorityPicker(label: String,
                                keyPath: WritableKeyPath<UserProfile, Int?>) -> some View {
        let binding = Binding<Int>(
            get: { store.user[keyPath: keyPath] ?? 1 },
            set: { store.user[keyPath: keyPath] = ($0 == 1) ? nil : $0 }
        )
        return Picker(label, selection: binding) {
            Text("Low").tag(0)
            Text("Balanced").tag(1)
            Text("High").tag(2)
        }
        .pickerStyle(.segmented)
    }

    // MARK: Allergens

    private var allergies: [String] { store.user.allergies ?? [] }

    private var customAllergies: [String] {
        let presets = Set(AllergenCatalog.labels.map { $0.lowercased() })
        return allergies.filter { !presets.contains($0.lowercased()) }
    }

    private var allergensSection: some View {
        Section {
            chipFlow(items: AllergenCatalog.labels, active: allergies) { v in
                toggleAllergen(v)
            }
            .padding(.vertical, 4)

            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .foregroundColor(Theme.inkSecondary)
                TextField("Add another allergy", text: $customAllergy)
                    .focused($allergyFocused)
                    .font(.sageMedium(14))
                    .submitLabel(.done)
                    .onSubmit { addCustomAllergy() }
                if !customAllergy.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button("Add", action: addCustomAllergy)
                        .font(.sageBold(13))
                        .foregroundColor(store.accent)
                }
            }

            // Custom entries are the only removable ones, so they get the
            // system's own swipe-to-delete rather than an x on a chip.
            ForEach(customAllergies, id: \.self) { a in
                Text(a.capitalized)
                    .font(.sageMedium(14))
                    .swipeActions {
                        Button("Remove", role: .destructive) { removeAllergy(a) }
                    }
            }
        } header: {
            Text("Allergens")
        } footer: {
            Text("We'll flag scans that may contain these. Data can be incomplete — always check the packaging.")
        }
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
