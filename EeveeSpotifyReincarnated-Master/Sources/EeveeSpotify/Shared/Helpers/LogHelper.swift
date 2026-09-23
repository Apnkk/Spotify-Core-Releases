import Foundation
import os.log

// Public logging helper that makes strings visible in Console.app
struct LogHelper {
    private static let log = OSLog(subsystem: "com.eevee.spotify", category: "EeveeSpotify")
    
    static func log(_ message: String) {
        os_log("%{public}@", log: log, type: .default, "[EeveeSpotify] \(message)")
    }
    
    static func logError(_ message: String) {
        os_log("%{public}@", log: log, type: .error, "[EeveeSpotify] ERROR: \(message)")
    }
    
    static func logDebug(_ message: String) {
        os_log("%{public}@", log: log, type: .debug, "[EeveeSpotify] \(message)")
    }
}
