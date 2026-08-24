import OSLog

enum AppLog {
    static let bluetooth = Logger(subsystem: "com.tom.swiftea", category: "Bluetooth")
    static let power = Logger(subsystem: "com.tom.swiftea", category: "Power")
    static let settings = Logger(subsystem: "com.tom.swiftea", category: "Settings")
    static let sidebar = Logger(subsystem: "com.tom.swiftea", category: "Sidebar")
}
