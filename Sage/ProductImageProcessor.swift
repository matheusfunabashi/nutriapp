import CryptoKit
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Vision

// MARK: - Backend image payload

/// Top-level `/lookup` image object. Absolute URL preferred; relative `/images/…`
/// is resolved against the Worker origin.
struct BackendProductImage: Codable, Equatable, Sendable {
    let url: String?
    let thumbUrl: String?
    let source: String?
    let isFrontImage: Bool?
    let isLowQuality: Bool?
}

// MARK: - Skip / quality heuristics (pure, unit-tested)

enum ProductImageHeuristics {
    /// Alpha channel with enough translucent pixels that the image is already a cutout.
    static func hasMeaningfulAlpha(_ image: UIImage,
                                   opaqueThreshold: UInt8 = 250,
                                   minFraction: Double = 0.01) -> Bool {
        guard let cg = image.cgImage else { return false }
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return false }

        // Downsample for speed — heuristics only need a representative sample.
        let maxSide = 64
        let scale = min(1.0, Double(maxSide) / Double(max(w, h)))
        let sw = max(1, Int(Double(w) * scale))
        let sh = max(1, Int(Double(h) * scale))
        let bytesPerPixel = 4
        var data = [UInt8](repeating: 0, count: sw * sh * bytesPerPixel)
        guard let ctx = CGContext(
            data: &data,
            width: sw,
            height: sh,
            bitsPerComponent: 8,
            bytesPerRow: sw * bytesPerPixel,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: sw, height: sh))

        var translucent = 0
        let total = sw * sh
        for i in 0..<total {
            if data[i * 4 + 3] < opaqueThreshold { translucent += 1 }
        }
        return Double(translucent) / Double(total) >= minFraction
    }

    /// Mask coverage outside this band usually means failed segmentation.
    static func isAcceptableMaskCoverage(_ ratio: Double) -> Bool {
        ratio >= 0.10 && ratio <= 0.95
    }

    /// Max person∩foreground / foreground before we reject the cutout.
    static let maxPersonForegroundOverlap: Double = 0.20

    static func shouldRejectForPersonOverlap(_ overlap: Double) -> Bool {
        overlap > maxPersonForegroundOverlap
    }

    /// Fraction of foreground mask pixels that also fire on the person mask.
    static func personForegroundOverlap(
        personMask: CVPixelBuffer,
        foregroundMask: CVPixelBuffer,
        threshold: Float = 0.5
    ) -> Double {
        CVPixelBufferLockBaseAddress(personMask, .readOnly)
        CVPixelBufferLockBaseAddress(foregroundMask, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(personMask, .readOnly)
            CVPixelBufferUnlockBaseAddress(foregroundMask, .readOnly)
        }

        let w = min(CVPixelBufferGetWidth(personMask), CVPixelBufferGetWidth(foregroundMask))
        let h = min(CVPixelBufferGetHeight(personMask), CVPixelBufferGetHeight(foregroundMask))
        guard w > 0, h > 0,
              let pBase = CVPixelBufferGetBaseAddress(personMask),
              let fBase = CVPixelBufferGetBaseAddress(foregroundMask) else { return 0 }

        let pRow = CVPixelBufferGetBytesPerRow(personMask)
        let fRow = CVPixelBufferGetBytesPerRow(foregroundMask)
        let thresh8 = UInt8(threshold * 255)
        var fg = 0
        var both = 0

        // Vision person masks are typically OneComponent32Float; foreground
        // scaled masks are often the same or OneComponent8.
        let pFloat = CVPixelBufferGetPixelFormatType(personMask) == kCVPixelFormatType_OneComponent32Float
            || CVPixelBufferGetPixelFormatType(personMask) == kCVPixelFormatType_DepthFloat32
        let fFloat = CVPixelBufferGetPixelFormatType(foregroundMask) == kCVPixelFormatType_OneComponent32Float
            || CVPixelBufferGetPixelFormatType(foregroundMask) == kCVPixelFormatType_DepthFloat32

        for y in 0..<h {
            for x in 0..<w {
                let fOn: Bool
                if fFloat {
                    fOn = fBase.advanced(by: y * fRow).assumingMemoryBound(to: Float32.self)[x] >= threshold
                } else {
                    fOn = fBase.assumingMemoryBound(to: UInt8.self)[y * fRow + x] >= thresh8
                }
                guard fOn else { continue }
                fg += 1
                let pOn: Bool
                if pFloat {
                    pOn = pBase.advanced(by: y * pRow).assumingMemoryBound(to: Float32.self)[x] >= threshold
                } else {
                    pOn = pBase.assumingMemoryBound(to: UInt8.self)[y * pRow + x] >= thresh8
                }
                if pOn { both += 1 }
            }
        }
        guard fg > 0 else { return 0 }
        return Double(both) / Double(fg)
    }

    /// Products are boxes / bags / bottles — not long shards.
    static let maxMaskAspectRatio: Double = 3.5
    /// Mask area ÷ bounding-box area; below this is a sliver/squiggle.
    static let minMaskSolidity: Double = 0.35

    static func isAcceptableMaskGeometry(aspectRatio: Double, solidity: Double) -> Bool {
        aspectRatio <= maxMaskAspectRatio && solidity >= minMaskSolidity
    }

    /// Bounding-box metrics for a soft mask (coverage of full frame, aspect, solidity).
    static func maskGeometry(of mask: CVPixelBuffer,
                             threshold: Float = 0.5) -> (coverage: Double, aspectRatio: Double, solidity: Double)? {
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }

        let w = CVPixelBufferGetWidth(mask)
        let h = CVPixelBufferGetHeight(mask)
        guard w > 0, h > 0,
              let base = CVPixelBufferGetBaseAddress(mask) else { return nil }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(mask)
        let format = CVPixelBufferGetPixelFormatType(mask)
        let thresh8 = UInt8(threshold * 255)

        var minX = w, minY = h, maxX = -1, maxY = -1
        var foreground = 0

        func consider(x: Int, y: Int, on: Bool) {
            guard on else { return }
            foreground += 1
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
        }

        if format == kCVPixelFormatType_OneComponent8 {
            let ptr = base.assumingMemoryBound(to: UInt8.self)
            for y in 0..<h {
                let row = ptr.advanced(by: y * bytesPerRow)
                for x in 0..<w {
                    consider(x: x, y: y, on: row[x] >= thresh8)
                }
            }
        } else if format == kCVPixelFormatType_OneComponent32Float
                    || format == kCVPixelFormatType_DepthFloat32 {
            for y in 0..<h {
                let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float32.self)
                for x in 0..<w {
                    consider(x: x, y: y, on: row[x] >= threshold)
                }
            }
        } else {
            let ptr = base.assumingMemoryBound(to: UInt8.self)
            let bpp = max(1, bytesPerRow / max(w, 1))
            for y in 0..<h {
                for x in 0..<w {
                    consider(x: x, y: y, on: ptr[y * bytesPerRow + x * bpp] >= thresh8)
                }
            }
        }

        guard foreground > 0, maxX >= minX, maxY >= minY else { return nil }
        let boxW = maxX - minX + 1
        let boxH = maxY - minY + 1
        let shortSide = Double(min(boxW, boxH))
        let longSide = Double(max(boxW, boxH))
        let aspect = shortSide > 0 ? longSide / shortSide : Double.infinity
        let solidity = Double(foreground) / Double(boxW * boxH)
        let coverage = Double(foreground) / Double(w * h)
        return (coverage, aspect, solidity)
    }

    /// Fraction of mask pixels above the soft-mask threshold.
    static func maskCoverage(of mask: CVPixelBuffer, threshold: Float = 0.5) -> Double {
        maskGeometry(of: mask, threshold: threshold)?.coverage ?? 0
    }
}

