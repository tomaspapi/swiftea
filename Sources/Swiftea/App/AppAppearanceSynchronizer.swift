import AppKit
import SwiftUI

struct AppAppearanceSynchronizer: NSViewRepresentable {
    let themePreference: AppModel.ThemePreference

    func makeNSView(context: Context) -> AppearanceSynchronizingView {
        let view = AppearanceSynchronizingView()
        view.themePreference = themePreference
        view.syncAppearance()
        return view
    }

    func updateNSView(_ nsView: AppearanceSynchronizingView, context: Context) {
        nsView.themePreference = themePreference
        nsView.syncAppearance()
    }
}

@MainActor
final class AppearanceSynchronizingView: NSView {
    var themePreference: AppModel.ThemePreference = .system

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncAppearance()
    }

    func syncAppearance() {
        let appearance = themePreference.nsAppearance

        NSApp.appearance = appearance

        for window in NSApp.windows {
            window.appearance = appearance
        }

        window?.appearance = appearance
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
