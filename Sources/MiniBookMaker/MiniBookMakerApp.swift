import SwiftUI

@main
struct MiniBookMakerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("MiniBook Maker 2.1") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 680)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open PDF…") {
                    model.requestImport()
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandMenu("Pages") {
                Button("Select & Arrange Pages…") {
                    model.openPageEditor()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(!model.hasDocument)
            }

            CommandGroup(after: .saveItem) {
                Button("Export Verified Cut-Stack PDF…") {
                    model.exportPDF()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!model.canExport)
            }
        }
    }
}
