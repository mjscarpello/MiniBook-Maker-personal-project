import CoreGraphics
import Foundation
import PDFKit

/// How a source PDF page is interpreted before mini-book imposition.
///
/// This is deliberately separate from page selection/order. The organizer decides
/// the reading order; this mode decides whether one PDF page represents one book
/// page or a left/right two-page spread.
enum SourceLayoutMode: String, CaseIterable, Identifiable {
    case automatic = "Auto"
    case singlePages = "Single Pages"
    case twoPageSpreads = "Two-Page Spreads"

    var id: String { rawValue }

    var helpText: String {
        switch self {
        case .automatic:
            return "Automatically split wide PDF pages into left and right book pages."
        case .singlePages:
            return "Treat every PDF page as one finished book page."
        case .twoPageSpreads:
            return "Split every PDF page into a left page followed by a right page."
        }
    }
}

enum BookPageSlice: String, Hashable, Codable {
    case whole
    case left
    case right

    var shortLabel: String {
        switch self {
        case .whole: return "Full"
        case .left: return "Left"
        case .right: return "Right"
        }
    }
}

/// A single logical page in reading order.
///
/// One source PDF page can produce either one `whole` page or two logical pages
/// (`left`, then `right`). The duplex exporter works only with these logical book
/// pages and never sorts them itself.
struct BookPageRef: Hashable, Identifiable, Codable {
    let sourcePageIndex: Int
    let slice: BookPageSlice

    var id: String { "\(sourcePageIndex)-\(slice.rawValue)" }

    var sourceLabel: String {
        switch slice {
        case .whole:
            return "PDF \(sourcePageIndex + 1)"
        case .left:
            return "PDF \(sourcePageIndex + 1) • Left"
        case .right:
            return "PDF \(sourcePageIndex + 1) • Right"
        }
    }
}

enum BookPageBuilder {
    /// A normal portrait page is about 0.77 wide/high, while a two-page portrait
    /// spread is commonly around 1.5. Using 1.05 intentionally treats any clearly wider-than-tall page as a likely
    /// spread. This app is book-focused, and the Source Layout control lets the
    /// user force Single Pages when a PDF is genuinely landscape content.
    static let automaticSpreadAspectThreshold: CGFloat = 1.05

    static func build(document: PDFDocument, mode: SourceLayoutMode) -> [BookPageRef] {
        var result: [BookPageRef] = []
        result.reserveCapacity(document.pageCount * (mode == .singlePages ? 1 : 2))

        for sourcePageIndex in 0..<document.pageCount {
            guard let page = document.page(at: sourcePageIndex) else { continue }

            let shouldSplit: Bool
            switch mode {
            case .singlePages:
                shouldSplit = false
            case .twoPageSpreads:
                shouldSplit = true
            case .automatic:
                let bounds = page.bounds(for: .cropBox)
                shouldSplit = isLikelyTwoPageSpread(bounds: bounds)
            }

            if shouldSplit {
                // Reading order is always left page, then right page.
                result.append(BookPageRef(sourcePageIndex: sourcePageIndex, slice: .left))
                result.append(BookPageRef(sourcePageIndex: sourcePageIndex, slice: .right))
            } else {
                result.append(BookPageRef(sourcePageIndex: sourcePageIndex, slice: .whole))
            }
        }

        return result
    }

    static func isLikelyTwoPageSpread(bounds: CGRect) -> Bool {
        guard bounds.width > 0, bounds.height > 0 else { return false }
        return bounds.width / bounds.height >= automaticSpreadAspectThreshold
    }

    /// Returns the crop rectangle for a logical page in PDF page coordinates.
    static func cropRect(for ref: BookPageRef, page: PDFPage) -> CGRect {
        let bounds = page.bounds(for: .cropBox)
        guard bounds.width > 0, bounds.height > 0 else { return bounds }

        switch ref.slice {
        case .whole:
            return bounds
        case .left:
            return CGRect(
                x: bounds.minX,
                y: bounds.minY,
                width: bounds.width / 2.0,
                height: bounds.height
            )
        case .right:
            return CGRect(
                x: bounds.midX,
                y: bounds.minY,
                width: bounds.width / 2.0,
                height: bounds.height
            )
        }
    }
}
