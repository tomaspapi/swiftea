import SwiftUI

struct DashboardCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(
                cardFill,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
    }

    private var cardFill: Color {
        switch colorScheme {
        case .light:
            Color.black.opacity(0.035)
        case .dark:
            Color.white.opacity(0.055)
        @unknown default:
            Color.primary.opacity(0.04)
        }
    }
}
