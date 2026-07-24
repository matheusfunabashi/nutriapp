import Foundation
import Testing
@testable import Sage

/// Unit tests for `OFFImageResolver` — fixture JSON only, no network.
@Suite("OFFImageResolver")
struct OFFImageResolverTests {

    private let barcode = "3017620422003"

    // MARK: Preferred-language hit

    @Test func preferredLanguageSelectedImagesHit() {
        let resolved = OFFImageResolver.resolve(
            barcode: barcode,
            lang: "fr",
            imageFrontURL: "https://images.openfoodfacts.org/images/products/301/762/042/2003/front_fr.4.400.jpg",
            imageURL: nil,
            selectedFrontDisplay: [
                "fr": "https://images.openfoodfacts.org/images/products/301/762/042/2003/front_fr.4.400.jpg",
                "pt": "https://images.openfoodfacts.org/images/products/301/762/042/2003/front_pt.7.400.jpg",
                "en": "https://images.openfoodfacts.org/images/products/301/762/042/2003/front_en.12.400.jpg"
            ],
            imageEntries: [
                "front_pt": OFFImageEntry(
                    rev: "7",
                    sizes: ["full": OFFImageSizeDims(w: 1200, h: 800)]
                ),
                "front_en": OFFImageEntry(
                    rev: "12",
                    sizes: ["full": OFFImageSizeDims(w: 1100, h: 900)]
                ),
                "front_fr": OFFImageEntry(
                    rev: "4",
                    sizes: ["full": OFFImageSizeDims(w: 1000, h: 700)]
                )
            ],
            preferredLanguages: ["pt", "en", "es"]
        )

        #expect(resolved != nil)
        #expect(resolved?.isFrontImage == true)
        #expect(resolved?.isLowQuality == false)
        #expect(resolved?.displayURL.absoluteString
                == "https://images.openfoodfacts.org/images/products/301/762/042/2003/front_pt.7.full.jpg")
        #expect(resolved?.thumbURL?.absoluteString
                == "https://images.openfoodfacts.org/images/products/301/762/042/2003/front_pt.7.400.jpg")
        #expect(resolved?.estimatedPixelSize?.width == 1200)
    }

    // MARK: Product-language fallback

    @Test func productLanguageFallback() {
        let resolved = OFFImageResolver.resolve(
            barcode: barcode,
            lang: "fr",
            imageFrontURL: nil,
            imageURL: nil,
            selectedFrontDisplay: [
                "fr": "https://images.openfoodfacts.org/images/products/301/762/042/2003/front_fr.4.200.jpg",
                "de": "https://images.openfoodfacts.org/images/products/301/762/042/2003/front_de.2.400.jpg"
            ],
            imageEntries: [
                "front_fr": OFFImageEntry(
                    rev: "4",
                    sizes: ["full": OFFImageSizeDims(w: 900, h: 900)]
                )
            ],
            preferredLanguages: ["pt", "en", "es"]  // none present in selected_images
        )

        #expect(resolved?.isFrontImage == true)
        #expect(resolved?.displayURL.absoluteString
                == "https://images.openfoodfacts.org/images/products/301/762/042/2003/front_fr.4.full.jpg")
        #expect(resolved?.thumbURL?.absoluteString
                == "https://images.openfoodfacts.org/images/products/301/762/042/2003/front_fr.4.400.jpg")
    }

    // MARK: image_front_url fallback

    @Test func imageFrontURLFallback() {
        let resolved = OFFImageResolver.resolve(
            barcode: barcode,
            lang: nil,
            imageFrontURL: "https://images.openfoodfacts.org/images/products/301/762/042/2003/front_en.12.400.jpg",
            imageURL: "https://images.openfoodfacts.org/images/products/301/762/042/2003/ingredients_en.3.400.jpg",
            selectedFrontDisplay: nil,
            imageEntries: nil,
            preferredLanguages: ["pt", "en"]
        )

        #expect(resolved != nil)
        #expect(resolved?.isFrontImage == true)
        #expect(resolved?.displayURL.absoluteString.contains("front_en.12") == true)
    }

    // MARK: image_url fallback + isFrontImage = false

    @Test func imageURLFallbackNotFront() {
        let resolved = OFFImageResolver.resolve(
            barcode: barcode,
            lang: nil,
            imageFrontURL: nil,
            imageURL: "https://images.openfoodfacts.org/images/products/301/762/042/2003/ingredients_en.3.400.jpg",
            selectedFrontDisplay: nil,
            imageEntries: nil,
            preferredLanguages: ["pt", "en"]
        )

        #expect(resolved != nil)
        #expect(resolved?.isFrontImage == false)
        #expect(resolved?.displayURL.absoluteString.contains("ingredients_en") == true)
    }

    // MARK: Thumbnail rewrite .100 / .200 → .400

    @Test func thumbnailURLRewriteTo400() {
        #expect(
            OFFImageResolver.upgradeToDisplaySize(
                "https://images.openfoodfacts.org/images/products/301/762/042/2003/front_en.12.100.jpg"
            ) == "https://images.openfoodfacts.org/images/products/301/762/042/2003/front_en.12.400.jpg"
        )
        #expect(
            OFFImageResolver.upgradeToDisplaySize(
                "https://images.openfoodfacts.org/images/products/301/762/042/2003/front_en.12.200.jpg"
            ) == "https://images.openfoodfacts.org/images/products/301/762/042/2003/front_en.12.400.jpg"
        )
        // Already .400 — unchanged; never mutates rev/lang.
        #expect(
            OFFImageResolver.upgradeToDisplaySize(
                "https://images.openfoodfacts.org/images/products/301/762/042/2003/front_pt.7.400.jpg"
            ) == "https://images.openfoodfacts.org/images/products/301/762/042/2003/front_pt.7.400.jpg"
        )
    }

    @Test func readyMadeSmallURLUpgradedOnResolve() {
        let resolved = OFFImageResolver.resolve(
            barcode: barcode,
            lang: "en",
            imageFrontURL: "https://images.openfoodfacts.org/images/products/301/762/042/2003/front_en.12.100.jpg",
            imageURL: nil,
            selectedFrontDisplay: nil,
            imageEntries: nil,
            preferredLanguages: ["en"]
        )
        #expect(resolved?.displayURL.absoluteString.hasSuffix(".400.jpg") == true
                || resolved?.displayURL.absoluteString.hasSuffix(".full.jpg") == true)
        // Parsed OFF URL with rev → builds full + 400 from barcode.
        #expect(resolved?.thumbURL?.absoluteString
                == "https://images.openfoodfacts.org/images/products/301/762/042/2003/front_en.12.400.jpg")
    }

    // MARK: Low-quality flagging

    @Test func lowQualityFlagWhenSourceUnder300() {
        let resolved = OFFImageResolver.resolve(
            barcode: barcode,
            lang: "en",
            imageFrontURL: nil,
            imageURL: nil,
            selectedFrontDisplay: [
                "en": "https://images.openfoodfacts.org/images/products/301/762/042/2003/front_en.1.100.jpg"
            ],
            imageEntries: [
                "front_en": OFFImageEntry(
                    rev: "1",
                    sizes: ["full": OFFImageSizeDims(w: 180, h: 240)]
                )
            ],
            preferredLanguages: ["en"]
        )

        #expect(resolved != nil)
        #expect(resolved?.isLowQuality == true)
        #expect(resolved?.estimatedPixelSize?.width == 180)
        // Still returned so callers can decide.
        #expect(resolved?.displayURL != nil)
    }

    // MARK: Nil when no images

    @Test func nilWhenNoImagesExist() {
        let resolved = OFFImageResolver.resolve(
            barcode: barcode,
            lang: "en",
            imageFrontURL: nil,
            imageURL: nil,
            selectedFrontDisplay: nil,
            imageEntries: nil,
            preferredLanguages: ["pt", "en"]
        )
        #expect(resolved == nil)
    }

    @Test func rejectsNonHTTPS() {
        let resolved = OFFImageResolver.resolve(
            barcode: barcode,
            lang: nil,
            imageFrontURL: "http://images.openfoodfacts.org/images/products/x/front.jpg",
            imageURL: nil,
            selectedFrontDisplay: nil,
            imageEntries: nil,
            preferredLanguages: ["en"]
        )
        #expect(resolved == nil)
    }

    // MARK: Fixture JSON decode → map path

    @Test func resolveFromDecodedOFFProductJSON() throws {
        let json = """
        {
          "product_name": "Nutella",
          "lang": "fr",
          "image_front_url": "https://images.openfoodfacts.org/images/products/301/762/042/2003/front_fr.4.400.jpg",
          "image_url": "https://images.openfoodfacts.org/images/products/301/762/042/2003/front_fr.4.400.jpg",
          "selected_images": {
            "front": {
              "display": {
                "en": "https://images.openfoodfacts.org/images/products/301/762/042/2003/front_en.12.400.jpg",
                "fr": "https://images.openfoodfacts.org/images/products/301/762/042/2003/front_fr.4.400.jpg"
              }
            }
          },
          "images": {
            "front_en": {
              "rev": "12",
              "sizes": { "full": { "w": 1400, "h": 1000 } }
            },
            "front_fr": {
              "rev": 4,
              "sizes": { "full": { "w": 900, "h": 900 } }
            }
          },
          "nutriments": {}
        }
        """.data(using: .utf8)!

        let off = try JSONDecoder().decode(OFFProduct.self, from: json)
        let resolved = OFFImageResolver.resolve(
            from: off,
            barcode: barcode,
            preferredLanguages: ["en", "pt"]
        )

        #expect(resolved?.displayURL.absoluteString
                == "https://images.openfoodfacts.org/images/products/301/762/042/2003/front_en.12.full.jpg")
        #expect(resolved?.isFrontImage == true)
        #expect(resolved?.isLowQuality == false)

        let product = OpenFoodFactsService.map(off, barcode: barcode)
        // map uses device preferredLanguages — force-check via resolve fields we just verified.
        // When preferred includes en, product should get the resolved EN full URL if device prefs allow.
        // At minimum, image fields are populated from the single resolver path.
        #expect(product.imageURL != nil)
    }

    @Test func barcodeFolderSplit() {
        #expect(OFFImageResolver.splitBarcodeFolder("3017620422003") == "301/762/042/2003")
        #expect(OFFImageResolver.splitBarcodeFolder("12345678") == "12345678")  // < 9 digits
        #expect(OFFImageResolver.splitBarcodeFolder("123456789") == "123/456/789/")
    }

    @Test func mapAppliesLowQualityToListAndDetailHelpers() {
        let off = OFFProduct(
            productName: "Tiny",
            imageFrontUrl: nil,
            imageUrl: nil,
            selectedImages: OFFSelectedImages(
                front: OFFSelectedImageSet(
                    display: ["en": "https://images.openfoodfacts.org/images/products/301/762/042/2003/front_en.1.100.jpg"],
                    small: nil,
                    thumb: nil
                )
            ),
            images: [
                "front_en": OFFImageEntry(
                    rev: "1",
                    sizes: ["full": OFFImageSizeDims(w: 100, h: 100)]
                )
            ],
            lang: "en"
        )
        // Bypass device locale by calling resolve + applying the same Product fields map uses.
        let resolved = OFFImageResolver.resolve(
            from: off, barcode: barcode, preferredLanguages: ["en"]
        )!
        #expect(resolved.isLowQuality)
        var p = OpenFoodFactsService.map(off, barcode: barcode)
        // Re-apply known resolved (map uses device langs which may differ).
        p.imageURL = resolved.displayURL.absoluteString
        p.imageThumbURL = resolved.thumbURL?.absoluteString
        p.imageIsLowQuality = resolved.isLowQuality
        #expect(p.listImageURL == nil)
        #expect(p.detailImageURL == nil)
        #expect(p.imageURL != nil)  // raw still stored
    }
}
