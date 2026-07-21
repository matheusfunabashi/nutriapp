import Foundation

// AdditiveDetector
// -----------------
// Recovers additives that Open Food Facts fails to tag because the ingredient
// text is written in Portuguese / Italian / Spanish / French (OFF's parser is
// English/EU-centric and leaves many local names as `is_in_taxonomy: 0`).
//
// Two independent recovery paths, both language-agnostic where possible:
//   1. Code extraction  — pulls "E150d" / "INS 150d" straight from the label text.
//   2. Name dictionary  — maps local additive names to their E-number.
//
// It then MERGES those with OFF's own `additives_tags` (deduplicated) and reports
// whether an undercount is likely, so the score can lower Data Confidence instead
// of silently trusting a too-low additive count.
//
// Test fixture: Coca-Cola Zero (BR, barcode 7894900700015). OFF tags only E951.
// This detector should return 5: E951, E150d, E952, E950, E211.

// MARK: - Model

enum AdditiveTier: String {
    case major        // v1 spec Tier A  (-15)
    case moderate     // v1 spec Tier B  (-8)
    case mild         // v1 spec Tier C  (-4)
    case soft         // v1 spec Tier D  (-2)
    case exempt       // never penalized
    case unclassified // detected but not tiered — treat as your default
}

enum AdditiveSource: String {
    case offTag   // came from OFF's additives_tags (authoritative)
    case code     // extracted E### / INS### from label text
    case name     // matched a local-language name in the dictionary
}

struct Additive: Hashable {
    let eNumber: String     // canonical parent, e.g. "E452"
    let tier: AdditiveTier
    let commonName: String  // for display, e.g. "Polyphosphates"
    /// Original subtype / alias codes merged into this parent (e.g. E452i, E452vi).
    var detectedAs: [String] = []
}

struct AdditiveScanResult {
    let additives: [Additive]              // merged + deduplicated, sorted
    let undercountSuspected: Bool          // OFF left ingredients unrecognized, OR we found additives OFF missed
    let ingredientTextMissing: Bool        // no text to scan — additive count is unverifiable
    let source: [String: AdditiveSource]   // eNumber -> how it was found
}

// MARK: - Detector

enum AdditiveDetector {

    /// - Parameters:
    ///   - ingredientsText: raw OFF `ingredients_text` (any language)
    ///   - offAdditiveTags: OFF `additives_tags`, e.g. ["en:e951"]
    ///   - hasUnrecognizedIngredients: true if OFF reported unparsed ingredients
    ///        (e.g. `unknown_ingredients_n > 0`, or any ingredient with `is_in_taxonomy == 0`)
    static func scan(ingredientsText: String?,
                     offAdditiveTags: [String],
                     hasUnrecognizedIngredients: Bool) -> AdditiveScanResult {

        var found: [String: (Additive, AdditiveSource)] = [:]

        // 1. OFF's own tags win when present.
        for tag in offAdditiveTags {
            let e = canonicalENumber(tag)
            guard !e.isEmpty else { continue }
            let a = definitions[e].map { Additive(eNumber: e, tier: $0.tier, commonName: $0.commonName) }
                ?? Additive(eNumber: e, tier: .unclassified, commonName: e)
            found[e] = (a, .offTag)
        }

        let rawText = ingredientsText ?? ""
        let normText = normalize(rawText)

        // 2. Codes printed on the label (E150d, INS 150d) — language-independent.
        for code in extractCodes(from: rawText) where found[code] == nil {
            let a = definitions[code].map { Additive(eNumber: code, tier: $0.tier, commonName: $0.commonName) }
                ?? Additive(eNumber: code, tier: .unclassified, commonName: code)
            found[code] = (a, .code)
        }

        // 3. Local-language names.
        for (e, def) in definitions where found[e] == nil {
            if def.normalizedSynonyms.contains(where: { normText.contains($0) }) {
                found[e] = (Additive(eNumber: e, tier: def.tier, commonName: def.commonName), .name)
            }
        }

        let weAddedBeyondOff = found.values.contains { $0.1 != .offTag }
        let textMissing = rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        let collapsed = collapseToParents(found)
        let additives = collapsed.map(\.additive).sorted { $0.eNumber < $1.eNumber }
        let sources = Dictionary(uniqueKeysWithValues: collapsed.map { ($0.additive.eNumber, $0.source) })

        return AdditiveScanResult(
            additives: additives,
            undercountSuspected: hasUnrecognizedIngredients || weAddedBeyondOff,
            ingredientTextMissing: textMissing,
            source: sources
        )
    }

