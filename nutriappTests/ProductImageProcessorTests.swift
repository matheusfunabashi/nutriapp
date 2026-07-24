import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import Sage

// MARK: - Fixtures

private enum ImageFixtures {
    static func opaqueRGB(width: Int = 40, height: Int = 40,
                          color: UIColor = .red) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = 1
        let size = CGSize(width: width, height: height)
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    /// Fully opaque except a translucent band — “already a cutout”.
    static func withMeaningfulAlpha(width: Int = 40, height: Int = 40) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = 1
        let size = CGSize(width: width, height: height)
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.clear.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
        }
    }
}

// MARK: - Heuristics

@Suite("ProductImageHeuristics")
struct ProductImageHeuristicsTests {

    @Test func opaqueImageHasNoMeaningfulAlpha() {
        let img = ImageFixtures.opaqueRGB()
        #expect(ProductImageHeuristics.hasMeaningfulAlpha(img) == false)
    }

    @Test func translucentImageHasMeaningfulAlpha() {
        let img = ImageFixtures.withMeaningfulAlpha()
        #expect(ProductImageHeuristics.hasMeaningfulAlpha(img) == true)
    }

    @Test func maskCoverageBounds() {
        #expect(ProductImageHeuristics.isAcceptableMaskCoverage(0.09) == false)
        #expect(ProductImageHeuristics.isAcceptableMaskCoverage(0.10) == true)
        #expect(ProductImageHeuristics.isAcceptableMaskCoverage(0.50) == true)
        #expect(ProductImageHeuristics.isAcceptableMaskCoverage(0.95) == true)
        #expect(ProductImageHeuristics.isAcceptableMaskCoverage(0.96) == false)
    }

    @Test func diagonalSliverMaskIsRejected() throws {
        let mask = try MaskFixtures.diagonalSliver(width: 64, height: 64)
        let geo = try #require(ProductImageHeuristics.maskGeometry(of: mask))
        #expect(ProductImageHeuristics.isAcceptableMaskCoverage(geo.coverage)
                || geo.solidity < ProductImageHeuristics.minMaskSolidity
                || geo.aspectRatio > ProductImageHeuristics.maxMaskAspectRatio)
        #expect(ProductImageHeuristics.isAcceptableMaskGeometry(
            aspectRatio: geo.aspectRatio, solidity: geo.solidity) == false)
    }

    @Test func solidBoxMaskPassesGeometry() throws {
        let mask = try MaskFixtures.solidBox(width: 64, height: 64,
                                             box: CGRect(x: 12, y: 10, width: 40, height: 44))
        let geo = try #require(ProductImageHeuristics.maskGeometry(of: mask))
        #expect(ProductImageHeuristics.isAcceptableMaskCoverage(geo.coverage))
        #expect(ProductImageHeuristics.isAcceptableMaskGeometry(
            aspectRatio: geo.aspectRatio, solidity: geo.solidity))
        #expect(geo.solidity >= 0.9)
        #expect(geo.aspectRatio < 2.0)
    }

    @Test func handHoldingProductOverlapRejects() throws {
        // Foreground = product box; person = hand overlapping ~40% of the box.
        let foreground = try MaskFixtures.solidBox(
            width: 64, height: 64,
            box: CGRect(x: 16, y: 8, width: 32, height: 48))
        let person = try MaskFixtures.solidBox(
            width: 64, height: 64,
            box: CGRect(x: 16, y: 36, width: 32, height: 20))
        let overlap = ProductImageHeuristics.personForegroundOverlap(
            personMask: person, foregroundMask: foreground)
        #expect(overlap > 0.20)
        #expect(ProductImageHeuristics.shouldRejectForPersonOverlap(overlap))
    }

    @Test func plainProductShotPersonOverlapPasses() throws {
        let foreground = try MaskFixtures.solidBox(
            width: 64, height: 64,
            box: CGRect(x: 12, y: 10, width: 40, height: 44))
        // No person pixels.
        let person = try MaskFixtures.solidBox(
            width: 64, height: 64,
            box: CGRect(x: 0, y: 0, width: 0, height: 0))
        let overlap = ProductImageHeuristics.personForegroundOverlap(
            personMask: person, foregroundMask: foreground)
        #expect(overlap == 0)
        #expect(ProductImageHeuristics.shouldRejectForPersonOverlap(overlap) == false)
    }
}