// MARK: - Foreground masking (injectable for tests)

struct ProductImageLiftResult: Sendable {
    let image: UIImage
    let maskCoverage: Double
}

protocol ProductForegroundMasking: Sendable {
    /// Lifts the subject onto a transparent background. Returns nil when Vision
    /// produced no usable observation (caller keeps the original).
    func liftSubject(from image: UIImage) throws -> ProductImageLiftResult?
}

struct VisionForegroundMasker: ProductForegroundMasking {
    func liftSubject(from image: UIImage) throws -> ProductImageLiftResult? {
        guard #available(iOS 17.0, *) else { return nil }
        return try liftSubject_iOS17(from: image)
    }

    @available(iOS 17.0, *)
    private func liftSubject_iOS17(from image: UIImage) throws -> ProductImageLiftResult? {
        guard let cgImage = image.cgImage else { return nil }
        let ciInput = CIImage(cgImage: cgImage)
        let handler = VNImageRequestHandler(ciImage: ciInput, options: [:])
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])
        guard let observation = request.results?.first else { return nil }

        let instances = Self.largestInstanceSet(in: observation, handler: handler)
            ?? observation.allInstances
        let maskBuffer = try observation.generateScaledMaskForImage(
            forInstances: instances,
            from: handler
        )
        guard let geo = ProductImageHeuristics.maskGeometry(of: maskBuffer) else { return nil }
        guard ProductImageHeuristics.isAcceptableMaskCoverage(geo.coverage),
              ProductImageHeuristics.isAcceptableMaskGeometry(
                aspectRatio: geo.aspectRatio, solidity: geo.solidity
              ) else {
            return nil
        }

        // Person guard — only after geometry passes (expensive).
        if let personBuf = try? Self.personSegmentationMask(from: handler),
           ProductImageHeuristics.shouldRejectForPersonOverlap(
            ProductImageHeuristics.personForegroundOverlap(
                personMask: personBuf, foregroundMask: maskBuffer
            )
           ) {
            return nil
        }

        let maskCI = CIImage(cvPixelBuffer: maskBuffer)
        guard let cutout = Self.applyMask(maskCI, to: ciInput) else { return nil }
        let trimmed = Self.trimToSubject(cutout, mask: maskCI, paddingFraction: 0.08)
            ?? cutout
        let ui = Self.render(trimmed, scale: image.scale) ?? image
        return ProductImageLiftResult(image: ui, maskCoverage: geo.coverage)
    }

    @available(iOS 17.0, *)
    private static func personSegmentationMask(
        from handler: VNImageRequestHandler
    ) throws -> CVPixelBuffer? {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        try handler.perform([request])
        return request.results?.first?.pixelBuffer
    }

    /// Prefer the single largest foreground instance when Vision returns several.
    @available(iOS 17.0, *)
    private static func largestInstanceSet(
        in observation: VNInstanceMaskObservation,
        handler: VNImageRequestHandler
    ) -> IndexSet? {
        let all = observation.allInstances
        guard all.count > 1 else { return all.isEmpty ? nil : all }

        var bestIndex: Int?
        var bestArea = -1
        for idx in all {
            guard let buffer = try? observation.generateScaledMaskForImage(
                forInstances: IndexSet(integer: idx),
                from: handler
            ),
            let geo = ProductImageHeuristics.maskGeometry(of: buffer) else { continue }
            let area = Int(geo.coverage * 1_000_000) // relative; coverage∝area
            if area > bestArea {
                bestArea = area
                bestIndex = idx
            }
        }
        guard let bestIndex else { return all }
        return IndexSet(integer: bestIndex)
    }

    private static let ciContext = CIContext(options: nil)

    private static func applyMask(_ mask: CIImage, to image: CIImage) -> CIImage? {
        let filter = CIFilter.blendWithMask()
        filter.inputImage = image
        filter.backgroundImage = CIImage.empty().cropped(to: image.extent)
        filter.maskImage = mask
        return filter.outputImage?.cropped(to: image.extent)
    }

    private static func trimToSubject(_ image: CIImage,
                                      mask: CIImage,
                                      paddingFraction: CGFloat) -> CIImage? {
        let extent = image.extent.integral
        guard !extent.isEmpty,
              let maskCG = ciContext.createCGImage(mask, from: mask.extent) else {
            return nil
        }

        let w = maskCG.width, h = maskCG.height
        var data = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(
            data: &data,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        ctx.draw(maskCG, in: CGRect(x: 0, y: 0, width: w, height: h))

        var minX = w, minY = h, maxX = 0, maxY = 0
        var found = false
        for y in 0..<h {
            for x in 0..<w {
                if data[y * w + x] > 12 {
                    found = true
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }
        guard found else { return nil }

        let boxW = max(1, maxX - minX + 1)
        let boxH = max(1, maxY - minY + 1)
        let padX = Int(CGFloat(boxW) * paddingFraction)
        let padY = Int(CGFloat(boxH) * paddingFraction)
        let x0 = max(0, minX - padX)
        let y0 = max(0, minY - padY)
        let x1 = min(w - 1, maxX + padX)
        let y1 = min(h - 1, maxY + padY)

        // Vision/CI y-axis: CGImage origin is top-left; CIImage is bottom-left.
        let ciMinY = extent.minY + CGFloat(h - 1 - y1)
        let crop = CGRect(
            x: extent.minX + CGFloat(x0),
            y: ciMinY,
            width: CGFloat(x1 - x0 + 1),
            height: CGFloat(y1 - y0 + 1)
        ).integral
        guard crop.width > 1, crop.height > 1 else { return nil }
        return image.cropped(to: crop)
    }

    private static func render(_ image: CIImage, scale: CGFloat) -> UIImage? {
        guard let cg = ciContext.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cg, scale: scale, orientation: .up)
    }
}

// MARK: - Disk cache (processed PNGs, ~100 MB LRU)

actor ProductImageDiskCache {
    static let shared = ProductImageDiskCache()

    static let maxBytes = 100 * 1024 * 1024

    private let directory: URL
    private let fm = FileManager.default

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.directory = caches.appendingPathComponent("sage_product_cutouts", isDirectory: true)
        }
        try? fm.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    func load(key: String) -> UIImage? {
        let url = fileURL(for: key)
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else { return nil }
        try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return image
    }

    func store(_ image: UIImage, key: String) {
        guard let data = image.pngData() else { return }
        let url = fileURL(for: key)
        try? data.write(to: url, options: .atomic)
        enforceCap()
    }

    func contains(key: String) -> Bool {
        fm.fileExists(atPath: fileURL(for: key).path)
    }

    func fileURL(for key: String) -> URL {
        directory.appendingPathComponent(key).appendingPathExtension("png")
    }

    private func enforceCap() {
        guard let files = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        struct Entry {
            let url: URL
            let size: Int
            let modified: Date
        }

        var entries: [Entry] = []
        var total = 0
        for url in files {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = values?.fileSize ?? 0
            let modified = values?.contentModificationDate ?? .distantPast
            total += size
            entries.append(Entry(url: url, size: size, modified: modified))
        }

        guard total > Self.maxBytes else { return }
        entries.sort { $0.modified < $1.modified }
        for entry in entries {
            guard total > Self.maxBytes else { break }
            try? fm.removeItem(at: entry.url)
            total -= entry.size
        }
    }
}

