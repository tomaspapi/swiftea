import SwiftUI

struct OnboardingView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPageID: Int?
    @State private var didFinish = false
    @State private var hasReviewedLegalDocuments: Bool
    @State private var hasAcceptedTermsOfUse: Bool
    @State private var hasAcceptedSafetyNotice: Bool

    private let pages = OnboardingPage.defaults

    init(model: AppModel) {
        self.model = model
        _selectedPageID = State(
            initialValue: model.shouldStartOnboardingAtLegalAgreement
                ? OnboardingPage.defaults.count - 1
                : 0
        )
        _hasReviewedLegalDocuments = State(initialValue: model.hasAcceptedCurrentLegalDocuments)
        _hasAcceptedTermsOfUse = State(initialValue: model.hasAcceptedCurrentTermsOfUse)
        _hasAcceptedSafetyNotice = State(initialValue: model.hasAcceptedCurrentSafetyNotice)
    }

    private var selectedPageIndex: Int {
        min(max(selectedPageID ?? 0, 0), pages.count - 1)
    }

    private var isLastPage: Bool {
        selectedPageIndex == pages.count - 1
    }

    private var hasAcceptedLegalAgreement: Bool {
        hasAcceptedTermsOfUse && hasAcceptedSafetyNotice
    }

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                OnboardingPageCard(
                    page: pages[selectedPageIndex],
                    hasReviewedLegalDocuments: $hasReviewedLegalDocuments,
                    hasAcceptedTermsOfUse: $hasAcceptedTermsOfUse,
                    hasAcceptedSafetyNotice: $hasAcceptedSafetyNotice
                )
                .id(selectedPageIndex)
                .transition(.opacity)
            }
            .frame(height: 398)
            .animation(.snappy(duration: 0.22), value: selectedPageIndex)

            ZStack {
                PageNavigationControl(
                    pageCount: pages.count,
                    selectedIndex: selectedPageIndex,
                    onPrevious: {
                        navigate(to: selectedPageIndex - 1)
                    },
                    onNext: {
                        navigate(to: selectedPageIndex + 1)
                    }
                )

                HStack {
                    if isLastPage {
                        Spacer()

                        Button("Get Started") {
                            finish()
                        }
                        .disabled(!hasAcceptedLegalAgreement)
                        .keyboardShortcut(.defaultAction)
                    } else {
                        Button("Skip") {
                            navigate(to: pages.count - 1)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .keyboardShortcut(.cancelAction)

                        Spacer()
                    }
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 30)
        .padding(.bottom, 22)
        .frame(width: 500, height: 500)
    }

    private func finish() {
        guard hasAcceptedLegalAgreement else {
            navigate(to: pages.count - 1)
            return
        }

        markFinished()
        dismiss()
    }

    private func navigate(to index: Int) {
        guard pages.indices.contains(index) else { return }

        withAnimation(.snappy(duration: 0.22)) {
            selectedPageID = index
        }
    }

    private func markFinished() {
        guard !didFinish else { return }

        didFinish = true
        model.acceptCurrentLegalDocumentsAndCompleteOnboarding()
    }
}

private struct OnboardingPage: Identifiable {
    enum VisualKind {
        case oneDevice
        case heat
        case history
        case presence
        case safety
    }

    let id: Int
    let title: String
    let message: String
    let visualKind: VisualKind

    var requiresAgreement: Bool {
        visualKind == .safety
    }

    var visualHeight: CGFloat {
        requiresAgreement ? 142 : 260
    }

