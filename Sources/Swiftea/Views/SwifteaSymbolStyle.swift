import AppKit
import SwiftUI

enum SwifteaSymbolColor {
    static let neutral = Color.primary

    static let muted = Color.secondary

    static let blue = Color.accentColor

    static let green = Color.green

    static let orange = Color.orange

    static let link = Color(nsColor: .linkColor)
}

extension View {
    func swifteaSymbolStyle(_ color: Color = SwifteaSymbolColor.neutral) -> some View {
        symbolRenderingMode(.monochrome)
            .foregroundStyle(color)
            .symbolColorRenderingMode(.flat)
    }
}

extension Image {
    func swifteaSymbolStyle(_ color: Color = SwifteaSymbolColor.neutral) -> some View {
        symbolRenderingMode(.monochrome)
            .symbolColorRenderingMode(.flat)
            .foregroundStyle(color)
    }
}