    // MARK: Parent / subtype collapse

    /// Strip roman-numeral subtype suffixes only: E452i / E452vi / E322ii → E452 / E322.
    /// Letter subtypes that identify distinct EU additives (E150d, E472e) are kept intact.
    static func parentENumber(_ raw: String) -> String {
        let e = canonicalENumber(raw.hasPrefix("E") || raw.hasPrefix("e") || raw.contains(":")
                                 ? raw
                                 : "E" + raw)
        guard !e.isEmpty else { return raw.uppercased() }
        let body = String(e.dropFirst()) // digits + optional suffix
        // Match digits then a roman-numeral run (i, ii, iii, iv, vi, …).
        guard let rx = try? NSRegularExpression(pattern: #"^(\d{3,4})([ivx]+)$"#,
                                                options: [.caseInsensitive]) else {
            return e
        }
        let ns = body as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let m = rx.firstMatch(in: body, range: range), m.numberOfRanges >= 2 else {
            // Preserve forms like E150d / E472e (latin letter, not roman).
            return "E" + body
        }
        let digits = ns.substring(with: m.range(at: 1))
        return "E" + digits
    }

    private struct Collapsed {
        var additive: Additive
        var source: AdditiveSource
    }

    private static func collapseToParents(
        _ found: [String: (Additive, AdditiveSource)]
    ) -> [Collapsed] {
        var byParent: [String: Collapsed] = [:]
        for (code, (additive, source)) in found {
            let parent = parentENumber(code)
            let resolved = resolveDefinition(parent: parent, original: code, fallback: additive)
            if var existing = byParent[parent] {
                if code.uppercased() != parent.uppercased(),
                   !existing.additive.detectedAs.contains(where: { $0.caseInsensitiveCompare(code) == .orderedSame }) {
                    existing.additive.detectedAs.append(canonicalDisplayCode(code))
                }
                // Prefer a classified tier over unclassified when merging.
                if existing.additive.tier == .unclassified, resolved.tier != .unclassified {
                    existing.additive = Additive(
                        eNumber: parent,
                        tier: resolved.tier,
                        commonName: resolved.commonName,
                        detectedAs: existing.additive.detectedAs
                    )
                }
                // Prefer OFF tag provenance when present.
                if source == .offTag { existing.source = .offTag }
                byParent[parent] = existing
            } else {
                var detectedAs: [String] = []
                if code.uppercased() != parent.uppercased() {
                    detectedAs = [canonicalDisplayCode(code)]
                }
                byParent[parent] = Collapsed(
                    additive: Additive(eNumber: parent, tier: resolved.tier,
                                       commonName: resolved.commonName,
                                       detectedAs: detectedAs),
                    source: source
                )
            }
        }
        return Array(byParent.values)
    }

    private static func resolveDefinition(parent: String, original: String,
                                          fallback: Additive) -> (tier: AdditiveTier, commonName: String) {
        if let def = definitions[parent] {
            return (def.tier, def.commonName)
        }
        if let def = definitions[original] {
            return (def.tier, def.commonName)
        }
        // Knowledge-base tier wins when the detector dictionary has no entry.
        if let kb = AdditiveKnowledgeBase.entry(for: parent) {
            return (tierFromRisk(kb.risk), kb.name.resolved())
        }
        return (fallback.tier, fallback.commonName == original ? parent : fallback.commonName)
    }

    private static func tierFromRisk(_ risk: RiskLevel) -> AdditiveTier {
        switch risk {
        case .high: return .major
        case .moderate: return .moderate
        case .low: return .mild
        case .unrated: return .unclassified
        }
    }