    static let defaults = [
        OnboardingPage(
            id: 0,
            title: "Close other apps controlling your mug",
            message: "Your Ember Mug can only listen to one app at a time. Before using Swiftea for macOS, hard close anything else controlling it — on any device.",
            visualKind: .oneDevice
        ),
        OnboardingPage(
            id: 1,
            title: "Set your temperature",
            message: "Choose your preferred temperature. Swiftea handles the Bluetooth connection in the background.",
            visualKind: .heat
        ),
        OnboardingPage(
            id: 2,
            title: "Track the day",
            message: "See recent battery and temperature history.",
            visualKind: .history
        ),
        OnboardingPage(
            id: 3,
            title: "Keep it nearby",
            message: "Use the Dock, the menu bar, or both, depending on how you like Swiftea to live on your Mac.",
            visualKind: .presence
        ),
        OnboardingPage(
            id: 4,
            title: "Before you use Swiftea",
            message: "Ember mugs contain heating elements and should never be left unsupervised. You’re responsible for monitoring your mug and using it safely while Swiftea is connected.",
            visualKind: .safety
        )
    ]
}

private struct OnboardingPageCard: View {
    let page: OnboardingPage
    @Binding var hasReviewedLegalDocuments: Bool
    @Binding var hasAcceptedTermsOfUse: Bool
    @Binding var hasAcceptedSafetyNotice: Bool

    var body: some View {
        Group {
            if page.requiresAgreement {
                OnboardingLegalAgreementPage(
                    title: page.title,
                    warning: page.message,
                    hasReviewedLegalDocuments: $hasReviewedLegalDocuments,
                    hasAcceptedTermsOfUse: $hasAcceptedTermsOfUse,
                    hasAcceptedSafetyNotice: $hasAcceptedSafetyNotice
                )
            } else {
                standardPage
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var standardPage: some View {
        VStack(spacing: 22) {
            OnboardingVisual(kind: page.visualKind)
                .frame(height: page.visualHeight)

            VStack(spacing: 8) {
                Text(page.title)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text(page.message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(maxWidth: 360)
            }
        }
    }
}

private struct OnboardingLegalAgreementPage: View {
    let title: String
    let warning: String
    @Binding var hasReviewedLegalDocuments: Bool
    @Binding var hasAcceptedTermsOfUse: Bool
    @Binding var hasAcceptedSafetyNotice: Bool

    var body: some View {
        VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .swifteaSymbolStyle(SwifteaSymbolColor.orange)

                    Text(title)
                        .font(.title3.weight(.semibold))
                }

                Text(warning)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(1)
                    .frame(maxWidth: 418, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 418, alignment: .leading)

            Text("Read these Terms of Use and Safety Notice before using the app")
                .font(.callout.weight(.medium))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: 418, alignment: .leading)
                .padding(.top, 8)

            OnboardingLegalReader(hasReachedEnd: $hasReviewedLegalDocuments)
                .frame(maxHeight: .infinity)
                .layoutPriority(1)

            VStack(alignment: .leading, spacing: 5) {
                Toggle(isOn: $hasAcceptedTermsOfUse) {
                    Text("I have read, understand and agree to the \(Text("Terms of Use").bold())")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .toggleStyle(.checkbox)
                .font(.callout)
                .disabled(!hasReviewedLegalDocuments)

                Toggle(isOn: $hasAcceptedSafetyNotice) {
                    Text("I have read, understand and agree to the \(Text("Safety Notice").bold())")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .toggleStyle(.checkbox)
                .font(.callout)
                .disabled(!hasReviewedLegalDocuments)
            }
            .frame(maxWidth: 418, alignment: .leading)
        }
    }
}

private struct OnboardingLegalReader: View {
    @Binding var hasReachedEnd: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                embeddedDocument(SwifteaLegalDocuments.termsOfUse)

                Divider()

                embeddedDocument(SwifteaLegalDocuments.safetyNotice)
            }
            .padding(14)
            .textSelection(.enabled)
        }
        .scrollIndicators(.automatic)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.visibleRect.maxY >= geometry.contentSize.height - 8
        } action: { _, reachedEnd in
            if reachedEnd {
                hasReachedEnd = true
            }
        }
        .accessibilityLabel("Terms of Use and Safety Notice")
    }

    private func embeddedDocument(_ document: SwifteaLegalDocument) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(document.title)
                    .font(.headline)

                Text(document.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text(document.metadata)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            ForEach(document.sections) { section in
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.title)
                        .font(.subheadline.weight(.semibold))

                    Text(section.body)
                        .font(.callout)
                        .lineSpacing(2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct OnboardingVisual: View {
    let kind: OnboardingPage.VisualKind

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.08), radius: 18, y: 8)

            switch kind {
            case .oneDevice:
                OneDeviceVisual()
            case .heat:
                HeatVisual()
            case .history:
                HistoryVisual()
            case .presence:
                PresenceVisual()
            case .safety:
                SafetyVisual()
            }
        }
        .padding(.horizontal, 18)
    }
}

