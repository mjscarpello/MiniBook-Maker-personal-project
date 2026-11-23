import AppKit
import CoreGraphics
import Foundation
import PDFKit

struct MiniBookLayout {
    // PDF points: 72 points = 1 inch.
    static let pointsPerInch: CGFloat = 72.0
    static let sheetRect = CGRect(x: 0, y: 0, width: 8.5 * pointsPerInch, height: 11.0 * pointsPerInch)
    static let tileWidth = sheetRect.width / 2.0
    static let tileHeight = sheetRect.height / 2.0

    // Intentionally tiny cutting marks to preserve maximum page area.
    static let cutMarkLength = 2.5 / 25.4 * pointsPerInch
    static let cutMarkLineWidth: CGFloat = 0.25
    static let cutMarkEdgeInset: CGFloat = 0.25 * pointsPerInch

    static let miniPageRect = CGRect(x: 0, y: 0, width: tileWidth, height: tileHeight)

    /// 0 = top-left, 1 = top-right, 2 = bottom-left, 3 = bottom-right.
    static func tileRect(_ position: Int) -> CGRect {
        switch position {
        case 0:
            return CGRect(x: 0, y: tileHeight, width: tileWidth, height: tileHeight)
        case 1:
            return CGRect(x: tileWidth, y: tileHeight, width: tileWidth, height: tileHeight)
        case 2:
            return CGRect(x: 0, y: 0, width: tileWidth, height: tileHeight)
        default:
            return CGRect(x: tileWidth, y: 0, width: tileWidth, height: tileHeight)
        }
    }
}

enum PDFExporter {
    static func physicalSheetCount(forBookPageCount count: Int) -> Int {
        MiniBookImposition.physicalSheetCount(forBookPageCount: count)
    }

    /// Export has exactly one source of physical ordering: a prevalidated
    /// `PhysicalSheetPlan`. There is intentionally no sequential 4-up fallback.
    static func export(
        document: PDFDocument,
        bookPages: [BookPageRef],
        bindingSettings: BindingGuideSettings,
        to url: URL,
        maximumPhysicalSheets: Int? = nil
    ) throws {
        let fullPlan = try MiniBookImposition.validatedPlan(bookPageCount: bookPages.count)
        let punchValidation = AdaptivePunchGeometry.validate(bookPageCount: bookPages.count, settings: bindingSettings)
        guard punchValidation.isValid else {
            throw MiniBookError.invalidBinding(punchValidation.message)
        }

        let requestedCount = min(fullPlan.count, maximumPhysicalSheets ?? fullPlan.count)
        let plan = Array(fullPlan.prefix(requestedCount))

        var mediaBox = MiniBookLayout.sheetRect
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw MiniBookError.couldNotCreateOutput
        }

        // Output PDF page order is ALWAYS:
        // physical sheet 1 FRONT, sheet 1 BACK, sheet 2 FRONT, sheet 2 BACK...
        for physicalSheet in plan {
            for side in [MiniBookSheetSide.front, MiniBookSheetSide.back] {
                context.beginPDFPage(nil)
                drawSheet(
                    document: document,
                    bookPages: bookPages,
                    bindingSettings: bindingSettings,
                    physicalSheet: physicalSheet,
                    side: side,
                    in: context
                )
                context.endPDFPage()
            }
        }

