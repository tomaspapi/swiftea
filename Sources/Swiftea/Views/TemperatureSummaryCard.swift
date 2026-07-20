import SwiftUI

struct TemperatureSummaryCard: View {
    @Bindable var model: AppModel

    private enum StatusPresentation: Equatable {
        case heating
        case idle
        case empty
    }

    private var statusPresentation: StatusPresentation {
        if model.isEmpty == true {
            return .empty
        }

        return model.isTemperatureControlOff ? .idle : .heating
    }

    private var currentTemperatureDisplayLabel: String {
        statusPresentation == .empty ? "—" : model.currentTemperatureLabel
    }

    var body: some View {
        DashboardCard {
            cardContent
        }
            .animation(.snappy(duration: 0.34, extraBounce: 0.05), value: statusPresentation)
    }

    private var cardContent: some View {
        VStack(spacing: 5) {
            sectionTitle("Current temperature")

            Text(currentTemperatureDisplayLabel)
                .font(.system(size: 60, weight: .semibold, design: .rounded))
                .foregroundStyle(valueColor)
                .frame(maxWidth: .infinity, alignment: .center)

            statusSymbol
                .frame(height: 18)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 16)
    }

    private var titleColor: Color {
        .secondary
    }

    private var valueColor: Color {
        .primary
    }

    @ViewBuilder
    private var statusSymbol: some View {
        switch statusPresentation {
        case .heating:
            AnimatedStatusSymbol(
                systemName: "heat.waves",
                fontSize: 14,
                weight: .semibold,
                baseColor: Color.orange,
                softHighlightColor: Color(red: 1.0, green: 0.66, blue: 0.25),
                brightHighlightColor: Color(red: 1.0, green: 0.86, blue: 0.52)
            )
            .transition(
                .asymmetric(
                    insertion: .scale(scale: 0.82).combined(with: .opacity),
                    removal: .scale(scale: 0.78).combined(with: .opacity)
                )
            )
        case .idle:
            Image(systemName: "pause.fill")
                .font(.system(size: 14, weight: .semibold))
                .swifteaSymbolStyle(SwifteaSymbolColor.muted)
        case .empty:
            Text("Mug is currently empty")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(nsColor: .disabledControlTextColor))
                .lineLimit(1)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(titleColor)
            .tracking(0.6)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

#Preview {
    TemperatureSummaryCard(model: AppModel.previewConnected())
        .padding()
}
