import AppKit
import SwiftUI

@main
struct SwifteaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let updateController = UpdateController()
    @State private var model = AppModel.launchModel()

    var body: some Scene {
        Window("Swiftea", id: "main") {
            ContentView(model: model)
                .background { SwifteaMainWindowMarker(appDelegate: appDelegate) }
                .preferredColorScheme(model.themePreference.colorScheme)
                .background {
                    AppAppearanceSynchronizer(themePreference: model.themePreference)
                    AppLocationPreferenceSynchronizer(
                        preference: model.appLocationPreference,
                        appDelegate: appDelegate
                    )
                    OnboardingPresentationTrigger(model: model)
                }
                .onAppear {
                    appDelegate.configure(model: model)
                }
                .frame(minWidth: 550, idealWidth: 550, maxWidth: 550, minHeight: 551, idealHeight: 551, maxHeight: 551)
        }
        .defaultSize(width: 550, height: 551)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandGroup(after: .appInfo) {
                CheckForUpdatesCommand(updater: updateController.updater)
            }
        }

        MenuBarExtra(isInserted: menuBarExtraBinding) {
            MenuBarStatusPanel(model: model, appDelegate: appDelegate)
                .preferredColorScheme(model.themePreference.colorScheme)
        } label: {
            MenuBarStatusLabel(status: model.menuBarStatusTemperatureLabel)
        }
        .menuBarExtraStyle(.window)

        Window("Discovery", id: "discovery") {
            DiscoveryWindowView(model: model)
                .preferredColorScheme(model.themePreference.colorScheme)
                .background {
                    AppAppearanceSynchronizer(themePreference: model.themePreference)
                }
        }
        .defaultSize(width: 420, height: 580)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)

        Window("Swiftea Acknowledgements", id: "acknowledgements") {
            AcknowledgementsView()
                .preferredColorScheme(model.themePreference.colorScheme)
                .background {
                    AppAppearanceSynchronizer(themePreference: model.themePreference)
                }
        }
        .defaultSize(width: 520, height: 400)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)

        Window("Swiftea License", id: "license") {
            LicenseView()
                .preferredColorScheme(model.themePreference.colorScheme)
                .background {
                    AppAppearanceSynchronizer(themePreference: model.themePreference)
                }
        }
        .defaultSize(width: 520, height: 360)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)

        Window("Swiftea Terms of Use", id: "terms-of-use") {
            LegalDocumentView(document: SwifteaLegalDocuments.termsOfUse)
                .preferredColorScheme(model.themePreference.colorScheme)
                .background {
                    AppAppearanceSynchronizer(themePreference: model.themePreference)
                }
        }
        .defaultSize(width: 560, height: 620)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)

        Window("Swiftea Safety Notice", id: "safety-notice") {
            LegalDocumentView(document: SwifteaLegalDocuments.safetyNotice)
                .preferredColorScheme(model.themePreference.colorScheme)
                .background {
                    AppAppearanceSynchronizer(themePreference: model.themePreference)
                }
        }
        .defaultSize(width: 560, height: 520)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)

        Window("Swiftea Privacy Policy", id: "privacy-policy") {
            LegalDocumentView(document: SwifteaLegalDocuments.privacyPolicy)
                .preferredColorScheme(model.themePreference.colorScheme)
                .background {
                    AppAppearanceSynchronizer(themePreference: model.themePreference)
                }
        }
        .defaultSize(width: 560, height: 620)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)

        Window("What’s New in Swiftea", id: "whats-new") {
            UpdateChangelogView(releases: model.updateChangelogReleases)
                .preferredColorScheme(model.themePreference.colorScheme)
                .background {
                    AppAppearanceSynchronizer(themePreference: model.themePreference)
                }
        }
        .defaultSize(width: 480, height: 260)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)

        Window("Welcome to Swiftea", id: "welcome") {
            OnboardingView(model: model)
                .preferredColorScheme(model.themePreference.colorScheme)
                .background {
                    AppAppearanceSynchronizer(themePreference: model.themePreference)
                }
        }
        .defaultSize(width: 500, height: 500)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView(model: model, updateController: updateController)
                .preferredColorScheme(model.themePreference.colorScheme)
                .background {
                    AppAppearanceSynchronizer(themePreference: model.themePreference)
                    AppLocationPreferenceSynchronizer(
                        preference: model.appLocationPreference,
                        appDelegate: appDelegate
                    )
                }
        }
    }

    private var menuBarExtraBinding: Binding<Bool> {
        Binding(
            get: {
                model.appLocationPreference.includesMenuBar
            },
            set: { isInserted in
                guard !isInserted else { return }

                switch model.appLocationPreference {
                case .dockAndMenuBar:
                    model.appLocationPreference = .dock
                case .menuBar:
                    model.appLocationPreference = .dock
                case .dock:
                    break
                }
            }
        )
    }
}

