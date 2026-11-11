import Foundation
import Darwin

protocol MugHistoryStoring: Sendable {
    func loadEvents() async throws -> [MugHistoryEvent]
    func append(_ event: MugHistoryEvent) async throws
    func replaceEvents(_ events: [MugHistoryEvent]) async throws
}

enum MugHistoryFileStoreError: Error, Equatable {
    case unsafeParentDirectory(String)
    case unsafeHistoryFile(String)
    case invalidHistoryFileName(String)
    case historySizeLimit
    case oversizedRecord
    case fileOperationFailed(String, Int32)
}

actor MugHistoryFileStore: MugHistoryStoring {
    static let shared = MugHistoryFileStore()

    private let fileURL: URL
    private let parentDirectoryURL: URL
    private let fileName: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let limits: MugHistoryLimits
    private var appendCountSincePrune = 0

    init(fileURL: URL? = nil, limits: MugHistoryLimits = .standard) {
        precondition(limits.maximumEvents > 0 && limits.maximumEventsPerMug > 0)
        precondition(limits.maximumFileBytes > limits.maximumRecordBytes && limits.maximumRecordBytes > 0)
        self.limits = limits
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.parentDirectoryURL = self.fileURL.deletingLastPathComponent()
        self.fileName = self.fileURL.lastPathComponent

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func loadEvents() throws -> [MugHistoryEvent] {
        guard let result = try readHistoryDataIfPresent() else { return [] }
        let data = result.data
        var events: [MugHistoryEvent] = []
        var nextReplacementIndex = 0
        var needsRewrite = result.wasTrimmed
        var lineStart = data.startIndex
        func decodeLine(endingAt end: Int) {
            defer { lineStart = end + 1 }
            guard end > lineStart else { return }
            guard end - lineStart <= limits.maximumRecordBytes,
                  let event = try? decoder.decode(MugHistoryEvent.self, from: data.subdata(in: lineStart ..< end)) else {
                needsRewrite = true
                return
            }
            if events.count < limits.maximumEvents {
                events.append(event)
            } else {
                events[nextReplacementIndex] = event
                nextReplacementIndex = (nextReplacementIndex + 1) % limits.maximumEvents
                needsRewrite = true
            }
        }
        for index in data.indices where data[index] == 0x0A { decodeLine(endingAt: index) }
        if lineStart < data.endIndex { decodeLine(endingAt: data.endIndex) }
        if nextReplacementIndex > 0 {
            events = Array(events[nextReplacementIndex...] + events[..<nextReplacementIndex])
        }
        let prunedEvents = MugHistoryRetention.pruned(events, limits: limits)
        if needsRewrite || prunedEvents.count != events.count {
            try replaceEvents(prunedEvents)
        }

        return prunedEvents
    }

    func append(_ event: MugHistoryEvent) throws {
        var line = try encoder.encode(event)
        guard line.count <= limits.maximumRecordBytes else { throw MugHistoryFileStoreError.oversizedRecord }
        line.append(0x0A)
        do {
            try appendHistoryData(line)
        } catch MugHistoryFileStoreError.historySizeLimit {
            let events = try loadEvents()
            try replaceHistoryData(encodedHistory(events + [event], byteLimit: limits.maximumFileBytes * 9 / 10))
            appendCountSincePrune = 0
            return
        }

        appendCountSincePrune += 1
        if appendCountSincePrune >= 1_000 {
            appendCountSincePrune = 0
            let events = try loadEvents()
            try replaceEvents(events)
        }
    }

    func replaceEvents(_ events: [MugHistoryEvent]) throws {
        try replaceHistoryData(encodedHistory(events, byteLimit: limits.maximumFileBytes))
        appendCountSincePrune = 0
    }

    private func encodedHistory(_ events: [MugHistoryEvent], byteLimit: Int) throws -> Data {
        let retained = MugHistoryRetention.pruned(events, limits: limits)
        var lines: [Data] = []
        var byteCount = 0
        for event in retained.reversed() {
            var line = try encoder.encode(event)
            guard line.count <= limits.maximumRecordBytes else { throw MugHistoryFileStoreError.oversizedRecord }
            line.append(0x0A)
            guard byteCount + line.count <= byteLimit else { break }
            lines.append(line)
            byteCount += line.count
        }
        var data = Data(capacity: byteCount)
        for line in lines.reversed() { data.append(line) }
        return data
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
            at: parentDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    private func readHistoryDataIfPresent() throws -> (data: Data, wasTrimmed: Bool)? {
        guard let parentDescriptor = try openParentDirectory(createIfNeeded: false) else {
            return nil
        }
        defer { closeDescriptor(parentDescriptor) }

        let descriptor = try openHistoryFile(
            relativeTo: parentDescriptor,
            flags: O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC,
            missingIsAllowed: true
        )
        guard let descriptor else { return nil }
        defer { closeDescriptor(descriptor) }

        let fileSize = try validateOpenHistoryFile(descriptor)
        let start = max(0, fileSize - limits.maximumFileBytes)
        guard lseek(descriptor, off_t(start), SEEK_SET) >= 0 else {
            throw MugHistoryFileStoreError.fileOperationFailed("seek history file", errno)
        }
        var data = try readAllData(from: descriptor, maximumBytes: min(fileSize, limits.maximumFileBytes))
        if start > 0 {
            if let newline = data.firstIndex(of: 0x0A) {
                data = data.subdata(in: data.index(after: newline) ..< data.endIndex)
            } else {
                data.removeAll()
            }
        }
        return (data, start > 0)
    }

    private func appendHistoryData(_ data: Data) throws {
        guard let parentDescriptor = try openParentDirectory(createIfNeeded: true) else {
            throw MugHistoryFileStoreError.unsafeParentDirectory(parentDirectoryURL.path)
        }
        defer { closeDescriptor(parentDescriptor) }

        guard
            let descriptor = try openHistoryFile(
                relativeTo: parentDescriptor,
                flags: O_WRONLY | O_CREAT | O_APPEND | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC,
                missingIsAllowed: false
            )
        else {
            throw MugHistoryFileStoreError.fileOperationFailed("open history file", ENOENT)
        }
        defer { closeDescriptor(descriptor) }

        let fileSize = try validateOpenHistoryFile(descriptor)
        guard fileSize <= limits.maximumFileBytes - data.count else {
            throw MugHistoryFileStoreError.historySizeLimit
        }
        try writeAllData(data, to: descriptor)
    }

    private func replaceHistoryData(_ data: Data) throws {
        guard let parentDescriptor = try openParentDirectory(createIfNeeded: true) else {
            throw MugHistoryFileStoreError.unsafeParentDirectory(parentDirectoryURL.path)
        }
        defer { closeDescriptor(parentDescriptor) }

        try validateExistingHistoryFileIfPresent(relativeTo: parentDescriptor)

        let temporaryFileName = ".\(fileName).\(UUID().uuidString).tmp"
        let temporaryDescriptor = try temporaryFileName.withCString { pointer in
            let descriptor = openat(
                parentDescriptor,
                pointer,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                S_IRUSR | S_IWUSR
            )

            guard descriptor >= 0 else {
                throw MugHistoryFileStoreError.fileOperationFailed("create temporary history file", errno)
            }

            return descriptor
        }

        var shouldRemoveTemporaryFile = true
        defer {
            closeDescriptor(temporaryDescriptor)
            if shouldRemoveTemporaryFile {
                temporaryFileName.withCString { pointer in
                    _ = unlinkat(parentDescriptor, pointer, 0)
                }
            }
        }

        try validateOpenHistoryFile(temporaryDescriptor)
        try writeAllData(data, to: temporaryDescriptor)

        try temporaryFileName.withCString { temporaryPointer in
            try fileName.withCString { filePointer in
                guard renameat(parentDescriptor, temporaryPointer, parentDescriptor, filePointer) == 0 else {
                    throw MugHistoryFileStoreError.fileOperationFailed("replace history file", errno)
                }
            }
        }

        shouldRemoveTemporaryFile = false
    }

    private func openParentDirectory(createIfNeeded: Bool) throws -> CInt? {
        guard !fileName.isEmpty, fileName != "." else {
            throw MugHistoryFileStoreError.invalidHistoryFileName(fileURL.path)
        }

        if createIfNeeded {
            try createParentDirectoryIfNeeded()
        }

        let descriptor = open(parentDirectoryURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            if !createIfNeeded && errno == ENOENT {
                return nil
            }

            throw MugHistoryFileStoreError.unsafeParentDirectory(parentDirectoryURL.path)
        }

        do {
            try validateOpenDirectory(descriptor)
        } catch {
            closeDescriptor(descriptor)
            throw error
        }

        return descriptor
    }

    private func openHistoryFile(
        relativeTo parentDescriptor: CInt,
        flags: CInt,
        missingIsAllowed: Bool
    ) throws -> CInt? {
        let descriptor = fileName.withCString { pointer in
            openat(parentDescriptor, pointer, flags, S_IRUSR | S_IWUSR)
        }

        guard descriptor >= 0 else {
            if missingIsAllowed && errno == ENOENT {
                return nil
            }

            if errno == ELOOP {
                throw MugHistoryFileStoreError.unsafeHistoryFile(fileURL.path)
            }

            throw MugHistoryFileStoreError.fileOperationFailed("open history file", errno)
        }

        return descriptor
    }

    private func validateExistingHistoryFileIfPresent(relativeTo parentDescriptor: CInt) throws {
        let descriptor = try openHistoryFile(
            relativeTo: parentDescriptor,
            flags: O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC,
            missingIsAllowed: true
        )

        guard let descriptor else { return }
        defer { closeDescriptor(descriptor) }

        try validateOpenHistoryFile(descriptor)
    }

    private func validateOpenDirectory(_ descriptor: CInt) throws {
        var status = stat()
        guard fstat(descriptor, &status) == 0 else {
            throw MugHistoryFileStoreError.fileOperationFailed("inspect history directory", errno)
        }

        guard Self.isDirectory(status.st_mode) else {
            throw MugHistoryFileStoreError.unsafeParentDirectory(parentDirectoryURL.path)
        }
    }

    @discardableResult
    private func validateOpenHistoryFile(_ descriptor: CInt) throws -> Int {
        var status = stat()
        guard fstat(descriptor, &status) == 0 else {
            throw MugHistoryFileStoreError.fileOperationFailed("inspect history file", errno)
        }

        guard Self.isRegularFile(status.st_mode), status.st_nlink == 1 else {
            throw MugHistoryFileStoreError.unsafeHistoryFile(fileURL.path)
        }
        return Int(status.st_size)
    }

    private func readAllData(from descriptor: CInt, maximumBytes: Int) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)

        while data.count < maximumBytes {
            let byteCount = buffer.withUnsafeMutableBytes { rawBuffer in
                read(descriptor, rawBuffer.baseAddress, min(rawBuffer.count, maximumBytes - data.count))
            }

            if byteCount > 0 {
                data.append(contentsOf: buffer.prefix(byteCount))
            } else if byteCount == 0 {
                return data
            } else if errno != EINTR {
                throw MugHistoryFileStoreError.fileOperationFailed("read history file", errno)
            }
        }
        return data
    }

    private func writeAllData(_ data: Data, to descriptor: CInt) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }

            var writtenByteCount = 0
            while writtenByteCount < rawBuffer.count {
                let result = write(
                    descriptor,
                    baseAddress.advanced(by: writtenByteCount),
                    rawBuffer.count - writtenByteCount
                )

                if result > 0 {
                    writtenByteCount += result
                } else if result == 0 {
                    throw MugHistoryFileStoreError.fileOperationFailed("write history file", EIO)
                } else if errno != EINTR {
                    throw MugHistoryFileStoreError.fileOperationFailed("write history file", errno)
                }
            }
        }
    }

    private func closeDescriptor(_ descriptor: CInt) {
        while close(descriptor) == -1 && errno == EINTR {}
    }

    private static func isDirectory(_ mode: mode_t) -> Bool {
        (mode & S_IFMT) == S_IFDIR
    }

    private static func isRegularFile(_ mode: mode_t) -> Bool {
        (mode & S_IFMT) == S_IFREG
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
