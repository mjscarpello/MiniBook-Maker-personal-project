import AppKit
import CoreGraphics
import Foundation

/// Fast shared renderer for logical book-page thumbnails.
///
/// A logical page can be a whole source PDF page or the left/right half of a
/// two-page spread. Visible cells request cached, size-bucketed renders on a
/// dedicated serial queue so Finder-style icon resizing remains responsive.
final class PDFThumbnailStore {
    private let renderQueue = DispatchQueue(
        label: "MiniBookMaker.PDFThumbnailRenderer",
        qos: .userInitiated
    )

    private let cache = NSCache<NSString, NSImage>()
    private let stateLock = NSLock()

    private var pdfDocument: CGPDFDocument?
    private var generation: Int = 0
    private var inFlight: [String: [UUID: (NSImage?) -> Void]] = [:]

    init() {
        cache.countLimit = 700
        cache.totalCostLimit = 320 * 1024 * 1024
    }

    func configure(data: Data) {
        stateLock.lock()
        generation += 1
        let currentGeneration = generation
        inFlight.removeAll()
        stateLock.unlock()

        cache.removeAllObjects()

        renderQueue.async { [weak self] in
            guard let self else { return }
            guard let provider = CGDataProvider(data: data as CFData) else {
                self.pdfDocument = nil
                return
            }

            let newDocument = CGPDFDocument(provider)

            self.stateLock.lock()
            let stillCurrent = self.generation == currentGeneration
            self.stateLock.unlock()

            if stillCurrent {
                self.pdfDocument = newDocument
            }
        }
    }

    func reset() {
        stateLock.lock()
        generation += 1
        inFlight.removeAll()
        stateLock.unlock()
        cache.removeAllObjects()

        renderQueue.async { [weak self] in
            self?.pdfDocument = nil
        }
    }

    func pixelBucket(forPointWidth pointWidth: CGFloat) -> Int {
        let desiredPixels = max(160, min(760, Int(ceil(pointWidth * 2.0))))
        let step = 80
        return Int(ceil(Double(desiredPixels) / Double(step))) * step
    }

    func requestKey(bookPage: BookPageRef, pointWidth: CGFloat) -> String {
        stateLock.lock()
        let currentGeneration = generation
        stateLock.unlock()
        return "\(currentGeneration)-\(bookPage.id)-\(pixelBucket(forPointWidth: pointWidth))"
    }

    func cachedImage(bookPage: BookPageRef, pointWidth: CGFloat) -> NSImage? {
        let key = requestKey(bookPage: bookPage, pointWidth: pointWidth)
        return cache.object(forKey: key as NSString)
    }

    /// Completion is always delivered on the main queue.
    @discardableResult
    func requestThumbnail(
        bookPage: BookPageRef,
        pointWidth: CGFloat,
        completion: @escaping (NSImage?) -> Void
    ) -> UUID? {
        let key = requestKey(bookPage: bookPage, pointWidth: pointWidth)

        if let cached = cache.object(forKey: key as NSString) {
            DispatchQueue.main.async { completion(cached) }
            return nil
        }

        let token = UUID()
        stateLock.lock()
        if inFlight[key] != nil {
            inFlight[key]?[token] = completion
            stateLock.unlock()
            return token
        }
        inFlight[key] = [token: completion]
        stateLock.unlock()

        let pixelWidth = pixelBucket(forPointWidth: pointWidth)

        renderQueue.async { [weak self] in
            guard let self else { return }

            self.stateLock.lock()
            let stillWanted = !(self.inFlight[key]?.isEmpty ?? true)
            self.stateLock.unlock()
            guard stillWanted else { return }

            let renderedImage = self.render(bookPage: bookPage, pixelWidth: pixelWidth)

            DispatchQueue.main.async {
                let image: NSImage?
                if let renderedImage {
                    image = NSImage(
                        cgImage: renderedImage,
                        size: NSSize(width: renderedImage.width, height: renderedImage.height)
                    )
                } else {
                    image = nil
                }

                if let image, let renderedImage {
                    let cost = max(1, renderedImage.bytesPerRow * renderedImage.height)
                    self.cache.setObject(image, forKey: key as NSString, cost: cost)
                }

                self.stateLock.lock()
                let callbacks = self.inFlight.removeValue(forKey: key) ?? [:]
                self.stateLock.unlock()
                callbacks.values.forEach { $0(image) }
            }
        }

        return token
    }

    func cancelRequest(key: String, token: UUID) {
        stateLock.lock()
        inFlight[key]?.removeValue(forKey: token)
        if inFlight[key]?.isEmpty == true {
            inFlight.removeValue(forKey: key)
        }
        stateLock.unlock()
    }

    private func render(bookPage: BookPageRef, pixelWidth: Int) -> CGImage? {
        guard let pdfDocument,
              bookPage.sourcePageIndex >= 0,
              bookPage.sourcePageIndex < pdfDocument.numberOfPages,
              let page = pdfDocument.page(at: bookPage.sourcePageIndex + 1) else {
            return nil
        }

        let box = page.getBoxRect(.cropBox)
        guard box.width > 0, box.height > 0 else { return nil }

        let sourceRect: CGRect
        switch bookPage.slice {
        case .whole:
            sourceRect = box
        case .left:
            sourceRect = CGRect(x: box.minX, y: box.minY, width: box.width / 2.0, height: box.height)
        case .right:
            sourceRect = CGRect(x: box.midX, y: box.minY, width: box.width / 2.0, height: box.height)
        }

        let aspect = sourceRect.height / sourceRect.width
        let pixelHeight = max(1, min(1400, Int(ceil(CGFloat(pixelWidth) * aspect))))

        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        let targetRect = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        context.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
        context.fill(targetRect)
        context.interpolationQuality = .high
        context.clip(to: targetRect)

        let scale = min(targetRect.width / sourceRect.width, targetRect.height / sourceRect.height)
        let fittedWidth = sourceRect.width * scale
        let fittedHeight = sourceRect.height * scale
        let fittedX = (targetRect.width - fittedWidth) / 2.0
        let fittedY = (targetRect.height - fittedHeight) / 2.0

        context.saveGState()
        context.translateBy(x: fittedX, y: fittedY)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -sourceRect.minX, y: -sourceRect.minY)
        context.drawPDFPage(page)
        context.restoreGState()

        return context.makeImage()
    }
}