// MARK: - Synthetic masks

private enum MaskFixtures {
    static func diagonalSliver(width: Int, height: Int) throws -> CVPixelBuffer {
        try makeMask(width: width, height: height) { x, y in
            // One-pixel-wide diagonal — low solidity inside its bbox.
            abs(x - y) <= 1
        }
    }

    static func solidBox(width: Int, height: Int, box: CGRect) throws -> CVPixelBuffer {
        try makeMask(width: width, height: height) { x, y in
            box.contains(CGPoint(x: x, y: y))
        }
    }

    private static func makeMask(width: Int, height: Int,
                                 on: (_ x: Int, _ y: Int) -> Bool) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_OneComponent8,
            [kCVPixelBufferCGImageCompatibilityKey: true,
             kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary,
            &buffer
        )
        guard status == kCVReturnSuccess, let buffer else {
            throw NSError(domain: "MaskFixtures", code: Int(status))
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                base[y * bytesPerRow + x] = on(x, y) ? 255 : 0
            }
        }
        return buffer
    }
}

// MARK: - Spy masker + cache hit skips Vision

private struct SpyMasker: ProductForegroundMasking {
    let coverage: Double
    let cutout: UIImage

    func liftSubject(from image: UIImage) throws -> ProductImageLiftResult? {
        ProductImageLiftResult(image: cutout, maskCoverage: coverage)
    }
}

private struct CountingMasker: ProductForegroundMasking {
    let inner: any ProductForegroundMasking
    let onCall: @Sendable () -> Void

    func liftSubject(from image: UIImage) throws -> ProductImageLiftResult? {
        onCall()
        return try inner.liftSubject(from: image)
    }
}

@Suite("ProductImageProcessor")
struct ProductImageProcessorTests {

    @Test func skipsVisionWhenImageAlreadyHasAlpha() async {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sage_cutout_test_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let cache = ProductImageDiskCache(directory: dir)
        let spyCalls = LockCounter()
        let cutout = ImageFixtures.withMeaningfulAlpha(width: 20, height: 20)
        let masker = CountingMasker(
            inner: SpyMasker(coverage: 0.4, cutout: cutout),
            onCall: { spyCalls.increment() }
        )
        let processor = ProductImageProcessor(cache: cache, masker: masker)
        let source = ImageFixtures.withMeaningfulAlpha()
        let url = URL(string: "https://example.com/alpha.png")!

        _ = await processor.process(source, url: url)
        #expect(spyCalls.value == 0)
        #expect(await processor.visionInvocationCount == 0)
    }

    @Test func cacheHitSkipsVision() async {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sage_cutout_test_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let cache = ProductImageDiskCache(directory: dir)
        let cutout = ImageFixtures.withMeaningfulAlpha(width: 24, height: 24)
        let spyCalls = LockCounter()
        let masker = CountingMasker(
            inner: SpyMasker(coverage: 0.4, cutout: cutout),
            onCall: { spyCalls.increment() }
        )
        let processor = ProductImageProcessor(cache: cache, masker: masker)
        let opaque = ImageFixtures.opaqueRGB()
        let url = URL(string: "https://example.com/pack.jpg")!

        _ = await processor.process(opaque, url: url)
        #expect(spyCalls.value == 1)
        #expect(await processor.visionInvocationCount == 1)

        await processor.resetVisionCount()
        spyCalls.reset()

        _ = await processor.process(opaque, url: url)
        #expect(spyCalls.value == 0)
        #expect(await processor.visionInvocationCount == 0)
    }