private struct OneDeviceVisual: View {
    var body: some View {
        Image(systemName: "iphone.slash")
            .font(.system(size: 102, weight: .regular))
            .swifteaSymbolStyle(SwifteaSymbolColor.muted)
    }
}

private struct HeatVisual: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "thermometer.medium")
                .font(.system(size: 62, weight: .medium))
                .swifteaSymbolStyle(SwifteaSymbolColor.orange)

            HStack(spacing: 14) {
                Text("−")
                Text("55°C")
                    .fontWeight(.semibold)
                Text("+")
            }
            .font(.title3)
            .padding(.horizontal, 22)
            .padding(.vertical, 9)
            .background(.quaternary, in: Capsule())
        }
    }
}

private struct HistoryVisual: View {
    @State private var selectedMetric = OnboardingHistoryMetric.battery

    var body: some View {
        VStack(spacing: 8) {
            Picker("History metric", selection: $selectedMetric) {
                ForEach(OnboardingHistoryMetric.allCases) { metric in
                    Text(metric.title)
                        .tag(metric)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.mini)
            .frame(width: 168)

            OnboardingHistoryChart(metric: selectedMetric)
                .frame(width: 300, height: 150)
        }
    }
}

private struct PresenceVisual: View {
    var body: some View {
        HStack(spacing: 26) {
            PresenceOption(symbolName: "dock.rectangle", title: "Dock")
            PresenceOption(symbolName: "menubar.rectangle", title: "Menu Bar")
            PresenceOption(symbolName: "menubar.dock.rectangle", title: "Both")
        }
    }
}

private struct PresenceOption: View {
    let symbolName: String
    let title: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbolName)
                .font(.system(size: 42, weight: .regular))
                .swifteaSymbolStyle(SwifteaSymbolColor.blue)
                .frame(height: 54)

            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(width: 90)
    }
}

private struct SafetyVisual: View {
    var body: some View {
        Image(systemName: "exclamationmark.shield.fill")
            .font(.system(size: 70, weight: .regular))
            .swifteaSymbolStyle(SwifteaSymbolColor.orange)
    }
}

private enum OnboardingHistoryMetric: String, CaseIterable, Identifiable {
    case battery
    case temperature

    var id: Self { self }

    var title: String {
        switch self {
        case .battery:
            "Battery"
        case .temperature:
            "Temperature"
        }
    }

    var color: Color {
        switch self {
        case .battery:
            .green
        case .temperature:
            .orange
        }
    }

    var yLabels: [String] {
        switch self {
        case .battery:
            ["100%", "60%", "20%"]
        case .temperature:
            ["70°C", "50°C", "30°C"]
        }
    }
}

private struct OnboardingHistoryChart: View {
    let metric: OnboardingHistoryMetric

    private let xLabels = ["9:00", "9:15", "9:30", "9:45"]

