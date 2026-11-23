import PDFKit
import SwiftUI

struct PDFKitPreview: NSViewRepresentable {
    let data: Data
    let identity: String
    let zoom: Double

    final class Coordinator {
        var identity = ""
        var zoom: Double = -1
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePage
        view.displayDirection = .vertical
        view.displaysPageBreaks = false
        view.autoScales = true
        view.backgroundColor = .clear
        view.minScaleFactor = 0.1
        view.maxScaleFactor = 8.0
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        let needsDocument = context.coordinator.identity != identity
        if needsDocument {
            view.document = PDFDocument(data: data)
            view.goToFirstPage(nil)
            view.autoScales = true
            context.coordinator.identity = identity
            context.coordinator.zoom = -1
        }

        guard context.coordinator.zoom != zoom || needsDocument else { return }
        context.coordinator.zoom = zoom

        DispatchQueue.main.async {
            let fit = view.scaleFactorForSizeToFit
            if fit > 0 {
                view.autoScales = false
                view.scaleFactor = min(view.maxScaleFactor, max(view.minScaleFactor, fit * zoom))
            } else {
                view.autoScales = true
            }
        }
    }
}