private struct OnboardingPresentationTrigger: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .task {
                guard model.consumeOnboardingPresentation() else { return }

                openWindow(id: "welcome")
                NSApp.activate(ignoringOtherApps: true)
            }
    }
}

private struct AppLocationPreferenceSynchronizer: NSViewRepresentable {
    let preference: AppModel.AppLocationPreference
    let appDelegate: AppDelegate

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        notifyDelegate()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        notifyDelegate()
    }

    private func notifyDelegate() {
        DispatchQueue.main.async {
            appDelegate.updateAppLocationPreference(preference)
        }
    }
}

private struct MenuBarStatusLabel: View {
    let status: String?

    var body: some View {
        if let status {
            HStack(spacing: 3) {
                Image(systemName: "mug.fill")
                    .swifteaSymbolStyle()
                Text(status)
            }
        } else {
            Image(systemName: "mug")
                .swifteaSymbolStyle(SwifteaSymbolColor.muted)
        }
    }
}

private struct MenuBarStatusPanel: View {
    @Bindable var model: AppModel
    let appDelegate: AppDelegate
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    private var heatingBinding: Binding<Bool> {
        Binding(
            get: { !model.isTemperatureControlOff },
            set: {
                model.setTemperatureControlEnabled(
                    $0,
                    emptyMugAlertPresentation: .menuBar
                )
            }
        )
    }

    private var isPresentingEmptyHeatingConfirmation: Bool {
        model.emptyHeatingAlertPresentation == .menuBar
    }

    private var isTargetControlEnabled: Bool {
        model.canAdjustTemperature && !model.isTemperatureControlOff
    }

    private var canDecreaseTargetTemperature: Bool {
        isTargetControlEnabled && model.canDecreaseTargetTemperatureDraft
    }