        context.closePDF()
    }

    static func makeSheetData(
        document: PDFDocument,
        bookPages: [BookPageRef],
        bindingSettings: BindingGuideSettings,
        sheetIndex: Int,
        side: MiniBookSheetSide
    ) -> Data? {
        guard !bookPages.isEmpty else { return nil }
        guard let plan = try? MiniBookImposition.validatedPlan(bookPageCount: bookPages.count),
              plan.indices.contains(sheetIndex) else {
            return nil
        }

        let mutableData = NSMutableData()
        guard let consumer = CGDataConsumer(data: mutableData as CFMutableData) else { return nil }
        var mediaBox = MiniBookLayout.sheetRect
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        context.beginPDFPage(nil)
        drawSheet(
            document: document,
            bookPages: bookPages,
            bindingSettings: bindingSettings,
            physicalSheet: plan[sheetIndex],
            side: side,
            in: context
        )
        context.endPDFPage()
        context.closePDF()

        return mutableData as Data
    }

    static func makeMiniPageData(
        document: PDFDocument,
        bookPage: BookPageRef,
        logicalBookIndex: Int,
        totalBookPages: Int,
        bindingSettings: BindingGuideSettings
    ) -> Data? {
        guard document.page(at: bookPage.sourcePageIndex) != nil else { return nil }

        let mutableData = NSMutableData()
        guard let consumer = CGDataConsumer(data: mutableData as CFMutableData) else { return nil }
        var mediaBox = MiniBookLayout.miniPageRect
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        context.beginPDFPage(nil)
        fillWhite(MiniBookLayout.miniPageRect, in: context)
        draw(bookPage: bookPage, from: document, into: MiniBookLayout.miniPageRect, in: context)
        drawAdaptivePunchGuides(
            logicalBookIndex: logicalBookIndex,
            totalBookPages: totalBookPages,
            bindingSettings: bindingSettings,
            targetRect: MiniBookLayout.miniPageRect,
            in: context
        )
        context.endPDFPage()
        context.closePDF()

        return mutableData as Data
    }

    /// Creates a source-independent 64-page calibration PDF that proves the
    /// eight-sheet cut-stack plan. After duplex printing and cutting all eight
    /// sheets together, piles A/B/C/D must be pages 1–16 / 17–32 / 33–48 / 49–64.
    static func exportCutStackCalibration(to url: URL) throws {
        let pageCount = 64
        let plan = try MiniBookImposition.validatedPlan(bookPageCount: pageCount)

        var mediaBox = MiniBookLayout.sheetRect
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw MiniBookError.couldNotCreateOutput
        }

        for sheet in plan {
            for side in [MiniBookSheetSide.front, MiniBookSheetSide.back] {
                context.beginPDFPage(nil)
                fillWhite(MiniBookLayout.sheetRect, in: context)
                let indices = sheet.indices(for: side)
                for position in 0..<4 {
                    let number = indices[position].map { $0 + 1 }
                    drawCalibrationTile(
                        number: number,
                        side: side,
                        position: position,
                        batchIndex: sheet.batchIndex,
                        sheetIndexInBatch: sheet.sheetIndexInBatch,
                        sheetsInBatch: sheet.sheetsInBatch,
                        in: context
                    )
                }
                drawMicroCutMarks(in: context)
                context.endPDFPage()
            }
        }

        context.closePDF()
    }

    private static func drawSheet(
        document: PDFDocument,
        bookPages: [BookPageRef],
        bindingSettings: BindingGuideSettings,
        physicalSheet: PhysicalSheetPlan,
        side: MiniBookSheetSide,
        in context: CGContext
    ) {
        fillWhite(MiniBookLayout.sheetRect, in: context)
        let physicalIndices = physicalSheet.indices(for: side)

        // No sorting happens here. The validated cut-stack plan already says
        // exactly which logical page belongs in every physical tile.
        for position in 0..<4 {
            guard let logicalIndex = physicalIndices[position],
                  bookPages.indices.contains(logicalIndex) else {
                continue
            }

            let target = MiniBookLayout.tileRect(position)
            draw(
                bookPage: bookPages[logicalIndex],
                from: document,
                into: target,
                in: context
            )
            drawAdaptivePunchGuides(
                logicalBookIndex: logicalIndex,
                totalBookPages: bookPages.count,
                bindingSettings: bindingSettings,
                targetRect: target,
                in: context
            )
        }

        drawMicroCutMarks(in: context)
    }

    /// Draws either a full source PDF page or one half of a two-page spread.
    /// Source PDF vectors/text remain vectors in the exported PDF.
    static func draw(
        bookPage: BookPageRef,
        from document: PDFDocument,
        into targetRect: CGRect,
        in context: CGContext
    ) {
        guard bookPage.sourcePageIndex >= 0,
              bookPage.sourcePageIndex < document.pageCount,
              let page = document.page(at: bookPage.sourcePageIndex) else {
            return
        }

        let sourceRect = BookPageBuilder.cropRect(for: bookPage, page: page)
        guard sourceRect.width > 0, sourceRect.height > 0 else { return }

        context.saveGState()
        defer { context.restoreGState() }

        context.clip(to: targetRect)
        context.interpolationQuality = .high

        let scale = min(targetRect.width / sourceRect.width, targetRect.height / sourceRect.height)
        let fittedWidth = sourceRect.width * scale
        let fittedHeight = sourceRect.height * scale
        let fittedX = targetRect.minX + (targetRect.width - fittedWidth) / 2.0
        let fittedY = targetRect.minY + (targetRect.height - fittedHeight) / 2.0

        context.translateBy(x: fittedX, y: fittedY)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -sourceRect.minX, y: -sourceRect.minY)
        page.draw(with: .cropBox, to: context)
    }

    private static func drawAdaptivePunchGuides(
        logicalBookIndex: Int,
        totalBookPages: Int,
        bindingSettings: BindingGuideSettings,
        targetRect: CGRect,
        in context: CGContext
    ) {
        guard bindingSettings.enabled else { return }

        let totalLeaves = MiniBookImposition.physicalLeafCount(forBookPageCount: totalBookPages)
        let leafIndex = AdaptivePunchGeometry.physicalLeafIndex(forLogicalPageIndex: logicalBookIndex)
        guard let targetYFromTop = AdaptivePunchGeometry.targetYFromTopInches(
            leafIndex: leafIndex,
            totalLeaves: totalLeaves,
            settings: bindingSettings
        ) else { return }

        let radius = CGFloat(bindingSettings.targetDiameterInches * 72.0 / 2.0)
        let inset = CGFloat(bindingSettings.bindingEdgeInsetInches * 72.0)
        let edge = AdaptivePunchGeometry.bindingEdge(forLogicalPageIndex: logicalBookIndex)
        let centerX: CGFloat = edge == .left
            ? targetRect.minX + inset
            : targetRect.maxX - inset

        context.saveGState()
        defer { context.restoreGState() }

        context.setStrokeColor(NSColor.black.cgColor)
        context.setFillColor(NSColor.black.cgColor)
        context.setLineWidth(0.35)

        for yFromTop in targetYFromTop {
            let centerY = targetRect.maxY - CGFloat(yFromTop * 72.0)
            let circle = CGRect(
                x: centerX - radius,
                y: centerY - radius,
                width: radius * 2.0,
                height: radius * 2.0
            )
            context.strokeEllipse(in: circle)

            // Tiny center mark makes manual alignment repeatable without filling
            // the 0.10-inch target circle.
            let dotRadius: CGFloat = 0.45
            context.fillEllipse(in: CGRect(
                x: centerX - dotRadius,
                y: centerY - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            ))
        }
    }

    private static func drawCalibrationTile(
        number: Int?,
        side: MiniBookSheetSide,
        position: Int,
        batchIndex: Int,
        sheetIndexInBatch: Int,
        sheetsInBatch: Int,
        in context: CGContext
    ) {
        let rect = MiniBookLayout.tileRect(position)
        context.saveGState()
        context.setStrokeColor(NSColor.systemGray.cgColor)
        context.setLineWidth(0.5)
        context.stroke(rect.insetBy(dx: 8, dy: 8))
        context.restoreGState()

        guard let number else { return }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let bigAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 82, weight: .bold),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph
        ]
        let smallAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.darkGray,
            .paragraphStyle: paragraph
        ]

        NSGraphicsContext.saveGraphicsState()
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = graphics

        let numberRect = CGRect(x: rect.minX + 20, y: rect.midY - 56, width: rect.width - 40, height: 112)
        NSString(string: "\(number)").draw(in: numberRect, withAttributes: bigAttributes)

        let pos = MiniBookTilePosition(rawValue: position)
        let sideText = "\(side.rawValue.uppercased()) • Pile \(pos?.pileLetter ?? "?") • \(pos?.label ?? "")"
        let sideRect = CGRect(x: rect.minX + 14, y: rect.minY + 30, width: rect.width - 28, height: 20)
        NSString(string: sideText).draw(in: sideRect, withAttributes: smallAttributes)

        let batchText = "Batch \(batchIndex + 1) • Sheet \(sheetIndexInBatch + 1)/\(sheetsInBatch)"
        let batchRect = CGRect(x: rect.minX + 14, y: rect.minY + 12, width: rect.width - 28, height: 18)
        NSString(string: batchText).draw(in: batchRect, withAttributes: smallAttributes)

        NSGraphicsContext.restoreGraphicsState()
    }

    private static func fillWhite(_ rect: CGRect, in context: CGContext) {
        context.saveGState()
        context.setFillColor(NSColor.white.cgColor)
        context.fill(rect)
        context.restoreGState()
    }

    private static func drawMicroCutMarks(in context: CGContext) {
        let w = MiniBookLayout.sheetRect.width
        let h = MiniBookLayout.sheetRect.height
        let midX = MiniBookLayout.tileWidth
        let midY = MiniBookLayout.tileHeight
        let length = MiniBookLayout.cutMarkLength
        let inset = MiniBookLayout.cutMarkEdgeInset

        context.saveGState()
        defer { context.restoreGState() }

        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(MiniBookLayout.cutMarkLineWidth)
        context.setLineCap(.butt)

        context.move(to: CGPoint(x: midX, y: inset))
        context.addLine(to: CGPoint(x: midX, y: inset + length))
        context.move(to: CGPoint(x: midX, y: h - inset))
        context.addLine(to: CGPoint(x: midX, y: h - inset - length))

        context.move(to: CGPoint(x: inset, y: midY))
        context.addLine(to: CGPoint(x: inset + length, y: midY))
        context.move(to: CGPoint(x: w - inset, y: midY))
        context.addLine(to: CGPoint(x: w - inset - length, y: midY))

        context.strokePath()
    }
}
