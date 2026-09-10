import Foundation

/// TEMPORARY instrumentation for P2-T02. Removed before the task reports.
enum TapProbe {
    static func log(_ message: String) {
        let line = "[probe] \(message)\n"
        FileHandle.standardError.write(line.data(using: .utf8)!)
    }
}