    private var canIncreaseTargetTemperature: Bool {
        isTargetControlEnabled && model.canIncreaseTargetTemperatureDraft
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let currentMug = model.currentSidebarMug, model.shouldShowMugDashboard {
                panelHeader {
                    mugStatusSection(currentMug: currentMug)
                }

                if isPresentingEmptyHeatingConfirmation {
                    emptyMugHeatingConfirmation
                } else {
                    heatingSection
                }

                Divider()
            } else {
                panelHeader {
                    emptyStateSection
                }
                Divider()
            }

            appActions
        }
        .controlSize(.small)
        .padding(12)
        .frame(width: 226)
    }

    private func panelHeader<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            content()

            Spacer(minLength: 8)

            settingsButton
        }
    }

    private func mugStatusSection(currentMug: AppModel.SidebarMugItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(currentMug.name)
                .font(.headline)
                .lineLimit(1)

            MenuBarMugTelemetryLine(model: model)
        }
    }

    private var heatingSection: some View {
        VStack(spacing: 7) {
            menuBarControlRow {
                Text("Heating")
            } trailing: {
                Toggle("", isOn: heatingBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .disabled(!model.canAdjustTemperature)
            }

            menuBarControlRow {
                Text("Target")
                    .foregroundStyle(model.isTemperatureControlOff ? Color(nsColor: .disabledControlTextColor) : .primary)
            } trailing: {
                TemperatureSegmentedControl(
                    valueLabel: model.targetTemperatureLabel,
                    isEnabled: isTargetControlEnabled,
                    canDecrement: canDecreaseTargetTemperature,
                    canIncrement: canIncreaseTargetTemperature,
                    onDecrement: model.decreaseTemperatureDraft,
                    onIncrement: model.increaseTemperatureDraft
                )
                .controlSize(.mini)
            }
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private var emptyMugHeatingConfirmation: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Mug is empty")
                    .font(.callout.weight(.semibold))

                Text("Turn heating on anyway?")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Spacer(minLength: 0)

                Button("Cancel", role: .cancel) {
                    model.cancelEmptyHeatingAlert()
                }
                .keyboardShortcut(.defaultAction)

                Button("Turn On") {
                    model.confirmEmptyHeatingAlert()
                }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var emptyStateSection: some View {
        Text("No mug connected")
            .font(.headline)
    }

    private var settingsButton: some View {
        Button {
            openSettings()
            NSApp.activate(ignoringOtherApps: true)
        } label: {
            Image(systemName: "gearshape.fill")
                .imageScale(.medium)
                .swifteaSymbolStyle()
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .help("Settings")
        .accessibilityLabel("Settings")
    }

    private var appActions: some View {
        VStack(spacing: 2) {
            MenuBarActionRow("Show Swiftea") {
                MainWindowPresenter.show(
                    appDelegate: appDelegate,
                    openWindow: openWindow
                )
                dismiss()
            }

            MenuBarActionRow("Quit Swiftea") {
                NSApp.terminate(nil)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func menuBarControlRow<Leading: View, Trailing: View>(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 10) {
            leading()

            Spacer(minLength: 8)

            trailing()
        }
        .frame(minHeight: 22)
    }
}

private struct MenuBarMugTelemetryLine: View {
    let model: AppModel

    private let batterySymbolFrame = CGSize(width: 10, height: 14)
    private let batterySymbolFontSize: CGFloat = 10
    private let temperatureLabelReservation = "888°F"

    private var mugStatusSymbolName: String {
        model.isEmpty == true ? "mug" : "thermometer.medium"
    }

    private var mugStatusLabel: String {
        if model.isEmpty == true {
            return "Empty"
        }

        return model.menuBarStatusTemperatureLabel ?? "—"
    }

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 5) {
                Image(systemName: mugStatusSymbolName)
                    .imageScale(.small)
                    .swifteaSymbolStyle(SwifteaSymbolColor.muted)

                ZStack(alignment: .leading) {
                    Text(temperatureLabelReservation)
                        .hidden()

                    Text("Empty")
                        .hidden()

                    Text(mugStatusLabel)
                        .contentTransition(.numericText())
                }
            }

            HStack(spacing: 4) {
                batteryStatusSymbol

                Text(model.batteryLabel)
                    .contentTransition(.numericText())
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var batteryStatusSymbol: some View {
        ZStack {
            if model.isCharging {
                AnimatedStatusSymbol(
                    systemName: "bolt.fill",
                    fontSize: batterySymbolFontSize,
                    weight: .semibold,
                    baseColor: .secondary,
                    softHighlightColor: Color(nsColor: .tertiaryLabelColor),
                    brightHighlightColor: Color(nsColor: .secondaryLabelColor)
                )
            } else {
                Image(systemName: "bolt.slash.fill")
                    .font(.system(size: batterySymbolFontSize, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                    .symbolColorRenderingMode(.flat)
            }
        }
        .frame(width: batterySymbolFrame.width, height: batterySymbolFrame.height, alignment: .center)
        .accessibilityHidden(true)
    }

    private var accessibilityLabel: String {
        let batteryStatus = model.isCharging ? "charging" : "not charging"
        return "\(mugStatusLabel), \(batteryStatus), \(model.batteryLabel) battery"
    }
}

private struct MenuBarActionRow: View {
    let title: String
    let action: () -> Void
    @State private var isHovering = false

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout)
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .background {
            if isHovering {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            }
        }
        .onHover { isHovering = $0 }
    }
}

extension AppModel.ThemePreference {
    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}
