import Foundation

protocol MugHistoryStoring: Sendable {
    func loadEvents() async throws -> [MugHistoryEvent]
    func append(_ event: MugHistoryEvent) async throws
    func replaceEvents(_ events: [MugHistoryEvent]) async throws
}

actor MugHistoryFileStore: MugHistoryStoring {
    static let shared = MugHistoryFileStore()

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var appendCountSincePrune = 0

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func loadEvents() async throws -> [MugHistoryEvent] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }

        let data = try Data(contentsOf: fileURL)
        guard let contents = String(data: data, encoding: .utf8) else { return [] }

        let events = contents
            .split(separator: "\n")
            .compactMap { line -> MugHistoryEvent? in
                guard let data = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(MugHistoryEvent.self, from: data)
            }

        let prunedEvents = MugHistoryRetention.pruned(events)
        if prunedEvents.count != events.count {
            try await replaceEvents(prunedEvents)
        }

        return prunedEvents
    }

    func append(_ event: MugHistoryEvent) async throws {
        try createParentDirectoryIfNeeded()

        var line = try encoder.encode(event)
        line.append(0x0A)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer {
                try? handle.close()
            }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: fileURL, options: .atomic)
        }

        appendCountSincePrune += 1
        if appendCountSincePrune >= 100 {
            appendCountSincePrune = 0
            let events = try await loadEvents()
            try await replaceEvents(events)
        }
    }

    func replaceEvents(_ events: [MugHistoryEvent]) async throws {
        try createParentDirectoryIfNeeded()

        let sortedEvents = events.sorted { $0.timestamp < $1.timestamp }
        var data = Data()
        for event in sortedEvents {
            data.append(try encoder.encode(event))
            data.append(0x0A)
        }

        try data.write(to: fileURL, options: .atomic)
    }

    private static func defaultFileURL() -> URL {
        let applicationSupportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]

        return applicationSupportDirectory
            .appendingPathComponent("Swiftea", isDirectory: true)
            .appendingPathComponent("mug-history-v1.jsonl", isDirectory: false)
    }

    private func createParentDirectoryIfNeeded() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }
}

actor InMemoryMugHistoryStore: MugHistoryStoring {
    private var events: [MugHistoryEvent]

    init(events: [MugHistoryEvent] = []) {
        self.events = MugHistoryRetention.pruned(events)
    }

    func loadEvents() async throws -> [MugHistoryEvent] {
        events
    }

    func append(_ event: MugHistoryEvent) async throws {
        events.append(event)
        events = MugHistoryRetention.pruned(events, now: event.timestamp)
    }

    func replaceEvents(_ events: [MugHistoryEvent]) async throws {
        self.events = MugHistoryRetention.pruned(events)
    }
}
