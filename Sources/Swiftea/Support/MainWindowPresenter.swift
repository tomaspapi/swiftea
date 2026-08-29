import AppKit
import SwiftUI

@MainActor
enum MainWindowPresenter {
    static func show(appDelegate: AppDelegate, openWindow: OpenWindowAction) {
        AppLog.windowing.notice("Show Swiftea action invoked")
        guard !appDelegate.requestMainWindowPresentation() else { return }

        AppLog.windowing.notice("Opening main window scene")
        openWindow(id: "main")
    }
}

extension NSWindow {
    var isSwifteaMainWindow: Bool {
        identifier?.rawValue == "main"
    }
}

struct SwifteaMainWindowMarker: NSViewRepresentable {
    let appDelegate: AppDelegate

    func makeNSView(context: Context) -> SwifteaMainWindowMarkerView {
        let view = SwifteaMainWindowMarkerView(frame: .zero)
        view.appDelegate = appDelegate
        return view
    }

    func updateNSView(_ nsView: SwifteaMainWindowMarkerView, context: Context) {
        nsView.appDelegate = appDelegate
        nsView.registerMainWindowIfAvailable()
    }
}

@MainActor
final class SwifteaMainWindowMarkerView: NSView {
    weak var appDelegate: AppDelegate?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registerMainWindowIfAvailable()
    }

    func registerMainWindowIfAvailable() {
        guard let window else { return }
        window.identifier = NSUserInterfaceItemIdentifier("main")
        appDelegate?.registerMainWindow(window)
    }
}