    private static func canonicalDisplayCode(_ code: String) -> String {
        let c = canonicalENumber(code)
        return c.isEmpty ? code.uppercased() : c
    }

    // MARK: Code extraction

    /// Pulls "E150d", "E 150", "E-150d", "E452i", "INS 150d", "INS:951" out of raw text.
    /// Returns canonical E-numbers (letter or roman suffix preserved for later parent collapse).
    static func extractCodes(from text: String) -> Set<String> {
        var out = Set<String>()
        let patterns = [
            #"(?i)\bE[\s\-]?(\d{3,4}(?:[ivx]+|[a-f])?)\b"#,
            #"(?i)\bINS[\s:]{0,2}(\d{3,4}(?:[ivx]+|[a-z])?)\b"#
        ]
        let ns = text as NSString
        for p in patterns {
            guard let rx = try? NSRegularExpression(pattern: p) else { continue }
            for m in rx.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let num = ns.substring(with: m.range(at: 1)).lowercased()
                out.insert("E" + num)
            }
        }
        return out
    }

    // MARK: Normalization

    /// Lowercase, strip diacritics (á→a, é→e, ç→c), normalize separators.
    /// Makes "Ácido Fosfórico" == "acido fosforico" and "édulcorant" == "edulcorant".
    static func normalize(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US"))
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
    }

    /// "en:e951" / "e951" / "E951" -> "E951"
    static func canonicalENumber(_ tag: String) -> String {
        let t = tag.replacingOccurrences(of: "en:", with: "").lowercased()
        guard t.first == "e" else { return "" }
        return "E" + t.dropFirst()
    }
}

// MARK: - Dictionary

private struct AdditiveDef {
    let tier: AdditiveTier
    let commonName: String
    let synonyms: [String]
    var normalizedSynonyms: [String] { synonyms.map(AdditiveDetector.normalize) }
}

