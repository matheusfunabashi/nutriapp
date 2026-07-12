import Testing
import Foundation
@testable import Sage

struct AdditiveDetectorTests {

    private let cocaColaZeroBRIngredients =
        "CONTÉM FENILALANINA Água Gaseificada, Extrato de Noz de Cola, " +
        "Cafeína, Aroma Natural, Corante Caramelo IV, Acidulante Ácido Fosfórico, " +
        "Edulcorantes Ciclamato de Sódio (27 mg), Acesulfame de Potássio (15 mg) e " +
        "Aspartame (12 mg) por 100 ml, CONSERVADOR BENZOATO DE SODIO, " +
        "REGULADOR DE ACIDEZ CITRATO DE SODIO."

    @Test func cocaColaZeroBRRecoversLocalLanguageAdditives() {
        let result = AdditiveDetector.scan(
            ingredientsText: cocaColaZeroBRIngredients,
            offAdditiveTags: ["en:e951"],
            hasUnrecognizedIngredients: true
        )

        let codes = Set(result.additives.map(\.eNumber))
        // Detector recovers local-language names OFF missed (was 1 tag: E951).
        for code in ["E951", "E150d", "E952", "E950", "E211", "E331", "E338"] {
            #expect(codes.contains(code), "missing \(code); got \(codes.sorted())")
        }
        #expect(codes.count >= 7)
        #expect(result.undercountSuspected == true)
        #expect(result.ingredientTextMissing == false)
    }

    /// Acacia honey lists "acacia" as the floral source, not gum arabic (E414).
    /// Bare "acacia" must never match — only gum/goma/gomma/gomme phrases do.
    @Test func acaciaHoneyDoesNotFalsePositiveE414() {
        let honeys = [
            "Miel d'Acacia",
            "Miele di Acacia",
            "Mel de Acácia",
        ]
        for ingredients in honeys {
            let result = AdditiveDetector.scan(
                ingredientsText: ingredients,
                offAdditiveTags: [],
                hasUnrecognizedIngredients: false
            )
            #expect(result.additives.isEmpty,
                    "E414 false positive for honey ingredients: \(ingredients)")
        }
    }
}
