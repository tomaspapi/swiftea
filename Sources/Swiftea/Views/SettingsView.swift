import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    let updateController: UpdateController
    @Environment(\.openWindow) private var openWindow
    @State private var selectedSection = SettingsSection.general
    @State private var paneHeights: [SettingsSection: CGFloat] = [:]

    var body: some View {
        TabView(selection: $selectedSection) {
            Tab(SettingsSection.general.title, systemImage: SettingsSection.general.symbolName, value: SettingsSection.general) {
                SettingsPane(section: .general) {
                    generalSettings
                }
            }

            Tab(SettingsSection.notifications.title, systemImage: SettingsSection.notifications.symbolName, value: SettingsSection.notifications) {
                SettingsPane(section: .notifications) {
                    notificationSettings
                }
            }

            Tab(SettingsSection.updates.title, systemImage: SettingsSection.updates.symbolName, value: SettingsSection.updates) {
                SettingsPane(section: .updates) {
                    UpdatesSettingsContent(updateController: updateController)
                }
            }

            Tab(SettingsSection.about.title, systemImage: SettingsSection.about.symbolName, value: SettingsSection.about) {
                SettingsPane(section: .about) {
                    aboutSettings
                }
            }
        }
        .frame(width: 540, alignment: .top)
        .frame(height: selectedPaneHeight, alignment: .top)
        .onPreferenceChange(SettingsPaneHeightPreferenceKey.self) { heights in
            for (section, height) in heights where height > 0 {
                paneHeights[section] = ceil(height)
            }
        }
        .background {
            Color(nsColor: .windowBackgroundColor)
            SettingsWindowFitter(selectedSection: selectedSection, selectedPaneHeight: selectedPaneHeight)
        }
        .alert("Notifications are turned off in macOS", isPresented: $model.isPresentingNotificationPermissionAlert) {
            Button("Open System Settings") {
                model.openNotificationSettings()
            }

            Button("OK", role: .cancel) {}
        } message: {
            Text(model.notificationPermissionAlertMessage)
        }
    }

    private var selectedPaneHeight: CGFloat? {
        paneHeights[selectedSection]
    }

    @ViewBuilder
    private var generalSettings: some View {
        Section("Appearance") {
            LabeledContent("Theme") {
                themeMenu
            }

            LabeledContent("Chart Timeframe") {
                timeframeMenu
            }
        }

        Section("Temperature") {
            LabeledContent("Units") {
                unitsMenu
            }
        }

        Section("Presence") {
            LabeledContent("Show Swiftea in") {
                appLocationMenu
            }

            LabeledContent("After closing window") {
                windowCloseBehaviorMenu
            }
        }
    }

    @ViewBuilder
    private var notificationSettings: some View {
        Section("Notifications") {
            LabeledContent("Mug reaches target temperature") {
                Toggle("", isOn: notificationToggleBinding)
                    .labelsHidden()
                    .disabled(model.isRequestingNotificationPermission)
            }

            LabeledContent("Battery charges to 100%") {
                Toggle("", isOn: batteryFullyChargedNotificationToggleBinding)
                    .labelsHidden()
                    .disabled(model.isRequestingNotificationPermission)
            }

            LabeledContent("Battery discharges to 0%") {
                Toggle("", isOn: batteryFullyDischargedNotificationToggleBinding)
                    .labelsHidden()
                    .disabled(model.isRequestingNotificationPermission)
            }
        }
    }

    @ViewBuilder
    private var aboutSettings: some View {
        Section("About") {
            LabeledContent("Current version") {
                Text(updateController.currentVersionDescription)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            LabeledContent("License") {
                Button("Zero-Clause BSD (0BSD)") {
                    openWindow(id: "license")
                }
                .buttonStyle(.link)
            }

            LabeledContent("Acknowledgements") {
                Button("Open") {
                    openWindow(id: "acknowledgements")
                }
                .buttonStyle(.link)
            }

            LabeledContent("Source code") {
                Link(destination: SettingsExternalLinks.sourceCode) {
                    Text("GitHub ↗")
                }
            }

            LabeledContent("Developer") {
                Text("Tomás Papi")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var notificationToggleBinding: Binding<Bool> {
        Binding(
            get: {
                model.targetTemperatureNotificationsEnabled
            },
            set: { isEnabled in
                model.setTargetTemperatureNotificationsEnabled(isEnabled)
            }
        )
    }

    private var batteryFullyChargedNotificationToggleBinding: Binding<Bool> {
        Binding(
            get: {
                model.batteryFullyChargedNotificationsEnabled
            },
            set: { isEnabled in
                model.setBatteryFullyChargedNotificationsEnabled(isEnabled)
            }
        )
    }

    private var batteryFullyDischargedNotificationToggleBinding: Binding<Bool> {
        Binding(
            get: {
                model.batteryFullyDischargedNotificationsEnabled
            },
            set: { isEnabled in
                model.setBatteryFullyDischargedNotificationsEnabled(isEnabled)
            }
        )
    }

    private var themeMenu: some View {
        Menu {
            ForEach(AppModel.ThemePreference.allCases) { preference in
                Button {
                    model.themePreference = preference
                } label: {
                    ThemePreferenceLabel(preference: preference)
                }
            }
        } label: {
            ThemePreferenceLabel(preference: model.themePreference)
                .frame(minWidth: 132, alignment: .leading)
        }
    }

    private var unitsMenu: some View {
        Menu {
            ForEach(AppModel.TemperatureUnitPreference.allCases) { preference in
                Button {
                    model.temperatureUnitPreference = preference
                } label: {
                    Text(preference.title)
                }
            }
        } label: {
            Text(model.temperatureUnitPreference.title)
                .frame(minWidth: 132, alignment: .leading)
        }
    }

    private var timeframeMenu: some View {
        Menu {
            ForEach(AppModel.ChartTimeframePreference.allCases) { preference in
                Button {
                    model.chartTimeframePreference = preference
                } label: {
                    Text(preference.title)
                }
            }
        } label: {
            Text(model.chartTimeframePreference.title)
                .frame(minWidth: 132, alignment: .leading)
        }
    }

    private var appLocationMenu: some View {
        Menu {
            ForEach(AppModel.AppLocationPreference.allCases) { preference in
                Button {
                    model.appLocationPreference = preference
                } label: {
                    Text(preference.title)
                }
            }
        } label: {
            Text(model.appLocationPreference.title)
                .frame(minWidth: 158, alignment: .leading)
        }
    }

    private var windowCloseBehaviorMenu: some View {
        Menu {
            Button {
                model.keepsRunningWhenWindowClosed = true
            } label: {
                Text("Run in background")
            }

            Button {
                model.keepsRunningWhenWindowClosed = false
            } label: {
                Text("Quit app")
            }
        } label: {
            Text(model.keepsRunningWhenWindowClosed ? "Run in background" : "Quit app")
                .frame(minWidth: 158, alignment: .leading)
        }
    }
}

private enum SettingsExternalLinks {
    static let sourceCode = URL(string: "https://github.com/tomaspapi/swiftea")!
}

private struct SettingsPane<Content: View>: View {
    let section: SettingsSection
    let content: Content

    init(section: SettingsSection, @ViewBuilder content: () -> Content) {
        self.section = section
        self.content = content()
    }

    var body: some View {
        Form {
            content
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .scenePadding()
        .frame(width: 540, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: SettingsPaneHeightPreferenceKey.self, value: [section: proxy.size.height])
            }
        }
    }
}

private struct SettingsPaneHeightPreferenceKey: PreferenceKey {
    static let defaultValue: [SettingsSection: CGFloat] = [:]

    static func reduce(value: inout [SettingsSection: CGFloat], nextValue: () -> [SettingsSection: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct UpdatesSettingsContent: View {
    @StateObject private var viewModel: UpdateSettingsViewModel

    init(updateController: UpdateController) {
        _viewModel = StateObject(wrappedValue: UpdateSettingsViewModel(updateController: updateController))
    }

    var body: some View {
        Section("Updates") {
            LabeledContent("Current version") {
                Text(viewModel.currentVersionDescription)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            LabeledContent("Check for updates automatically") {
                Toggle("", isOn: Binding(
                    get: {
                        viewModel.automaticallyChecksForUpdates
                    },
                    set: { isEnabled in
                        viewModel.setAutomaticallyChecksForUpdates(isEnabled)
                    }
                ))
                .labelsHidden()
            }

            LabeledContent("Check manually") {
                Button("Check for Updates…") {
                    viewModel.checkForUpdates()
                }
                .disabled(!viewModel.canCheckForUpdates)
                .buttonStyle(.link)
                .help(viewModel.canCheckForUpdates ? "Check for updates now." : "Update checks are available in configured release builds.")
            }
        }
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case notifications
    case updates
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general:
            "General"
        case .notifications:
            "Notifications"
        case .updates:
            "Updates"
        case .about:
            "About"
        }
    }

    var symbolName: String {
        switch self {
        case .general:
            "gearshape"
        case .notifications:
            "bell"
        case .updates:
            "arrow.triangle.2.circlepath"
        case .about:
            "info.circle"
        }
    }
}

private struct ThemePreferenceLabel: View {
    let preference: AppModel.ThemePreference

    var body: some View {
        Label {
            Text(preference.title)
        } icon: {
            Image(systemName: preference.symbolName)
                .font(.system(size: 13, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .frame(width: 18, alignment: .center)
        }
        .font(.body)
    }
}

private struct SettingsWindowFitter: NSViewRepresentable {
    let selectedSection: SettingsSection
    let selectedPaneHeight: CGFloat?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        fitWindow(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        fitWindow(from: nsView)
    }

    private func fitWindow(from view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    guard view.window != nil else { return }
                    fitWindow(from: view)
                }
                return
            }

            window.backgroundColor = .windowBackgroundColor
            window.contentView?.layoutSubtreeIfNeeded()
            let fittingSize = window.contentView?.fittingSize ?? .zero
            guard fittingSize.height > 0 else { return }

            let screenFrame = (window.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 720)
            let targetContentHeight = min(ceil(fittingSize.height), screenFrame.height - 96)
            let currentContentSize = window.contentRect(forFrameRect: window.frame).size
            guard abs(currentContentSize.height - targetContentHeight) > 1 else { return }

            let targetContentSize = NSSize(width: currentContentSize.width, height: targetContentHeight)
            let targetFrameSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: targetContentSize)).size
            var targetFrame = window.frame
            targetFrame.origin.y = min(window.frame.maxY - targetFrameSize.height, screenFrame.maxY - targetFrameSize.height)
            targetFrame.origin.y = max(targetFrame.origin.y, screenFrame.minY)
            targetFrame.size = targetFrameSize

            window.setFrame(targetFrame, display: true)
        }
    }
}

#Preview {
    SettingsView(model: AppModel.previewConnected(), updateController: UpdateController())
}
