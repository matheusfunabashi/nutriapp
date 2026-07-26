import Testing
@testable import Sage

@Suite("ProductNameFormatter")
struct ProductNameFormatterTests {

    private func fmt(_ name: String?, brands: String? = nil, quantity: String? = nil) -> FormattedProduct {
        ProductNameFormatter.format(productName: name, brands: brands, quantity: quantity)
    }

    // MARK: Spec table

    @Test func refrigeranteCocaColaGarrafa() {
        let f = fmt("Refrigerante Coca Cola Original Garrafa 2l", brands: "Coca-Cola")
        #expect(f.brand == "Coca-Cola")
        #expect(f.name == "Refrigerante Original")
        #expect(f.size == "Garrafa 2 L")
        #expect(f.raw == "Refrigerante Coca Cola Original Garrafa 2l")
    }

    @Test func achocolatadoNescau() {
        let f = fmt("achocolatado em pó, NESCAU", brands: "Nescau")
        #expect(f.brand == "Nescau")
        #expect(f.name == "Achocolatado em Pó")
        #expect(f.size == nil)
    }

    @Test func cocaColaZeroAcucar() {
        let f = fmt("Coca Cola Zero Açúcar", brands: "Coca-Cola")
        #expect(f.brand == "Coca-Cola")
        #expect(f.name == "Zero Açúcar")
        #expect(f.size == nil)
    }

    @Test func cremosaComSalQualy() {
        let f = fmt("Cremosa com sal", brands: "Qualy")
        #expect(f.brand == "Qualy")
        #expect(f.name == "Cremosa com Sal")
        #expect(f.size == nil)
    }

    @Test func leitePoNinhoIntegral() {
        let f = fmt("LEITE PO NINHO INTEGRAL", brands: "Ninho")
        #expect(f.brand == "Ninho")
        #expect(f.name == "Leite em Pó Integral" || f.name == "Leite Pó Integral")
        #expect(f.size == nil)
    }

    @Test func sodaLimonada350ml() {
        let f = fmt("Refrigerante Soda Limonada 350ml", brands: "Antarctica")
        #expect(f.brand == "Antarctica")
        #expect(f.name == "Refrigerante Soda Limonada")
        #expect(f.size == "350 ml")
    }

    @Test func emptyNameFallsBackToBrand() {
        let f = fmt("", brands: "Ypê")
        #expect(f.brand == "Ypê")
        #expect(f.name == "Ypê")
        #expect(f.size == nil)
    }

    @Test func granolaNoBrand() {
        let f = fmt("Granola", brands: "")
        #expect(f.brand == nil)
        #expect(f.name == "Granola")
        #expect(f.size == nil)
    }

    @Test func leiteUHTIntegral1L() {
        let f = fmt("LEITE UHT INTEGRAL 1L", brands: "Piracanjuba")
        #expect(f.brand == "Piracanjuba")
        #expect(f.name == "Leite UHT Integral")
        #expect(f.size == "1 L")
    }

    // MARK: Safety / invariants

    @Test func neverEmptyName() {
        let cases: [(String?, String?)] = [
            (nil, nil),
            ("", ""),
            ("   ", nil),
            (nil, "Coca-Cola"),
            ("", "Ypê"),
        ]
        for (name, brand) in cases {
            let f = fmt(name, brands: brand)
            #expect(!f.name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    @Test func noDoubleSpacesOrEdgePunctuation() {
        let samples = [
            ("Refrigerante Coca Cola Original Garrafa 2l", "Coca-Cola"),
            ("achocolatado em pó, NESCAU", "Nescau"),
            ("LEITE PO NINHO INTEGRAL", "Ninho"),
            ("Coca Cola Zero Açúcar", "Coca-Cola"),
        ]
        for (name, brand) in samples {
            let f = fmt(name, brands: brand)
            #expect(!f.name.contains("  "))
            #expect(f.name.first?.isPunctuation != true)
            #expect(f.name.last?.isPunctuation != true)
        }
    }

    @Test func rawPreserved() {
        let original = "achocolatado em pó, NESCAU"
        let f = fmt(original, brands: "Nescau")
        #expect(f.raw == original)
    }

    @Test func quantityFieldPreferred() {
        let f = fmt("Leite Integral", brands: "Itambé", quantity: "1L")
        #expect(f.size == "1 L")
        #expect(f.name == "Leite Integral")
    }

    @Test func brandOnlyNameDropsEyebrow() {
        // Name equals brand → keep name, brand nil (avoid empty title).
        let f = fmt("Coca-Cola", brands: "Coca-Cola")
        #expect(f.brand == nil)
        #expect(f.name == "Coca-Cola")
    }

    @Test func accessibilityJoinsParts() {
        let f = fmt("Refrigerante Coca Cola Original Garrafa 2l", brands: "Coca-Cola")
        #expect(f.accessibilityLabel.contains("Coca-Cola"))
        #expect(f.accessibilityLabel.contains("Refrigerante Original"))
        #expect(f.accessibilityLabel.contains("Garrafa 2 L"))
    }

    @Test func memoReturnsSame() {
        let a = fmt("Granola", brands: "")
        let b = fmt("Granola", brands: "")
        #expect(a == b)
    }
}