// High-impact additives across PT / IT / ES / FR / EN (US + UK).
// Cognates (identical across languages, e.g. "aspartame") are listed once.
// Tiers mirror the v1 spec where specified — adjust to match your AdditiveTier table.
// The DETECTION is the point; tiers are only so results plug straight into scoring.
private let definitions: [String: AdditiveDef] = [

    // ---- Sweeteners ----
    "E950": .init(tier: .mild, commonName: "Acesulfame-K",
        synonyms: ["acesulfame", "acesulfame k", "acesulfame-k", "acesulfame de potassio",
                   "acesulfame di potassio", "acesulfamo de potasio", "acesulfame de potassium",
                   "acesulfame potassium", "acesulfamo"]),
    "E951": .init(tier: .moderate, commonName: "Aspartame",
        synonyms: ["aspartame", "aspartamo", "aspartame acesulfame"]),
    "E952": .init(tier: .moderate, commonName: "Cyclamate",
        synonyms: ["ciclamato", "ciclamato de sodio", "ciclamato di sodio", "cyclamate",
                   "cyclamate de sodium", "sodium cyclamate", "acido ciclamico"]),
    "E954": .init(tier: .moderate, commonName: "Saccharin",
        synonyms: ["sacarina", "saccarina", "saccharine", "saccharin", "sacarina sodica"]),
    "E955": .init(tier: .mild, commonName: "Sucralose",
        synonyms: ["sucralose", "sucralosa"]),
    "E960": .init(tier: .exempt, commonName: "Steviol glycosides",
        synonyms: ["steviol", "glicosideos de esteviol", "glucosidos de esteviol",
                   "glicosidi steviolici", "glycosides de steviol", "steviol glycosides"]),
    "E961": .init(tier: .moderate, commonName: "Neotame", synonyms: ["neotame"]),
    "E965": .init(tier: .mild, commonName: "Maltitol", synonyms: ["maltitol", "maltitolo"]),
    "E967": .init(tier: .soft, commonName: "Xylitol", synonyms: ["xilitol", "xylitol", "xilitolo"]),
    "E968": .init(tier: .exempt, commonName: "Erythritol",
        synonyms: ["eritritol", "eritritolo", "erythritol", "erythritol"]),
    "E420": .init(tier: .soft, commonName: "Sorbitol", synonyms: ["sorbitol", "sorbitolo"]),

    // ---- Colours ----
    "E100": .init(tier: .exempt, commonName: "Curcumin",
        synonyms: ["curcumina", "curcumin", "curcuma"]),
    "E101": .init(tier: .exempt, commonName: "Riboflavin",
        synonyms: ["riboflavina", "riboflavin"]),
    "E102": .init(tier: .moderate, commonName: "Tartrazine",
        synonyms: ["tartrazina", "tartrazine", "amarelo tartrazina", "giallo tartrazina"]),
    "E104": .init(tier: .moderate, commonName: "Quinoline yellow",
        synonyms: ["amarelo de quinoleina", "giallo di chinolina", "amarillo de quinoleina",
                   "jaune de quinoleine", "quinoline yellow"]),
    "E110": .init(tier: .moderate, commonName: "Sunset yellow",
        synonyms: ["amarelo crepusculo", "giallo tramonto", "amarillo ocaso",
                   "jaune orange s", "sunset yellow"]),
    "E120": .init(tier: .mild, commonName: "Cochineal / carmine",
        synonyms: ["cochonilha", "carmim", "carminio", "cochinilla", "carmin",
                   "cochineal", "carmine"]),
    "E122": .init(tier: .moderate, commonName: "Azorubine / carmoisine",
        synonyms: ["azorrubina", "azorubina", "carmoisina", "carmoisine", "azorubine"]),
    "E124": .init(tier: .moderate, commonName: "Ponceau 4R",
        synonyms: ["ponceau 4r", "vermelho ponceau", "rosso ponceau", "rojo ponceau", "ponceau"]),
    "E127": .init(tier: .major, commonName: "Erythrosine",
        synonyms: ["eritrosina", "erythrosine", "red 3", "vermelho eritrosina"]),
    "E129": .init(tier: .moderate, commonName: "Allura red",
        synonyms: ["vermelho allura", "rosso allura", "rojo allura", "rouge allura",
                   "allura red", "red 40"]),
    "E133": .init(tier: .moderate, commonName: "Brilliant blue",
        synonyms: ["azul brilhante", "blu brillante", "azul brillante", "bleu brillant",
                   "brilliant blue", "blue 1"]),
    "E150c": .init(tier: .moderate, commonName: "Caramel colour III",
        synonyms: ["corante caramelo iii", "colorante caramello iii", "colorante caramelo iii",
                   "colorant caramel iii", "caramel colour iii", "caramel color iii", "caramelo iii"]),
    "E150d": .init(tier: .moderate, commonName: "Caramel colour IV",
        synonyms: ["corante caramelo iv", "colorante caramello iv", "colorante caramelo iv",
                   "colorant caramel iv", "caramel colour iv", "caramel color iv", "caramelo iv",
                   "caramelo amoniacal sulfitico", "caramelo iv sulfito de amonia"]),
    "E160b": .init(tier: .mild, commonName: "Annatto",
        synonyms: ["urucum", "annatto", "achiote", "rocou"]),
    "E171": .init(tier: .major, commonName: "Titanium dioxide",
        synonyms: ["dioxido de titanio", "biossido di titanio", "dioxyde de titane",
                   "titanium dioxide"]),

    // ---- Preservatives ----
    "E200": .init(tier: .mild, commonName: "Sorbic acid",
        synonyms: ["acido sorbico", "sorbic acid"]),
    "E202": .init(tier: .mild, commonName: "Potassium sorbate",
        synonyms: ["sorbato de potassio", "sorbato di potassio", "sorbato de potasio",
                   "sorbate de potassium", "potassium sorbate"]),
    "E210": .init(tier: .mild, commonName: "Benzoic acid",
        synonyms: ["acido benzoico", "benzoic acid"]),
    "E211": .init(tier: .mild, commonName: "Sodium benzoate",
        synonyms: ["benzoato de sodio", "benzoato di sodio", "benzoate de sodium",
                   "sodium benzoate", "conservador benzoato de sodio", "conservante benzoato di sodio"]),
    "E220": .init(tier: .mild, commonName: "Sulphur dioxide",
        synonyms: ["dioxido de enxofre", "anidride solforosa", "dioxido de azufre",
                   "dioxyde de soufre", "sulphur dioxide", "sulfur dioxide"]),
    "E223": .init(tier: .mild, commonName: "Sodium metabisulphite",
        synonyms: ["metabissulfito de sodio", "metabisolfito di sodio", "metabisulfito de sodio",
                   "metabisulfite de sodium", "sodium metabisulphite", "sodium metabisulfite"]),
    "E249": .init(tier: .major, commonName: "Potassium nitrite",
        synonyms: ["nitrito de potassio", "nitrito di potassio", "nitrito de potasio",
                   "nitrite de potassium", "potassium nitrite"]),
    "E250": .init(tier: .major, commonName: "Sodium nitrite",
        synonyms: ["nitrito de sodio", "nitrito di sodio", "nitrite de sodium", "sodium nitrite"]),
    "E251": .init(tier: .major, commonName: "Sodium nitrate",
        synonyms: ["nitrato de sodio", "nitrato di sodio", "nitrate de sodium", "sodium nitrate"]),
    "E252": .init(tier: .major, commonName: "Potassium nitrate",
        synonyms: ["nitrato de potassio", "nitrato di potassio", "nitrato de potasio",
                   "nitrate de potassium", "potassium nitrate"]),
    "E281": .init(tier: .mild, commonName: "Sodium propionate",
        synonyms: ["propionato de sodio", "propionato di sodio", "propionate de sodium",
                   "sodium propionate"]),
    "E319": .init(tier: .major, commonName: "TBHQ",
        synonyms: ["tbhq", "terc butil hidroquinona", "butilidrochinone", "butylhydroquinone"]),
    "E320": .init(tier: .major, commonName: "BHA",
        synonyms: ["bha", "butil hidroxianisol", "butilidrossianisolo", "butylated hydroxyanisole",
                   "hydroxyanisole"]),
    "E321": .init(tier: .moderate, commonName: "BHT",
        synonyms: ["bht", "butil hidroxitolueno", "butilidrossitoluene", "butylated hydroxytoluene",
                   "hydroxytoluene"]),

    // ---- Acids & regulators ----
    "E260": .init(tier: .exempt, commonName: "Acetic acid", synonyms: ["acido acetico", "acetic acid"]),
    "E270": .init(tier: .exempt, commonName: "Lactic acid",
        synonyms: ["acido latico", "acido lactico", "acide lactique", "lactic acid"]),
    "E296": .init(tier: .exempt, commonName: "Malic acid", synonyms: ["acido malico", "malic acid"]),
    "E300": .init(tier: .exempt, commonName: "Ascorbic acid",
        synonyms: ["acido ascorbico", "ascorbic acid", "acide ascorbique"]),
    "E330": .init(tier: .exempt, commonName: "Citric acid",
        synonyms: ["acido citrico", "citric acid", "acide citrique"]),
    "E331": .init(tier: .exempt, commonName: "Sodium citrate",
        synonyms: ["citrato de sodio", "citrato di sodio", "citrate de sodium", "sodium citrate"]),
    "E334": .init(tier: .exempt, commonName: "Tartaric acid",
        synonyms: ["acido tartarico", "tartaric acid"]),
    "E338": .init(tier: .mild, commonName: "Phosphoric acid",
        synonyms: ["acido fosforico", "acide phosphorique", "phosphoric acid",
                   "acidulante acido fosforico"]),

    // ---- Emulsifiers / stabilizers / thickeners ----
    "E322": .init(tier: .exempt, commonName: "Lecithin",
        synonyms: ["lecitina", "lecithine", "lecithin"]),
    "E406": .init(tier: .exempt, commonName: "Agar", synonyms: ["agar", "agar agar"]),
    "E407": .init(tier: .moderate, commonName: "Carrageenan",
        synonyms: ["carragenina", "carragena", "carraghenina", "carragenano",
                   "carraghenane", "carrageenan", "carragheen"]),
    // Natural fibre hydrocolloids — benign, like the already-exempt agar /
    // gum arabic / pectin. (Synthetic emulsifiers below stay penalized.)
    "E410": .init(tier: .exempt, commonName: "Locust bean gum",
        synonyms: ["goma de alfarroba", "farina di semi di carrube", "goma garrofin",
                   "gomme de caroube", "locust bean gum", "carob gum"]),
    "E412": .init(tier: .exempt, commonName: "Guar gum",
        synonyms: ["goma guar", "gomma di guar", "gomme guar", "guar gum"]),
    "E414": .init(tier: .exempt, commonName: "Gum arabic",
        synonyms: ["goma arabica", "gomma arabica", "goma arabiga", "gomme arabique",
                   "gum arabic", "goma acacia", "gomma d'acacia", "goma de acacia",
                   "gomme d'acacia", "acacia gum", "gum acacia"]),
    "E415": .init(tier: .exempt, commonName: "Xanthan gum",
        synonyms: ["goma xantana", "gomma di xanthan", "gomme xanthane", "xanthan gum", "xantana"]),
    "E418": .init(tier: .exempt, commonName: "Gellan gum",
        synonyms: ["goma gelana", "gomma gellano", "gomme gellane", "gellan gum", "gelana"]),
    "E433": .init(tier: .moderate, commonName: "Polysorbate 80",
        synonyms: ["polissorbato 80", "polisorbato 80", "polysorbate 80"]),
    "E440": .init(tier: .exempt, commonName: "Pectin", synonyms: ["pectina", "pectine", "pectin"]),
    "E466": .init(tier: .mild, commonName: "Cellulose gum (CMC)",
        synonyms: ["carboximetilcelulose", "carbossimetilcellulosa", "carboximetilcelulosa",
                   "carboxymethylcellulose", "cellulose gum", "cmc"]),
    "E450": .init(tier: .moderate, commonName: "Diphosphates",
        synonyms: ["difosfato", "difosfatos", "diphosphate", "diphosphates",
                   "disodium diphosphate", "sodium acid pyrophosphate"]),
    "E451": .init(tier: .moderate, commonName: "Triphosphates",
        synonyms: ["trifosfato", "trifosfatos", "triphosphate", "triphosphates",
                   "pentasodium triphosphate"]),
    "E452": .init(tier: .moderate, commonName: "Polyphosphates",
        synonyms: ["polifosfato", "polifosfatos", "polyphosphate", "polyphosphates",
                   "sodium hexametaphosphate", "hexametafosfato", "hexametafosfato de sodio",
                   "sodium polyphosphate", "potassium polyphosphate"]),
    "E471": .init(tier: .mild, commonName: "Mono- & diglycerides",
        synonyms: ["mono e digliceridios", "mono e digliceridi", "mono y digliceridos",
                   "mono et diglycerides", "monoglycerides", "diglycerides",
                   "mono and diglycerides", "mono e diglicerideos de acidos graxos"]),

    // ---- Flavour enhancers ----
    "E621": .init(tier: .mild, commonName: "Monosodium glutamate",
        synonyms: ["glutamato monossodico", "glutammato monosodico", "glutamato monosodico",
                   "glutamate monosodique", "monosodium glutamate", "msg"]),
    "E627": .init(tier: .soft, commonName: "Disodium guanylate",
        synonyms: ["guanilato dissodico", "guanilato disodico", "disodium guanylate", "guanylate"]),
    "E631": .init(tier: .soft, commonName: "Disodium inosinate",
        synonyms: ["inosinato dissodico", "inosinato disodico", "disodium inosinate", "inosinate"]),

    // ---- Flour treatment ----
    "E924": .init(tier: .major, commonName: "Potassium bromate",
        synonyms: ["bromato de potassio", "bromato di potassio", "bromato de potasio",
                   "bromate de potassium", "potassium bromate"]),
    "E927a": .init(tier: .major, commonName: "Azodicarbonamide",
        synonyms: ["azodicarbonamida", "azodicarbonammide", "azodicarbonamide"]),

    // ---- Benign: natural colours, vitamins, minerals, leavening, inert gases ----
    // Well-established as harmless at dietary levels — exempt so they carry no
    // penalty and display as benign rather than "UNRATED". OFF-tagged products
    // match on the E-number key; synonyms cover text-only detection.
    "E140": .init(tier: .exempt, commonName: "Chlorophylls",
        synonyms: ["clorofila", "clorofilla", "chlorophylle", "chlorophyll", "chlorophylls"]),
    "E160a": .init(tier: .exempt, commonName: "Carotenes",
        synonyms: ["caroteno", "carotene", "beta caroteno", "beta-carotene", "betacarotene",
                   "carotenos", "carotenes"]),
    "E160c": .init(tier: .exempt, commonName: "Paprika extract",
        synonyms: ["extrato de paprica", "estratto di paprika", "extracto de pimenton",
                   "extrait de paprika", "paprika extract", "capsanthin"]),
    "E162": .init(tier: .exempt, commonName: "Beetroot red",
        synonyms: ["vermelho de beterraba", "rosso di barbabietola", "rojo de remolacha",
                   "rouge de betterave", "beetroot red", "betanin"]),
    "E163": .init(tier: .exempt, commonName: "Anthocyanins",
        synonyms: ["antocianinas", "antocianine", "anthocyanes", "anthocyanins", "anthocyanin"]),
    "E306": .init(tier: .exempt, commonName: "Tocopherols (Vitamin E)",
        synonyms: ["tocoferois", "tocoferolo", "tocoferoles", "tocopherols", "tocopherol",
                   "vitamin e", "vitamina e"]),
    "E307": .init(tier: .exempt, commonName: "Alpha-tocopherol",
        synonyms: ["alfa tocoferol", "alpha-tocopherol", "alpha tocopherol"]),
    "E375": .init(tier: .exempt, commonName: "Niacin (Vitamin B3)",
        synonyms: ["niacina", "niacin", "vitamina b3", "vitamin b3"]),
    "E170": .init(tier: .exempt, commonName: "Calcium carbonate",
        synonyms: ["carbonato de calcio", "carbonato di calcio", "carbonate de calcium",
                   "calcium carbonate"]),
    "E500": .init(tier: .exempt, commonName: "Sodium carbonates",
        synonyms: ["bicarbonato de sodio", "bicarbonato di sodio", "carbonato de sodio",
                   "bicarbonate de sodium", "sodium bicarbonate", "sodium carbonate", "baking soda"]),
    "E501": .init(tier: .exempt, commonName: "Potassium carbonates",
        synonyms: ["carbonato de potassio", "carbonato di potassio", "carbonate de potassium",
                   "potassium carbonate", "potassium bicarbonate"]),
    "E504": .init(tier: .exempt, commonName: "Magnesium carbonate",
        synonyms: ["carbonato de magnesio", "carbonato di magnesio", "carbonate de magnesium",
                   "magnesium carbonate"]),
    "E509": .init(tier: .exempt, commonName: "Calcium chloride",
        synonyms: ["cloreto de calcio", "cloruro di calcio", "cloruro de calcio",
                   "chlorure de calcium", "calcium chloride"]),
    "E290": .init(tier: .exempt, commonName: "Carbon dioxide",
        synonyms: ["dioxido de carbono", "anidride carbonica", "dioxyde de carbone",
                   "carbon dioxide"]),
    "E941": .init(tier: .exempt, commonName: "Nitrogen",
        synonyms: ["nitrogenio", "azoto", "nitrogeno", "azote", "nitrogen"]),
    "E948": .init(tier: .exempt, commonName: "Oxygen",
        synonyms: ["oxigenio", "ossigeno", "oxigeno", "oxygene", "oxygen"]),
]
