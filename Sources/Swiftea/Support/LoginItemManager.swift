import ServiceManagement

enum LoginItemRegistrationStatus: Equatable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable
}

@MainActor
protocol LoginItemManaging: AnyObject {
    var status: LoginItemRegistrationStatus { get }

    func setEnabled(_ isEnabled: Bool) throws
    func openSystemSettings()
}

@MainActor
final class NativeLoginItemManager: LoginItemManaging {
    static let shared = NativeLoginItemManager()

    private let service = SMAppService.mainApp

    private init() {}

    var status: LoginItemRegistrationStatus {
        switch service.status {
        case .notRegistered:
            .disabled
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .unavailable
        @unknown default:
            .unavailable
        }
    }

    func setEnabled(_ isEnabled: Bool) throws {
        if isEnabled {
            guard service.status != .enabled else { return }
            try service.register()
        } else {
            guard service.status != .notRegistered else { return }
            try service.unregister()
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

@MainActor
final class NoOpLoginItemManager: LoginItemManaging {
    static let shared = NoOpLoginItemManager()

    private init() {}

    var status: LoginItemRegistrationStatus { .disabled }

    func setEnabled(_ isEnabled: Bool) throws {}
    func openSystemSettings() {}
}
