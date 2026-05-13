import Foundation

enum AppTrace {
    nonisolated(unsafe) private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) static var isEnabled = true

    nonisolated static func log(_ category: String, _ message: String, file: String = #fileID, function: String = #function, line: Int = #line) {
        guard isEnabled else { return }

        let timestamp = formatter.string(from: Date())
        let source = "\(file):\(line) \(function)"
        let payload = "[webiqu][\(timestamp)][\(category)] \(message) | \(source)"

        NSLog("%@", payload)
    }
}
