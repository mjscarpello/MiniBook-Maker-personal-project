import AppKit
import Combine
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    static let appVersion = "2.1"

    enum PreviewMode: String, CaseIterable, Identifiable {
        case sheet = "Sheet"
        case book = "Book"
        case cut = "Cut"

        var id: String { rawValue }
    }

    @Published var document: PDFDocument?
    @Published var fileName: String = ""
    @Published var previewMode: PreviewMode = .sheet
    @Published var sheetSide: MiniBookSheetSide = .front
    @Published var currentSheet: Int = 0
    @Published var currentPage: Int = 0
    @Published var zoom: Double = 1.0
    @Published var isImportPresented = false
    @Published var isPageEditorPresented = false
    @Published var isDropTarget = false
    @Published var alertTitle: String = ""
    @Published var alertMessage: String = ""
    @Published var showAlert = false
    @Published var lastExportURL: URL?
    @Published var bindingSettings = BindingGuideSettings()
    @Published private(set) var sourceLayoutMode: SourceLayoutMode = .automatic

    /// This preference belongs ONLY to Select & Arrange Pages. The exporter never
    /// reads it. The export engine always performs its independent duplex imposition.
    @Published private(set) var organizerKeepsSourceOrder: Bool = true

    let thumbnailStore = PDFThumbnailStore()

    /// Every logical book page available after interpreting source PDF pages as
    /// full pages or left/right spreads. This is always in source reading order.
    @Published private(set) var availableBookPages: [BookPageRef] = []

    /// The exact reading order selected by the user. Duplex physical ordering is
    /// applied later by MiniBookImposition and never mutates this array.
    @Published private(set) var bookPages: [BookPageRef] = []

    private var sourceData: Data?
    private var sheetCache: [String: Data] = [:]
    private var pageCache: [String: Data] = [:]

    var hasDocument: Bool { document != nil }
    var sourcePageCount: Int { document?.pageCount ?? 0 }
    var availableBookPageCount: Int { availableBookPages.count }
    var pageCount: Int { bookPages.count }
    var splitSourcePageCount: Int { max(0, availableBookPageCount - sourcePageCount) }
    var leafCount: Int { MiniBookImposition.physicalLeafCount(forBookPageCount: pageCount) }
    var sheetCount: Int { MiniBookImposition.physicalSheetCount(forBookPageCount: pageCount) }
    var cutBatchCount: Int { MiniBookImposition.cutBatchCount(forBookPageCount: pageCount) }
    var outputPDFPageCount: Int { sheetCount * 2 }
    var impositionValidation: ImpositionValidationResult {
        MiniBookImposition.validate(
            plan: MiniBookImposition.makePlan(bookPageCount: pageCount),
            bookPageCount: pageCount
        )
    }
    var bindingValidation: BindingGeometryValidation {
        AdaptivePunchGeometry.validate(bookPageCount: pageCount, settings: bindingSettings)
    }
    var canExport: Bool {
        hasDocument && !bookPages.isEmpty && impositionValidation.isValid && bindingValidation.isValid
    }

    var estimatedStackThicknessInches: Double {
        bindingSettings.resolvedStackThicknessInches(totalLeaves: leafCount)
    }

    var firstLeafHoleSpacingInches: Double? {
        guard leafCount > 0 else { return nil }
        return AdaptivePunchGeometry.holeSpacingInches(leafIndex: 0, totalLeaves: leafCount, settings: bindingSettings)
    }

    var middleLeafHoleSpacingInches: Double? {
        guard leafCount > 0 else { return nil }
        return AdaptivePunchGeometry.holeSpacingInches(leafIndex: max(0, (leafCount - 1) / 2), totalLeaves: leafCount, settings: bindingSettings)
    }

    var lastLeafHoleSpacingInches: Double? {
        guard leafCount > 0 else { return nil }
        return AdaptivePunchGeometry.holeSpacingInches(leafIndex: leafCount - 1, totalLeaves: leafCount, settings: bindingSettings)
    }

    var displayPositionText: String {
        switch previewMode {
        case .sheet:
            guard sheetCount > 0 else { return "" }
            if let batch = MiniBookImposition.batchForPhysicalSheet(sheetIndex: currentSheet, bookPageCount: pageCount) {
                let local = currentSheet - batch.firstPhysicalSheetIndex + 1
                return "Batch \(batch.batchIndex + 1)/\(cutBatchCount) • Sheet \(local)/\(batch.sheetCount) • \(sheetSide.rawValue)"
            }
            return "Physical sheet \(currentSheet + 1) of \(sheetCount) • \(sheetSide.rawValue)"
        case .cut:
            guard sheetCount > 0 else { return "" }
            if let batch = MiniBookImposition.batchForPhysicalSheet(sheetIndex: currentSheet, bookPageCount: pageCount) {
                let local = currentSheet - batch.firstPhysicalSheetIndex + 1
                return "Cut batch \(batch.batchIndex + 1)/\(cutBatchCount) • Sheet \(local)/\(batch.sheetCount)"
            }
            return "Physical sheet \(currentSheet + 1) of \(sheetCount) • 4 cut leaves"
        case .book:
            guard pageCount > 0, let ref = bookPageRef(forBookIndex: currentPage) else { return "" }
            return "Book page \(currentPage + 1) of \(pageCount) • \(ref.sourceLabel)"
        }
    }

    func requestImport() {
        isImportPresented = true
    }

    func openPageEditor() {
        guard hasDocument else { return }
        isPageEditorPresented = true
    }

    func closeDocument() {
        document = nil
        sourceData = nil
        fileName = ""
        availableBookPages = []
        bookPages = []
        sourceLayoutMode = .automatic
        organizerKeepsSourceOrder = true
        previewMode = .sheet
        sheetSide = .front
        currentSheet = 0
        currentPage = 0
        zoom = 1.0
        isPageEditorPresented = false
        clearCaches()
        thumbnailStore.reset()
        lastExportURL = nil
    }

    func loadPDF(from url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let data = try Data(contentsOf: url)
            guard let loaded = PDFDocument(data: data), loaded.pageCount > 0 else {
                throw MiniBookError.invalidPDF
            }
            guard !loaded.isLocked else {
                throw MiniBookError.lockedPDF
            }

            document = loaded
            sourceData = data
            fileName = url.lastPathComponent
            sourceLayoutMode = .automatic
            organizerKeepsSourceOrder = true
            thumbnailStore.configure(data: data)
            rebuildLogicalBookPages(selectAll: true)
            currentSheet = 0
            currentPage = 0
            previewMode = .sheet
            sheetSide = .front
            zoom = 1.0
            isPageEditorPresented = false
            clearCaches()
            lastExportURL = nil
        } catch {
            presentError(title: "Couldn’t Open PDF", message: error.localizedDescription)
        }
    }

    /// Changes how source PDF pages become logical book pages. Because a source
    /// page can change from one logical page to two logical pages, selection is
    /// safely reset to all pages in the newly interpreted reading order.
    func setSourceLayoutMode(_ mode: SourceLayoutMode) {
        guard mode != sourceLayoutMode, document != nil else { return }
        sourceLayoutMode = mode
        organizerKeepsSourceOrder = true
        rebuildLogicalBookPages(selectAll: true)
        currentSheet = 0
        currentPage = 0
        sheetSide = .front
        clearCaches()
        lastExportURL = nil
    }

    func applyBookPageOrder(_ proposedOrder: [BookPageRef], keepSourceOrder: Bool) {
        guard document != nil else { return }

        let availableSet = Set(availableBookPages)
        var seen = Set<BookPageRef>()
        var validated = proposedOrder.filter { ref in
            guard availableSet.contains(ref), !seen.contains(ref) else { return false }
            seen.insert(ref)
            return true
        }

        guard !validated.isEmpty else {
            presentError(title: "Choose at Least One Page", message: "Your mini-book needs at least one selected book page.")
            return
        }

        if keepSourceOrder {
            let rank = Dictionary(uniqueKeysWithValues: availableBookPages.enumerated().map { ($0.element, $0.offset) })
            validated.sort { (rank[$0] ?? Int.max) < (rank[$1] ?? Int.max) }
        }

        bookPages = validated
        organizerKeepsSourceOrder = keepSourceOrder
        currentSheet = 0
        currentPage = 0
        sheetSide = .front
        clearCaches()
        lastExportURL = nil
        isPageEditorPresented = false
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.presentError(title: "Couldn’t Open PDF", message: error.localizedDescription)
                }
                return
            }

            var resolvedURL: URL?
            if let url = item as? URL {
                resolvedURL = url
            } else if let data = item as? Data {
                resolvedURL = URL(dataRepresentation: data, relativeTo: nil)
            } else if let nsURL = item as? NSURL {
                resolvedURL = nsURL as URL
            }

            guard let url = resolvedURL, url.pathExtension.lowercased() == "pdf" else {
                DispatchQueue.main.async {
                    self?.presentError(title: "PDF Required", message: "Drop a PDF file into MiniBook Maker.")
                }
                return
            }

            DispatchQueue.main.async {
                self?.loadPDF(from: url)
            }
        }

        return true
    }

    func bookPageRef(forBookIndex bookIndex: Int) -> BookPageRef? {
        guard bookPages.indices.contains(bookIndex) else { return nil }
        return bookPages[bookIndex]
    }

    func sourcePageIndex(forBookIndex bookIndex: Int) -> Int? {
        bookPageRef(forBookIndex: bookIndex)?.sourcePageIndex
    }

    func pageForBookIndex(_ bookIndex: Int) -> PDFPage? {
        guard let document, let ref = bookPageRef(forBookIndex: bookIndex) else { return nil }
        return document.page(at: ref.sourcePageIndex)
    }

    /// Physical imposition lookup. Notice there is no organizer lock parameter.
    /// This reads only from the validated physical sheet plan.
    func bookIndexForPhysicalTile(sheetIndex: Int, side: MiniBookSheetSide, position: Int) -> Int? {
        guard (0..<4).contains(position) else { return nil }
        guard let plan = try? MiniBookImposition.validatedPlan(bookPageCount: pageCount),
              plan.indices.contains(sheetIndex) else {
            return nil
        }
        return plan[sheetIndex].indices(for: side)[position]
    }

    func imposedBookNumbers(sheetIndex: Int, side: MiniBookSheetSide) -> [Int?] {
        MiniBookImposition.displayedBookNumbers(
            sheetIndex: sheetIndex,
            side: side,
            pageCount: pageCount
        )
    }

    func imposedSequenceText(sheetIndex: Int, side: MiniBookSheetSide) -> String {
        imposedBookNumbers(sheetIndex: sheetIndex, side: side)
            .map { $0.map(String.init) ?? "Blank" }
            .joined(separator: "  •  ")
    }

    func next() {
        switch previewMode {
        case .sheet, .cut:
            guard currentSheet + 1 < sheetCount else { return }
            currentSheet += 1
        case .book:
            guard currentPage + 1 < pageCount else { return }
            currentPage += 1
        }
    }

    func previous() {
        switch previewMode {
        case .sheet, .cut:
            guard currentSheet > 0 else { return }
            currentSheet -= 1
        case .book:
            guard currentPage > 0 else { return }
            currentPage -= 1
        }
    }

    func canGoNext() -> Bool {
        switch previewMode {
        case .sheet, .cut: return currentSheet + 1 < sheetCount
        case .book: return currentPage + 1 < pageCount
        }
    }

    func canGoPrevious() -> Bool {
        switch previewMode {
        case .sheet, .cut: return currentSheet > 0
        case .book: return currentPage > 0
        }
    }

    func zoomIn() {
        zoom = min(4.0, zoom + 0.25)
    }

    func zoomOut() {
        zoom = max(0.5, zoom - 0.25)
    }

    func resetZoom() {
        zoom = 1.0
    }

    func sheetPreviewData(for index: Int, side: MiniBookSheetSide? = nil) -> Data? {
        guard let document, index >= 0, index < sheetCount else { return nil }
        let resolvedSide = side ?? sheetSide
        let cacheKey = "v2.1-\(index)-\(resolvedSide.rawValue)-\(bookPages.map(\.id).joined(separator: ","))-\(bindingSettings.cacheKey)"
        if let cached = sheetCache[cacheKey] { return cached }
        let data = PDFExporter.makeSheetData(
            document: document,
            bookPages: bookPages,
            bindingSettings: bindingSettings,
            sheetIndex: index,
            side: resolvedSide
        )
        if let data { sheetCache[cacheKey] = data }
        return data
    }

    func miniPagePreviewData(for bookIndex: Int) -> Data? {
        guard let document, let ref = bookPageRef(forBookIndex: bookIndex) else { return nil }
        let key = "\(ref.id)-\(bookIndex)-\(pageCount)-\(bindingSettings.cacheKey)"
        if let cached = pageCache[key] { return cached }
        let data = PDFExporter.makeMiniPageData(
            document: document,
            bookPage: ref,
            logicalBookIndex: bookIndex,
            totalBookPages: pageCount,
            bindingSettings: bindingSettings
        )
        if let data { pageCache[key] = data }
        return data
    }

    func exportPDF() {
        guard let document, canExport else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.title = "Export Duplex MiniBook PDF"
        panel.prompt = "Export"

        let base = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        panel.nameFieldStringValue = base.isEmpty ? "MiniBook-MB21-CUTSTACK-VERIFIED.pdf" : "\(base)-MB21-CUTSTACK-VERIFIED.pdf"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try PDFExporter.export(document: document, bookPages: bookPages, bindingSettings: bindingSettings, to: url)
            lastExportURL = url
            alertTitle = "Verified Cut-Stack MiniBook Exported"
            alertMessage = "MiniBook Maker 2.1 validated the full cut-stack plan and adaptive punch geometry before export. Print Two-Sided, Flip on Long Edge, at 100% / Actual Size. Keep each cutting batch (maximum 8 sheets) together, cut the stack into four piles, then stack A → B → C → D."
            showAlert = true
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            presentError(title: "Export Failed", message: error.localizedDescription)
        }
    }

    func exportTestSheet() {
        guard let document, canExport else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.title = "Export First Cutting Batch"
        panel.prompt = "Export Test"

        let base = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        panel.nameFieldStringValue = base.isEmpty ? "MiniBook-MB21-FIRST-BATCH.pdf" : "\(base)-MB21-FIRST-BATCH.pdf"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let firstBatchSheets = MiniBookImposition.makeBatches(bookPageCount: pageCount).first?.sheetCount ?? 1
            try PDFExporter.export(
                document: document,
                bookPages: bookPages,
                bindingSettings: bindingSettings,
                to: url,
                maximumPhysicalSheets: firstBatchSheets
            )
            lastExportURL = url
            alertTitle = "First Cutting Batch Exported"
            alertMessage = "This export contains the first cutting batch (up to 8 Letter sheets / 64 book pages). Print Two-Sided with Flip on Long Edge at 100% / Actual Size. Keep all sheets aligned, cut them together, then stack the four mini-page piles A → B → C → D."
            showAlert = true
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            presentError(title: "Export Failed", message: error.localizedDescription)
        }
    }

    func exportCalibrationSheet() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.title = "Export 64-Page Cut-Stack Calibration"
        panel.prompt = "Export Calibration"
        panel.nameFieldStringValue = "MiniBook-MB21-CUTSTACK-CALIBRATION-1-64.pdf"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try PDFExporter.exportCutStackCalibration(to: url)
            lastExportURL = url
            alertTitle = "64-Page Cut-Stack Calibration Exported"
            alertMessage = "Print all 8 sheets Two-Sided, Flip on Long Edge, at 100% / Actual Size. Cut the aligned 8-sheet stack into quarters. Pile A must be 1–16, B 17–32, C 33–48, and D 49–64. Stack A → B → C → D."
            showAlert = true
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            presentError(title: "Calibration Export Failed", message: error.localizedDescription)
        }
    }

    func updateBindingSettings(_ mutate: (inout BindingGuideSettings) -> Void) {
        var updated = bindingSettings
        mutate(&updated)
        bindingSettings = updated
        clearCaches()
        lastExportURL = nil
    }

    func currentBatchPileRangeText(_ pilePosition: Int) -> String {
        guard let batch = MiniBookImposition.batchForPhysicalSheet(sheetIndex: currentSheet, bookPageCount: pageCount) else { return "Blank" }
        return MiniBookImposition.bookPageRangeTextForPile(
            batchIndex: batch.batchIndex,
            pilePosition: pilePosition,
            bookPageCount: pageCount
        )
    }

    func pairedBackBookIndex(forFrontTilePosition position: Int, sheetIndex: Int) -> Int? {
        guard (0..<4).contains(position) else { return nil }
        let backPosition = MiniBookImposition.longEdgeReversePosition[position]
        return bookIndexForPhysicalTile(sheetIndex: sheetIndex, side: .back, position: backPosition)
    }

    private func rebuildLogicalBookPages(selectAll: Bool) {
        guard let document else {
            availableBookPages = []
            bookPages = []
            return
        }

        let rebuilt = BookPageBuilder.build(document: document, mode: sourceLayoutMode)
        availableBookPages = rebuilt
        if selectAll {
            bookPages = rebuilt
        } else {
            let allowed = Set(rebuilt)
            bookPages = bookPages.filter { allowed.contains($0) }
        }
    }

    private func clearCaches() {
        sheetCache.removeAll()
        pageCache.removeAll()
    }

    private func presentError(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }
}

enum MiniBookError: LocalizedError {
    case invalidPDF
    case lockedPDF
    case couldNotCreateOutput
    case invalidImposition
    case invalidBinding(String)

    var errorDescription: String? {
        switch self {
        case .invalidPDF:
            return "The selected file could not be read as a PDF."
        case .lockedPDF:
            return "Password-protected PDFs are not supported in this version. Unlock the PDF first, then import it again."
        case .couldNotCreateOutput:
            return "MiniBook Maker could not create the output PDF."
        case .invalidImposition:
            return "The cut-stack page-imposition safety check failed. Export was stopped before printing an incorrect page order."
        case .invalidBinding(let message):
            return "Adaptive punch-guide validation failed: \(message)"
        }
    }
}