// MARK: - Processor

actor ProductImageProcessor {
    static let shared = ProductImageProcessor()

    /// Bump to invalidate on-disk cutouts after algorithm changes.
    static let processorVersion = "v4"

    static let maxOutputSide: CGFloat = 600
    private static let maxConcurrent = 2

    private let cache: ProductImageDiskCache
    private let masker: any ProductForegroundMasking
    private var activeCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Test / diagnostics: increments each time the masker is invoked.
    private(set) var visionInvocationCount = 0

    init(cache: ProductImageDiskCache = .shared,
         masker: any ProductForegroundMasking = VisionForegroundMasker()) {
        self.cache = cache
        self.masker = masker
    }

    static func cacheKey(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(hex)_\(processorVersion)"
    }

    func cachedImage(for url: URL) async -> UIImage? {
        await cache.load(key: Self.cacheKey(for: url))
    }

    /// Returns a cutout when processing succeeds; otherwise the original (or a
    /// downscaled copy). Always safe to display.
    func process(_ image: UIImage, url: URL) async -> UIImage {
        let key = Self.cacheKey(for: url)
        if let hit = await cache.load(key: key) {
            return hit
        }

        await acquirePermit()
        defer { releasePermit() }

        // Re-check after waiting — another task may have filled the cache.
        if let hit = await cache.load(key: key) {
            return hit
        }

        let result = runProcessing(image)
        await cache.store(result, key: key)
        return result
    }

    /// Exposed for unit tests — no concurrency gate, no disk I/O.
    func processInMemory(_ image: UIImage) -> UIImage {
        runProcessing(image)
    }

    func resetVisionCount() {
        visionInvocationCount = 0
    }

    // MARK: Private

    private func runProcessing(_ image: UIImage) -> UIImage {
        if ProductImageHeuristics.hasMeaningfulAlpha(image) {
            return downscaleIfNeeded(image)
        }

        visionInvocationCount += 1
        do {
            if let lifted = try masker.liftSubject(from: image) {
                return downscaleIfNeeded(lifted.image)
            }
        } catch {
            // Fall through to original.
        }
        return downscaleIfNeeded(image)
    }

    private func downscaleIfNeeded(_ image: UIImage) -> UIImage {
        let pixelLongest = max(image.size.width, image.size.height) * image.scale
        guard pixelLongest > Self.maxOutputSide else { return image }
        let factor = Self.maxOutputSide / pixelLongest
        let points = CGSize(
            width: max(1, image.size.width * image.scale * factor),
            height: max(1, image.size.height * image.scale * factor)
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: points, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: points))
        }
    }

    private func acquirePermit() async {
        while activeCount >= Self.maxConcurrent {
            await withCheckedContinuation { cont in
                waiters.append(cont)
            }
        }
        activeCount += 1
    }

    private func releasePermit() {
        activeCount = max(0, activeCount - 1)
        guard !waiters.isEmpty else { return }
        let next = waiters.removeFirst()
        next.resume()
    }
}
