import Foundation

enum MugHistoryEventKind: String, Codable, Sendable {
    case appSessionStarted
    case connected
    case disconnected
    case reading
    case heatingChanged
    case batteryRecalibrated
}

struct MugHistoryEvent: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let mugIdentifier: String?
    let appSessionID: UUID
    let kind: MugHistoryEventKind
    let batteryPercent: Int?
    let temperatureCelsius: Double?
    let isHeatingOn: Bool?
    let isConnected: Bool

    init(
        id: UUID = UUID(),
        timestamp: Date,
        mugIdentifier: String?,
        appSessionID: UUID,
        kind: MugHistoryEventKind,
        batteryPercent: Int?,
        temperatureCelsius: Double?,
        isHeatingOn: Bool?,
        isConnected: Bool
    ) {
        self.id = id
        self.timestamp = timestamp
        self.mugIdentifier = mugIdentifier
        self.appSessionID = appSessionID
        self.kind = kind
        self.batteryPercent = batteryPercent
        self.temperatureCelsius = temperatureCelsius
        self.isHeatingOn = isHeatingOn
        self.isConnected = isConnected
    }
}

enum MugHistoryMetric: String, CaseIterable, Identifiable {
    case battery
    case temperature

    var id: String { rawValue }

    var title: String {
        switch self {
        case .battery:
            "Battery"
        case .temperature:
            "Temperature"
        }
    }
}

struct MugHistoryChartPoint: Equatable, Identifiable {
    let id: String
    let timestamp: Date
    let value: Double
}

struct MugHistoryChartSegment: Equatable, Identifiable {
    let id: String
    let points: [MugHistoryChartPoint]
}

enum MugHistoryRetention {
    static let duration: TimeInterval = 30 * 24 * 60 * 60

    static func pruned(_ events: [MugHistoryEvent], now: Date = Date()) -> [MugHistoryEvent] {
        let cutoff = now.addingTimeInterval(-duration)
        return events
            .filter { $0.timestamp >= cutoff }
            .sorted { $0.timestamp < $1.timestamp }
    }
}