    var body: some View {
        GeometryReader { geometry in
            let plot = CGRect(
                x: 42,
                y: 8,
                width: max(geometry.size.width - 50, 1),
                height: max(geometry.size.height - 34, 1)
            )

            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    drawGrid(in: &context, plot: plot)
                    drawLine(in: &context, plot: plot)
                }

                ForEach(Array(metric.yLabels.enumerated()), id: \.offset) { index, label in
                    Text(label)
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                        .position(x: 18, y: yPosition(for: index, plot: plot))
                }

                ForEach(Array(xLabels.enumerated()), id: \.offset) { index, label in
                    Text(label)
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 42)
                        .position(x: xPosition(for: index, plot: plot), y: plot.maxY + 14)
                }
            }
        }
    }

    private func drawGrid(in context: inout GraphicsContext, plot: CGRect) {
        var grid = Path()

        for index in 0..<metric.yLabels.count {
            let y = yPosition(for: index, plot: plot)
            grid.move(to: CGPoint(x: plot.minX, y: y))
            grid.addLine(to: CGPoint(x: plot.maxX, y: y))
        }

        for index in 0..<xLabels.count {
            let x = xPosition(for: index, plot: plot)
            grid.move(to: CGPoint(x: x, y: plot.minY))
            grid.addLine(to: CGPoint(x: x, y: plot.maxY))
        }

        context.stroke(grid, with: .color(.secondary.opacity(0.2)), lineWidth: 0.6)
    }

    private func drawLine(in context: inout GraphicsContext, plot: CGRect) {
        let normalizedPoints: [CGPoint]
        switch metric {
        case .battery:
            normalizedPoints = [
                CGPoint(x: 0.02, y: 0.82),
                CGPoint(x: 0.22, y: 0.72),
                CGPoint(x: 0.43, y: 0.60),
                CGPoint(x: 0.64, y: 0.44),
                CGPoint(x: 0.82, y: 0.32),
                CGPoint(x: 0.98, y: 0.24)
            ]
        case .temperature:
            normalizedPoints = [
                CGPoint(x: 0.02, y: 0.86),
                CGPoint(x: 0.20, y: 0.52),
                CGPoint(x: 0.38, y: 0.30),
                CGPoint(x: 0.58, y: 0.26),
                CGPoint(x: 0.78, y: 0.26),
                CGPoint(x: 0.98, y: 0.26)
            ]
        }

        var line = Path()
        for (index, point) in normalizedPoints.enumerated() {
            let mapped = CGPoint(
                x: plot.minX + point.x * plot.width,
                y: plot.minY + point.y * plot.height
            )

            if index == 0 {
                line.move(to: mapped)
            } else {
                line.addLine(to: mapped)
            }
        }

        context.stroke(
            line,
            with: .color(metric.color),
            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
        )
    }

    private func xPosition(for index: Int, plot: CGRect) -> CGFloat {
        guard xLabels.count > 1 else { return plot.midX }
        return plot.minX + CGFloat(index) / CGFloat(xLabels.count - 1) * plot.width
    }

    private func yPosition(for index: Int, plot: CGRect) -> CGFloat {
        guard metric.yLabels.count > 1 else { return plot.midY }
        return plot.minY + CGFloat(index) / CGFloat(metric.yLabels.count - 1) * plot.height
    }
}

private struct PageNavigationControl: View {
    let pageCount: Int
    let selectedIndex: Int
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            navigationButton(systemName: "chevron.left", label: "Previous page", action: onPrevious)
                .disabled(selectedIndex == 0)

            HStack(spacing: 7) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Capsule()
                        .fill(index == selectedIndex ? Color.primary.opacity(0.72) : Color.secondary.opacity(0.28))
                        .frame(width: index == selectedIndex ? 18 : 6, height: 6)
                        .animation(.snappy(duration: 0.2), value: selectedIndex)
                }
            }

            navigationButton(systemName: "chevron.right", label: "Next page", action: onNext)
                .disabled(selectedIndex == pageCount - 1)
        }
        .accessibilityLabel("Page \(selectedIndex + 1) of \(pageCount)")
    }

    private func navigationButton(
        systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .swifteaSymbolStyle()
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
    }
}
