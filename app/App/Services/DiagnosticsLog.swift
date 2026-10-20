import Foundation

/// Small on-device log for device tests (what was scheduled, what was cleaned up). Viewable and
/// copyable from the menu screen; holds no personal data beyond menu and step names.
enum DiagnosticsLog {
    private static let key = "diagnostics.log.v1"
    private static let lock = NSLock()
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/dd HH:mm:ss.S"
        return f
    }()

    static var lines: [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }

    static func add(_ text: String) {
        lock.lock()
        defer { lock.unlock() }
        var all = lines
        all.append("\(formatter.string(from: Date())) \(text)")
        UserDefaults.standard.set(Array(all.suffix(400)), forKey: key)
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}
