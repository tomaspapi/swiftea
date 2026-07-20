import AppKit
import SwiftUI

@MainActor
enum MainWindowPresenter {
    static func show(openWindow: OpenWindowAction) {
        if focusExistingMainWindow() {
            return
        }

        openWindow(id: "main")

        DispatchQueue.main.async {
            _ = focusExistingMainWindow()
        }
    }

    @discardableResult
    private static func focusExistingMainWindow() -> Bool {
        let windows = NSApp.windows.filter(\.isSwifteaMainWindow)
        guard let window = windows.first else {
            return false
        }

        for duplicateWindow in windows.dropFirst() {
            duplicateWindow.close()
        }

        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }
}

private extension NSWindow {
    var isSwifteaMainWindow: Bool {
        guard title == "Swiftea" else { return false }

        return true
    }
}
