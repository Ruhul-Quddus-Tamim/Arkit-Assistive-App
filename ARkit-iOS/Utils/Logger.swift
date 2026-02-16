import Foundation

/// Logging utility for production-ready apps
/// Debug logs only appear in DEBUG builds, errors always logged
enum LogLevel {
    case debug
    case info
    case error
}

struct Logger {
    /// Log a message with specified level
    /// - Parameters:
    ///   - message: The message to log
    ///   - level: The log level (default: .debug)
    static func log(_ message: String, level: LogLevel = .debug) {
        #if DEBUG
        let levelString: String
        switch level {
        case .debug:
            levelString = "DEBUG"
        case .info:
            levelString = "INFO"
        case .error:
            levelString = "ERROR"
        }
        print("[\(levelString)] \(message)")
        #else
        // Only log errors in release builds
        if level == .error {
            print("[ERROR] \(message)")
        }
        #endif
    }
    
    /// Convenience method for debug logs
    static func debug(_ message: String) {
        log(message, level: .debug)
    }
    
    /// Convenience method for info logs
    static func info(_ message: String) {
        log(message, level: .info)
    }
    
    /// Convenience method for error logs
    static func error(_ message: String) {
        log(message, level: .error)
    }
}
