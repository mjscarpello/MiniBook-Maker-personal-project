import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    private var sourceLayoutBinding: Binding<SourceLayoutMode> {
        Binding(
            get: { model.sourceLayoutMode },
            set: { model.setSourceLayoutMode($0) }
        )
    }

    private func bindingSetting(_ keyPath: WritableKeyPath<BindingGuideSettings, Double>) -> Binding<Double> {
        Binding(
            get: { model.bindingSettings[keyPath: keyPath] },
            set: { newValue in
                model.updateBindingSettings { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private var bindingEnabled: Binding<Bool> {
        Binding(
            get: { model.bindingSettings.enabled },
            set: { value in model.updateBindingSettings { $0.enabled = value } }
        )
    }

    private var thicknessModeBinding: Binding<BindingThicknessMode> {
        Binding(
            get: { model.bindingSettings.thicknessMode },
            set: { value in model.updateBindingSettings { $0.thicknessMode = value } }
        )
    }

    private var smallNumberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 4
        formatter.minimum = 0
        return formatter
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 270)

            Divider()

            VStack(spacing: 0) {
                toolbar
                Divider()
                previewArea
                Divider()
                footer
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .fileImporter(
            isPresented: $model.isImportPresented,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                model.loadPDF(from: url)
            case .failure(let error):
                model.alertTitle = "Couldn’t Open PDF"
                model.alertMessage = error.localizedDescription
                model.showAlert = true
            }
        }
        .sheet(isPresented: $model.isPageEditorPresented) {
            PageOrganizerView()
                .environmentObject(model)
        }
        .alert(isPresented: $model.showAlert) {
            Alert(
                title: Text(model.alertTitle),
                message: Text(model.alertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MiniBook Maker 2")
                            .font(.title2.bold())
                        Text("v2.1 • Cut-stack imposition + adaptive punch guides")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if model.hasDocument {
                        Button {
                            model.closeDocument()
                        } label: {
                            Label("Back to Start", systemImage: "chevron.left")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .keyboardShortcut(.cancelAction)

                        Button {
                            model.openPageEditor()
                        } label: {
                            Label("Select & Arrange Pages", systemImage: "rectangle.stack")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            model.requestImport()
                        } label: {
                            Label("Open Another PDF", systemImage: "doc.badge.plus")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        Button {
                            model.requestImport()
                        } label: {
                            Label("Open PDF", systemImage: "doc.badge.plus")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if model.hasDocument {
                        GroupBox("Source Layout") {
                            VStack(alignment: .leading, spacing: 8) {
                                Picker("PDF contains", selection: sourceLayoutBinding) {
                                    ForEach(SourceLayoutMode.allCases) { mode in
                                        Text(mode.rawValue).tag(mode)
                                    }
                                }
                                .labelsHidden()

                                Text(model.sourceLayoutMode.helpText)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)

                                Divider()
                                infoRow("PDF pages", "\(model.sourcePageCount)")
                                infoRow("Detected book pages", "\(model.availableBookPageCount)")
                                if model.sourceLayoutMode == .automatic {
                                    infoRow("Auto-split spreads", "\(model.splitSourcePageCount)")
                                }
                            }
                            .padding(.top, 3)
                        }
                    }

                    GroupBox("Universal Format") {
                        VStack(alignment: .leading, spacing: 9) {
                            infoRow("Paper", "US Letter")
                            infoRow("Layout", "2 × 2 duplex")
                            infoRow("Mini-page", "4.25 × 5.5 in")
                            infoRow("Leaves/sheet", "4")
                            infoRow("Book pages/sheet", "Up to 8")
                            infoRow("Cut batch", "≤ 8 sheets / 64 pages")
                            infoRow("Cut marks", "2.5 mm")
                            infoRow("Mark width", "0.25 pt")
                        }
                        .padding(.top, 3)
                    }

                    if model.hasDocument {
                        GroupBox("Cut-Stack Print Map") {
                            VStack(alignment: .leading, spacing: 8) {
                                Label(
                                    model.impositionValidation.isValid ? "Cut-stack plan validated" : "Export blocked",
                                    systemImage: model.impositionValidation.isValid ? "checkmark.shield.fill" : "exclamationmark.triangle.fill"
                                )
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(model.impositionValidation.isValid ? Color.accentColor : Color.red)

                                Text("Full batch • Sheet 1")
                                    .font(.caption2.weight(.semibold))
                                Text("Front  TL 1  •  TR 17  •  BL 33  •  BR 49")
                                    .font(.system(.caption2, design: .monospaced))
                                Text("Back   TL 18 •  TR 2   •  BL 50  •  BR 34")
                                    .font(.system(.caption2, design: .monospaced))
                                Text("Cut up to 8 sheets together, then stack piles A → B → C → D.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("Keep Reading Order only affects Select & Arrange; it cannot override this print map.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 3)
                        }

                        GroupBox("Adaptive Punch Guides") {
                            VStack(alignment: .leading, spacing: 9) {
                                Toggle("Print 0.10-in punch targets", isOn: bindingEnabled)
                                    .toggleStyle(.switch)

                                if model.bindingSettings.enabled {
                                    Picker("Thickness", selection: thicknessModeBinding) {
                                        ForEach(BindingThicknessMode.allCases) { mode in
                                            Text(mode.rawValue).tag(mode)
                                        }
                                    }
                                    .pickerStyle(.segmented)

                                    measurementField("Ring diameter", bindingSetting(\.ringDiameterInches), suffix: "in")
                                    measurementField("Edge inset", bindingSetting(\.bindingEdgeInsetInches), suffix: "in")

                                    if model.bindingSettings.thicknessMode == .estimated {
                                        measurementField("Paper caliper", bindingSetting(\.paperCaliperInches), suffix: "in")
                                    } else {
                                        measurementField("Stack thickness", bindingSetting(\.measuredStackThicknessInches), suffix: "in")
                                    }

                                    Divider()
                                    infoRow("Resolved stack", String(format: "%.3f in", model.estimatedStackThicknessInches))
                                    if let first = model.firstLeafHoleSpacingInches {
                                        infoRow("First leaf spacing", String(format: "%.3f in", first))
                                    }
                                    if let middle = model.middleLeafHoleSpacingInches {
                                        infoRow("Middle spacing", String(format: "%.3f in", middle))
                                    }
                                    if let last = model.lastLeafHoleSpacingInches {
                                        infoRow("Last leaf spacing", String(format: "%.3f in", last))
                                    }
                                    infoRow("Ring centers", "1.50 / 4.00 in")

                                    if !model.bindingValidation.isValid {
                                        Label(model.bindingValidation.message, systemImage: "exclamationmark.triangle.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.red)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .padding(.top, 3)
                        }
                    }

                    if model.hasDocument {
                        GroupBox("Document") {
                            VStack(alignment: .leading, spacing: 9) {
                                Text(model.fileName)
                                    .lineLimit(2)
                                    .font(.callout.weight(.medium))
                                Divider()
                                infoRow("Book pages", "\(model.pageCount) selected")
                                infoRow("Physical leaves", "\(model.leafCount)")
                                infoRow("Physical sheets", "\(model.sheetCount)")
                                infoRow("Cut batches", "\(model.cutBatchCount)")
                                infoRow("PDF print pages", "\(model.outputPDFPageCount)")
                                infoRow("Cuts/sheet", "2")
                            }
                            .padding(.top, 3)
                        }
                    }
                }
                .padding(18)
            }

            Divider()

            VStack(alignment: .leading, spacing: 5) {
                Label("Two-Sided • Flip on Long Edge", systemImage: "printer")
                    .font(.caption.weight(.semibold))
                Text("100% / Actual Size. Keep each ≤8-sheet batch aligned, cut into four piles, then stack A → B → C → D. Print only the MB21-CUTSTACK-VERIFIED PDF.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            if model.hasDocument {
                Button {
                    model.closeDocument()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .help("Return to the start screen (Esc)")

                Button {
                    model.openPageEditor()
                } label: {
                    Label("Pages", systemImage: "rectangle.stack")
                }
                .help("Choose and arrange logical book pages (⇧⌘P)")

                Divider().frame(height: 22)
            }

            Picker("Preview", selection: $model.previewMode) {
                ForEach(AppModel.PreviewMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 260)
            .disabled(!model.hasDocument || model.pageCount == 0)

            if model.previewMode == .sheet {
                Picker("Side", selection: $model.sheetSide) {
                    ForEach(MiniBookSheetSide.allCases) { side in
                        Text(side.rawValue).tag(side)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                .help("Switch between the physical front and back of this Letter sheet")
            }

            Spacer()

            Button(action: model.zoomOut) {
                Image(systemName: "minus.magnifyingglass")
            }
            .help("Zoom Out")
            .disabled(!model.hasDocument || model.pageCount == 0 || model.previewMode == .cut)

            Button(action: model.resetZoom) {
                Text("\(Int(model.zoom * 100))%")
                    .monospacedDigit()
                    .frame(width: 48)
            }
            .buttonStyle(.plain)
            .help("Reset Zoom")
            .disabled(!model.hasDocument || model.pageCount == 0 || model.previewMode == .cut)

            Button(action: model.zoomIn) {
                Image(systemName: "plus.magnifyingglass")
            }
            .help("Zoom In")
            .disabled(!model.hasDocument || model.pageCount == 0 || model.previewMode == .cut)

            Divider().frame(height: 22)

            Menu {
                Button("Export Full Cut-Stack Book…") {
                    model.exportPDF()
                }

                Button("Export First Cutting Batch…") {
                    model.exportTestSheet()
                }


                Divider()

                Button("Export 64-Page Cut-Stack Calibration…") {
                    model.exportCalibrationSheet()
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.borderedProminent)
            .disabled(!model.canExport)
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
    }

    @ViewBuilder
    private var previewArea: some View {
        if model.hasDocument {
            ZStack {
                Color(nsColor: .underPageBackgroundColor)

                if model.pageCount == 0 {
                    VStack(spacing: 12) {
                        Image(systemName: "rectangle.stack.badge.minus")
                            .font(.system(size: 42, weight: .light))
                            .foregroundStyle(.secondary)
                        Text("No pages selected")
                            .font(.title3.weight(.semibold))
                        Button("Select Pages…") {
                            model.openPageEditor()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    switch model.previewMode {
                    case .sheet:
                        sheetPreview
                    case .book:
                        bookPreview
                    case .cut:
                        cutPreview
                    }
                }
            }
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)

            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    model.isDropTarget ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 7])
                )
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.72))
                )
                .frame(maxWidth: 560, maxHeight: 330)
                .padding(40)

            VStack(spacing: 13) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Drop a PDF here")
                    .font(.title2.weight(.semibold))
                Text("or open one to create a standardized duplex mini-book")
                    .foregroundStyle(.secondary)
                Button("Choose PDF…") {
                    model.requestImport()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $model.isDropTarget) { providers in
            model.handleDrop(providers: providers)
        }
    }

    private var sheetPreview: some View {
        Group {
            if let data = model.sheetPreviewData(for: model.currentSheet) {
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        Label(
                            model.sheetSide == .front ? "Physical Front" : "Physical Back",
                            systemImage: model.sheetSide == .front ? "1.square" : "2.square"
                        )
                        .font(.caption.weight(.semibold))

                        Text("Pile A/TL • Pile B/TR • Pile C/BL • Pile D/BR")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Text(model.imposedSequenceText(sheetIndex: model.currentSheet, side: model.sheetSide))
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.accentColor)

                    PDFKitPreview(
                        data: data,
                        identity: "sheet-\(model.currentSheet)-\(model.sheetSide.rawValue)-\(model.pageCount)-\(model.sourceLayoutMode.rawValue)-\(model.bindingSettings.cacheKey)",
                        zoom: model.zoom
                    )
                }
                .padding(20)
            } else {
                Text("Couldn’t render this sheet.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var bookPreview: some View {
        VStack(spacing: 10) {
            if let ref = model.bookPageRef(forBookIndex: model.currentPage) {
                VStack(spacing: 3) {
                    Text("Book page \(model.currentPage + 1) • \(ref.sourceLabel) • finished 4.25 × 5.5 in")
                    if model.bindingSettings.enabled {
                        let leaf = AdaptivePunchGeometry.physicalLeafIndex(forLogicalPageIndex: model.currentPage)
                        let spacing = AdaptivePunchGeometry.holeSpacingInches(
                            leafIndex: leaf,
                            totalLeaves: model.leafCount,
                            settings: model.bindingSettings
                        )
                        Text("Physical leaf \(leaf + 1) • punch spacing \(spacing.map { String(format: "%.3f in", $0) } ?? "invalid")")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 10)
            }

            if let data = model.miniPagePreviewData(for: model.currentPage) {
                PDFKitPreview(
                    data: data,
                    identity: "page-\(model.currentPage)-\(model.bookPageRef(forBookIndex: model.currentPage)?.id ?? "none")-\(model.bindingSettings.cacheKey)",
                    zoom: model.zoom
                )
                .padding(.horizontal, 80)
                .padding(.bottom, 18)
            }
        }
    }

    private var cutPreview: some View {
        VStack(spacing: 16) {
            Text("Cut-Stack Preview")
                .font(.headline)

            if let batch = MiniBookImposition.batchForPhysicalSheet(sheetIndex: model.currentSheet, bookPageCount: model.pageCount) {
                Text("Batch \(batch.batchIndex + 1) uses \(batch.sheetCount) Letter sheet\(batch.sheetCount == 1 ? "" : "s"). Keep them aligned, cut the full stack into quarters, then stack A → B → C → D.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 800)

                HStack(spacing: 12) {
                    ForEach(0..<4, id: \.self) { pile in
                        VStack(spacing: 2) {
                            Text("Pile \(MiniBookTilePosition(rawValue: pile)?.pileLetter ?? "?")")
                                .font(.caption.weight(.semibold))
                            Text(model.currentBatchPileRangeText(pile))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: 820)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(0..<4, id: \.self) { position in
                    cutPileTile(position: position)
                }
            }
            .frame(maxWidth: 820)
            .padding(.horizontal, 24)
        }
        .padding(24)
    }

    private func cutPileTile(position: Int) -> some View {
        let frontBookIndex = model.bookIndexForPhysicalTile(
            sheetIndex: model.currentSheet,
            side: .front,
            position: position
        )
        let backBookIndex = model.pairedBackBookIndex(
            forFrontTilePosition: position,
            sheetIndex: model.currentSheet
        )
        let tile = MiniBookTilePosition(rawValue: position)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Pile \(tile?.pileLetter ?? "?") • \(tile?.label ?? "")")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(model.currentBatchPileRangeText(position))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            HStack(spacing: 10) {
                leafFace(bookIndex: frontBookIndex, label: "Front")
                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                leafFace(bookIndex: backBookIndex, label: "Back")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    @ViewBuilder
    private func leafFace(bookIndex: Int?, label: String) -> some View {
        if let bookIndex, bookIndex < model.pageCount, let ref = model.bookPageRef(forBookIndex: bookIndex) {
            VStack(spacing: 5) {
                CachedPDFThumbnail(
                    store: model.thumbnailStore,
                    bookPage: ref,
                    pointWidth: 118
                )
                .frame(width: 118, height: 153)
                .background(Color.white)
                .overlay(Rectangle().stroke(Color.secondary.opacity(0.22), lineWidth: 1))

                Text("\(label) • Book \(bookIndex + 1)")
                    .font(.caption2.weight(.medium))
                    .monospacedDigit()
                Text(ref.sourceLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } else {
            VStack(spacing: 5) {
                Rectangle()
                    .fill(Color.white.opacity(0.45))
                    .frame(width: 118, height: 153)
                    .overlay(Rectangle().stroke(Color.secondary.opacity(0.15), lineWidth: 1))
                Text("\(label) • Blank")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button(action: model.previous) {
                Label("Previous", systemImage: "chevron.left")
            }
            .disabled(!model.canGoPrevious())

            Spacer()

            Text(model.displayPositionText)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Spacer()

            Button(action: model.next) {
                Label("Next", systemImage: "chevron.right")
                    .labelStyle(.titleAndIcon)
            }
            .disabled(!model.canGoNext())
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    private func measurementField(_ label: String, _ binding: Binding<Double>, suffix: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            TextField("", value: binding, formatter: smallNumberFormatter)
                .frame(width: 58)
                .multilineTextAlignment(.trailing)
            Text(suffix)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
        .font(.caption)
    }
}

private struct PageOrganizerView: View {
    private enum BrowserMode: String, CaseIterable, Identifiable {
        case all = "All Pages"
        case selected = "Selected Book"

        var id: String { rawValue }
    }

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPages: Set<BookPageRef> = []
    @State private var workingOrder: [BookPageRef] = []
    @State private var keepSourceOrder = true
    @State private var browserMode: BrowserMode = .all
    @State private var thumbnailWidth: Double = 148
    @State private var draggedPage: BookPageRef?

    private var tileWidth: CGFloat { CGFloat(thumbnailWidth) + 18 }
    private var pageWidth: CGFloat { CGFloat(thumbnailWidth) }
    private var pageHeight: CGFloat { pageWidth * (5.5 / 4.25) }

    private var columns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: tileWidth, maximum: tileWidth),
                spacing: 18,
                alignment: .top
            )
        ]
    }

    private var sourceRank: [BookPageRef: Int] {
        Dictionary(uniqueKeysWithValues: model.availableBookPages.enumerated().map { ($0.element, $0.offset) })
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            organizerToolbar
            Divider()
            pageBrowser
            Divider()
            organizerFooter
        }
        .frame(minWidth: 960, minHeight: 700)
        .onAppear {
            workingOrder = model.bookPages
            selectedPages = Set(model.bookPages)
            keepSourceOrder = model.organizerKeepsSourceOrder
        }
        .onChange(of: keepSourceOrder) { isLocked in
            draggedPage = nil
            if isLocked {
                let rank = sourceRank
                workingOrder.sort { (rank[$0] ?? Int.max) < (rank[$1] ?? Int.max) }
            } else {
                browserMode = .selected
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Select & Arrange Pages")
                    .font(.title2.bold())
                Text("These are logical book pages. Two-page source spreads are split before arranging.")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(workingOrder.count) selected")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Button("Cancel") {
                dismiss()
            }

            Button("Apply to Book") {
                model.applyBookPageOrder(workingOrder, keepSourceOrder: keepSourceOrder)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(workingOrder.isEmpty)
        }
        .padding(.horizontal, 20)
        .frame(height: 72)
    }

    private var organizerToolbar: some View {
        HStack(spacing: 14) {
            Picker("View", selection: $browserMode) {
                ForEach(BrowserMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)

            Divider().frame(height: 22)

            Button("Select All") {
                selectAll()
            }
            .keyboardShortcut("a", modifiers: .command)

            Button("Clear") {
                clearSelection()
            }
            .disabled(workingOrder.isEmpty)

            Divider().frame(height: 22)

            Toggle(isOn: $keepSourceOrder) {
                HStack(spacing: 7) {
                    Image(systemName: keepSourceOrder ? "lock.fill" : "lock.open")
                    Text("Keep Reading Order")
                        .fontWeight(.medium)
                }
            }
            .toggleStyle(.switch)
            .help("This lock only controls the organizer. It never controls physical print imposition.")

            Spacer()

            if keepSourceOrder {
                Label("Reading order protected", systemImage: "checkmark.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("Drag to reorder", systemImage: "arrow.up.arrow.down")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var pageBrowser: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)

            if browserMode == .selected && workingOrder.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.stack.badge.minus")
                        .font(.system(size: 38, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("No pages selected")
                        .font(.headline)
                    Text("Switch to All Pages and choose the pages you want in the mini-book.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Show All Pages") {
                        browserMode = .all
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                        if browserMode == .all {
                            ForEach(model.availableBookPages) { ref in
                                pageTile(bookPage: ref, bookPosition: nil)
                            }
                        } else {
                            ForEach(Array(workingOrder.enumerated()), id: \.element) { position, ref in
                                reorderableTile(bookPage: ref, bookPosition: position)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 22)
                }
            }
        }
    }

    @ViewBuilder
    private func reorderableTile(bookPage: BookPageRef, bookPosition: Int) -> some View {
        let tile = pageTile(bookPage: bookPage, bookPosition: bookPosition)

        if keepSourceOrder {
            tile
        } else {
            tile
                .onDrag {
                    draggedPage = bookPage
                    return NSItemProvider(object: bookPage.id as NSString)
                }
                .onDrop(
                    of: [UTType.text],
                    delegate: PageReorderDropDelegate(
                        targetPage: bookPage,
                        pages: $workingOrder,
                        draggedPage: $draggedPage
                    )
                )
        }
    }

    private func pageTile(bookPage: BookPageRef, bookPosition: Int?) -> some View {
        let isSelected = selectedPages.contains(bookPage)
        let sourcePosition = (sourceRank[bookPage] ?? 0) + 1

        return Button {
            togglePage(bookPage)
        } label: {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    CachedPDFThumbnail(
                        store: model.thumbnailStore,
                        bookPage: bookPage,
                        pointWidth: pageWidth
                    )
                    .frame(width: pageWidth, height: pageHeight)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(
                                isSelected ? Color.accentColor : Color.secondary.opacity(0.28),
                                lineWidth: isSelected ? 2.5 : 1
                            )
                    }

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                            .padding(7)
                    }

                    if let bookPosition {
                        Text("\(bookPosition + 1)")
                            .font(.caption2.bold())
                            .monospacedDigit()
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.accentColor))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(7)
                    }
                }

                VStack(spacing: 2) {
                    Text("Page \(sourcePosition)")
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.primary)

                    Text(bookPage.sourceLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if browserMode == .selected && !keepSourceOrder {
                        Text("Book position \((bookPosition ?? 0) + 1)")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .frame(width: tileWidth)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isSelected ? "Included. Click to remove \(bookPage.sourceLabel)." : "Excluded. Click to include \(bookPage.sourceLabel).")
    }

    private var organizerFooter: some View {
        HStack(spacing: 14) {
            Text("\(workingOrder.count) of \(model.availableBookPageCount) book pages")
                .font(.callout)
                .monospacedDigit()

            Text("•")
                .foregroundStyle(.tertiary)

            Text(workingOrder.isEmpty ? "0 physical sheets" : "\(MiniBookImposition.physicalSheetCount(forBookPageCount: workingOrder.count)) physical sheets")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            if !keepSourceOrder {
                Text("• Custom reading order")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color.accentColor)
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    thumbnailWidth = max(88, thumbnailWidth - 20)
                } label: {
                    Image(systemName: "square.grid.3x3")
                }
                .buttonStyle(.plain)
                .help("Smaller page icons")

                Slider(value: $thumbnailWidth, in: 88...260, step: 1)
                    .frame(width: 180)
                    .help("Page icon size")

                Button {
                    thumbnailWidth = min(260, thumbnailWidth + 20)
                } label: {
                    Image(systemName: "square.grid.2x2")
                }
                .buttonStyle(.plain)
                .help("Larger page icons")

                Text("\(Int(thumbnailWidth))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .trailing)
            }
            .accessibilityLabel("Page icon size")
        }
        .padding(.horizontal, 18)
        .frame(height: 48)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func selectAll() {
        let all = Set(model.availableBookPages)

        if keepSourceOrder {
            workingOrder = model.availableBookPages
        } else {
            let existing = Set(workingOrder)
            for ref in model.availableBookPages where !existing.contains(ref) {
                workingOrder.append(ref)
            }
        }

        selectedPages = all
    }

    private func clearSelection() {
        selectedPages.removeAll(keepingCapacity: true)
        workingOrder.removeAll(keepingCapacity: true)
        draggedPage = nil
    }

    private func togglePage(_ bookPage: BookPageRef) {
        if selectedPages.contains(bookPage) {
            selectedPages.remove(bookPage)
            if let position = workingOrder.firstIndex(of: bookPage) {
                workingOrder.remove(at: position)
            }
            return
        }

        selectedPages.insert(bookPage)

        if keepSourceOrder {
            let rank = sourceRank
            let pageRank = rank[bookPage] ?? Int.max
            let insertionIndex = workingOrder.firstIndex {
                (rank[$0] ?? Int.max) > pageRank
            } ?? workingOrder.endIndex
            workingOrder.insert(bookPage, at: insertionIndex)
        } else {
            workingOrder.append(bookPage)
        }
    }
}

private struct CachedPDFThumbnail: View {
    let store: PDFThumbnailStore
    let bookPage: BookPageRef
    let pointWidth: CGFloat

    @State private var image: NSImage?
    @State private var requestKey: String = ""
    @State private var requestToken: UUID?

    private var thumbnailIdentity: String {
        store.requestKey(bookPage: bookPage, pointWidth: pointWidth)
    }

    var body: some View {
        ZStack {
            Color.white

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "doc")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Color.secondary.opacity(0.45))
            }
        }
        .onAppear(perform: loadThumbnail)
        .onChange(of: thumbnailIdentity) { _ in
            loadThumbnail()
        }
        .onDisappear {
            cancelOutstandingRequest()
        }
    }

    private func loadThumbnail() {
        let key = store.requestKey(bookPage: bookPage, pointWidth: pointWidth)
        guard key != requestKey else { return }

        cancelOutstandingRequest()
        requestKey = key

        if let cached = store.cachedImage(bookPage: bookPage, pointWidth: pointWidth) {
            image = cached
            return
        }

        requestToken = store.requestThumbnail(bookPage: bookPage, pointWidth: pointWidth) { loadedImage in
            guard requestKey == key else { return }
            requestToken = nil
            if let loadedImage {
                image = loadedImage
            }
        }
    }

    private func cancelOutstandingRequest() {
        if let requestToken, !requestKey.isEmpty {
            store.cancelRequest(key: requestKey, token: requestToken)
        }
        requestToken = nil
    }
}

private struct PageReorderDropDelegate: DropDelegate {
    let targetPage: BookPageRef
    @Binding var pages: [BookPageRef]
    @Binding var draggedPage: BookPageRef?

    func dropEntered(info: DropInfo) {
        guard let draggedPage,
              draggedPage != targetPage,
              let from = pages.firstIndex(of: draggedPage),
              let to = pages.firstIndex(of: targetPage),
              from != to else {
            return
        }

        pages.swapAt(from, to)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedPage = nil
        return true
    }

    func dropExited(info: DropInfo) {
        // Keep drag state while moving between adjacent cells.
    }
}
