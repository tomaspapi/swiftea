import Foundation

enum MugHistoryEventKind: String, Codable, Sendable {
    case appSessionStarted
    case connected
    case disconnected
    case reading
    case heatingChanged
    case batteryRecalibrated
    case recordingGap
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

enum MugHistoryChartSelection: String, CaseIterable, Identifiable {
    case battery
    case temperature
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .battery:
            "Battery"
        case .temperature:
            "Temperature"
        case .both:
            "Both"
        }
    }

    var metrics: [MugHistoryMetric] {
        switch self {
        case .battery:
            [.battery]
        case .temperature:
            [.temperature]
        case .both:
            [.battery, .temperature]
        }
    }

    var leadingMetric: MugHistoryMetric {
        switch self {
        case .temperature:
            .temperature
        case .battery, .both:
            .battery
        }
    }

    var trailingMetric: MugHistoryMetric? {
        self == .both ? .temperature : nil
    }
}

enum MugHistoryChartScale {
    static func normalizedFraction(for value: Double, in domain: ClosedRange<Double>) -> Double {
        let valueRange = max(domain.upperBound - domain.lowerBound, 1)
        return min(max((value - domain.lowerBound) / valueRange, 0), 1)
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

struct MugHistoryLimits: Sendable {
    static let standard = MugHistoryLimits()
    var maximumEvents = 500_000
    var maximumEventsPerMug = 160_000
    var maximumFileBytes = 128_000_000
    var maximumRecordBytes = 4_096
}

struct MugHistoryRecordingBudget {
    static let interval: TimeInterval = 5
    private var tokens = 8.0
    private var lastRefillAt: Date?
    private var lastRecordedAt: Date?

    mutating func admit(kind: MugHistoryEventKind, now: Date) -> Bool {
        if let lastRefillAt {
            tokens = min(8, tokens + max(0, now.timeIntervalSince(lastRefillAt)) / Self.interval)
        }
        lastRefillAt = max(lastRefillAt ?? now, now)
        if kind == .reading, let lastRecordedAt, now.timeIntervalSince(lastRecordedAt) < Self.interval {
            return false
        }
        guard tokens >= 1 else { return false }
        tokens -= 1
        lastRecordedAt = now
        return true
    }
}

struct MugHistoryWriteBuffer {
    static let maximumCount = 256
    private(set) var events: [MugHistoryEvent] = []
    private(set) var needsReplacement = false
    var isEmpty: Bool { events.isEmpty && !needsReplacement }

    mutating func enqueue(_ event: MugHistoryEvent) {
        guard !needsReplacement else { return }
        guard events.count < Self.maximumCount else {
            events.removeAll(keepingCapacity: true)
            needsReplacement = true
            return
        }
        events.append(event)
    }

    mutating func takeReplacementRequest() -> Bool {
        let result = needsReplacement
        needsReplacement = false
        return result
    }

    mutating func takeBatch() -> [MugHistoryEvent] {
        let batch = Array(events.prefix(64))
        events.removeFirst(batch.count)
        return batch
    }
}

enum MugHistoryRetention {
    static let duration: TimeInterval = 30 * 24 * 60 * 60

    static func pruned(
        _ events: [MugHistoryEvent],
        now: Date = Date(),
        limits: MugHistoryLimits = .standard
    ) -> [MugHistoryEvent] {
        let cutoff = now.addingTimeInterval(-duration)
        let sorted = events
            .filter { $0.timestamp >= cutoff }
            .sorted { $0.timestamp < $1.timestamp }
        var counts: [String?: Int] = [:]
        var result: [MugHistoryEvent] = []
        for event in sorted.reversed() {
            guard result.count < limits.maximumEvents else { break }
            guard counts[event.mugIdentifier, default: 0] < limits.maximumEventsPerMug else { continue }
            counts[event.mugIdentifier, default: 0] += 1
            result.append(event)
        }
        return result.reversed()
    }
}