    @Test func rejectsOutOfBandCoverageWithoutUsingCutout() async {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sage_cutout_test_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Spy returns coverage that VisionForegroundMasker would reject — but Spy
        // bypasses that check. Exercise processInMemory skip via a masker that
        // returns nil for bad coverage (mirrors production guard).
        struct RejectingMasker: ProductForegroundMasking {
            func liftSubject(from image: UIImage) throws -> ProductImageLiftResult? {
                // Simulate VisionForegroundMasker's coverage guard.
                let coverage = 0.05
                guard ProductImageHeuristics.isAcceptableMaskCoverage(coverage) else {
                    return nil
                }
                return ProductImageLiftResult(image: image, maskCoverage: coverage)
            }
        }

        let cache = ProductImageDiskCache(directory: dir)
        let processor = ProductImageProcessor(cache: cache, masker: RejectingMasker())
        let opaque = ImageFixtures.opaqueRGB()
        let out = await processor.processInMemory(opaque)
        // Same dimensions — processing fell back to (possibly downscaled) original.
        #expect(out.size.width == opaque.size.width)
        #expect(await processor.visionInvocationCount == 1)
    }
}

/// Tiny mutex counter for @Sendable spy closures in concurrent tests.
private final class LockCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    var value: Int {
        lock.lock(); defer { lock.unlock() }
        return _value
    }
    func increment() {
        lock.lock(); _value += 1; lock.unlock()
    }
    func reset() {
        lock.lock(); _value = 0; lock.unlock()
    }
}

// MARK: - Backend image decode

@Suite("Backend product image")
struct BackendProductImageDecodeTests {

    @Test func lookupImageObjectOverridesOFFURLs() throws {
        let body = """
        {
          "source": "off",
          "product": {
            "product_name": "Quaker",
            "nutriments": {},
            "image_front_url": "https://images.openfoodfacts.org/x/front.jpg"
          },
          "image": {
            "url": "https://sage-backend.sage-app1710.workers.dev/images/0003000001040",
            "thumbUrl": "https://sage-backend.sage-app1710.workers.dev/images/0003000001040",
            "source": "kroger",
            "isFrontImage": true,
            "isLowQuality": false
          }
        }
        """.data(using: .utf8)!
        let p = try OpenFoodFactsService.makeProduct(from: body, barcode: "0003000001040")
        #expect(p.imageURL == "https://sage-backend.sage-app1710.workers.dev/images/0003000001040")
        #expect(p.imageSource == "kroger")
        #expect(p.imageIsLowQuality == false)
        #expect(p.shouldProcessCutout == true)
        #expect(p.listImageURL != nil)
    }

    @Test func lowQualityOFFPrefersGlyph() throws {
        let body = """
        {
          "source": "off",
          "product": {
            "product_name": "Soft shot",
            "nutriments": {},
            "image_front_url": "https://images.openfoodfacts.org/x/front.jpg"
          },
          "image": {
            "url": "https://sage-backend.sage-app1710.workers.dev/images/1",
            "thumbUrl": "https://sage-backend.sage-app1710.workers.dev/images/1",
            "source": "off",
            "isFrontImage": true,
            "isLowQuality": true
          }
        }
        """.data(using: .utf8)!
        let p = try OpenFoodFactsService.makeProduct(from: body, barcode: "1")
        #expect(p.prefersGlyphOverRemoteImage == true)
        #expect(p.listImageURL == nil)
        #expect(p.detailImageURL == nil)
        #expect(p.shouldProcessCutout == false)
    }

    @Test func relativeImagePathAbsolutized() throws {
        let body = """
        {
          "source": "off",
          "product": { "product_name": "Rel", "nutriments": {} },
          "image": {
            "url": "/images/123",
            "thumbUrl": "/images/123",
            "source": "kroger",
            "isFrontImage": true,
            "isLowQuality": false
          }
        }
        """.data(using: .utf8)!
        let p = try OpenFoodFactsService.makeProduct(from: body, barcode: "123")
        #expect(p.imageURL == "https://sage-backend.sage-app1710.workers.dev/images/123")
    }

    @Test func legacyPayloadWithoutImageStillMapsOFF() throws {
        let body = """
        {
          "source": "off",
          "product": {
            "product_name": "Pictured product",
            "nutriments": {},
            "image_front_url": "https://images.openfoodfacts.org/x/front.jpg"
          }
        }
        """.data(using: .utf8)!
        let p = try OpenFoodFactsService.makeProduct(from: body, barcode: "1")
        #expect(p.imageURL == "https://images.openfoodfacts.org/x/front.jpg")
        #expect(p.imageSource == nil)
    }
}
