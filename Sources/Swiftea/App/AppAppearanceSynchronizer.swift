import AppKit
import SwiftUI

struct AppAppearanceSynchronizer: NSViewRepresentable {
    let themePreference: AppModel.ThemePreference

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        syncAppearance(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        syncAppearance(from: nsView)
    }

    private func syncAppearance(from view: NSView) {
        DispatchQueue.main.async {
            let appearance = themePreference.nsAppearance

            NSApp.appearance = appearance

            for window in NSApp.windows {
                window.appearance = appearance
            }

            view.window?.appearance = appearance
        }
    }
}

private extension AppModel.ThemePreference {
    var nsAppearance: NSAppearance? {
        switch self {
        case .system:
            nil
        case .light:
            NSAppearance(named: .aqua)
        case .dark:
            NSAppearance(named: .darkAqua)
        }
    }
}
