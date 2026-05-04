import AppKit
import Foundation

enum SystemSettingsNavigator {
    static func openBluetoothPrivacy() {
        let urls = [
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth"),
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy"),
            URL(string: "x-apple.systempreferences:com.apple.preference.security")
        ].compactMap { $0 }

        for url in urls where NSWorkspace.shared.open(url) {
            return
        }
    }
}
