import Foundation
import OSLog

/// Centralized logging utility using OSLog
enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.gauntletai.whatsnext"
    
    static let auth = Logger(subsystem: subsystem, category: "Auth")
    static let network = Logger(subsystem: subsystem, category: "Network")
    static let database = Logger(subsystem: subsystem, category: "Database")
    static let messaging = Logger(subsystem: subsystem, category: "Messaging")
    static let realtime = Logger(subsystem: subsystem, category: "Realtime")
    static let sync = Logger(subsystem: subsystem, category: "Sync")
    static let ui = Logger(subsystem: subsystem, category: "UI")
    
    /// Log an error with context
    static func logError(_ error: Error, context: String, logger: Logger? = nil) {
        let selectedLogger = logger ?? auth
        selectedLogger.error("\(context): \(error.localizedDescription)")
    }

    /// Log info message
    static func logInfo(_ message: String, logger: Logger? = nil) {
        let selectedLogger = logger ?? messaging
        selectedLogger.info("\(message)")
    }

    /// Log debug message
    static func logDebug(_ message: String, logger: Logger? = nil) {
        let selectedLogger = logger ?? messaging
        selectedLogger.debug("\(message)")
    }

    /// Log warning message
    static func logWarning(_ message: String, logger: Logger? = nil) {
        let selectedLogger = logger ?? messaging
        selectedLogger.warning("\(message)")
    }
}

/// Error tracking and reporting
final class ErrorTracker {
    static let shared = ErrorTracker()
    
    private var recentErrors: [(error: Error, context: String, timestamp: Date)] = []
    private let maxErrors = 50
    
    private init() {}
    
    func trackError(_ error: Error, context: String) {
        let entry = (error: error, context: context, timestamp: Date())
        recentErrors.append(entry)
        
        // Keep only recent errors
        if recentErrors.count > maxErrors {
            recentErrors.removeFirst()
        }
        
        // Log to system
        AppLogger.logError(error, context: context)
    }
    
    func getRecentErrors() -> [(error: Error, context: String, timestamp: Date)] {
        return recentErrors
    }
    
    func clearErrors() {
        recentErrors.removeAll()
    }
}

