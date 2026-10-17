import Foundation

/// JSON files in one directory (docs/メニュー形式.md "ファイル"). Writes are atomic.
public struct FileStore: Sendable {
    public enum StoreError: Error, Equatable {
        /// The file was written by a newer app version; it is left untouched.
        case unsupportedSchema(found: Int)
    }

    public static let menusSchemaVersion = 1

    private struct MenusFile: Codable {
        var schemaVersion: Int
        var menus: [Menu]
    }

    private struct SchemaProbe: Decodable { var schemaVersion: Int? }

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Application Support/workout-timer
    public static func appDefault() throws -> FileStore {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        return FileStore(directory: base.appendingPathComponent("workout-timer", isDirectory: true))
    }

    /// ISO 8601 with milliseconds, so saved end times keep sub-second precision.
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(isoFormatter(fractional: true).string(from: date))
        }
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let text = try c.decode(String.self)
            if let date = isoFormatter(fractional: true).date(from: text) ?? isoFormatter(fractional: false).date(from: text) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "invalid date \(text)")
        }
        return d
    }()

    static func isoFormatter(fractional: Bool) -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = fractional ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        return f
    }

    private func url(_ name: String) -> URL { directory.appendingPathComponent(name) }

    private func write<T: Encodable>(_ value: T, to name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileStore.encoder.encode(value).write(to: url(name), options: .atomic)
    }

    private func read<T: Decodable>(_ type: T.Type, from name: String, maxSchema: Int) throws -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        if let found = try FileStore.decoder.decode(SchemaProbe.self, from: data).schemaVersion, found > maxSchema {
            throw StoreError.unsupportedSchema(found: found)
        }
        return try FileStore.decoder.decode(type, from: data)
    }

    // MARK: Menus

    public func loadMenus() throws -> [Menu]? {
        try read(MenusFile.self, from: "menus.json", maxSchema: FileStore.menusSchemaVersion)?.menus
    }

    public func saveMenus(_ menus: [Menu]) throws {
        try write(MenusFile(schemaVersion: FileStore.menusSchemaVersion, menus: menus), to: "menus.json")
    }

    // MARK: Session

    public func loadSession() throws -> Session? {
        try read(Session.self, from: "session.json", maxSchema: Session.schemaVersion)
    }

    public func saveSession(_ session: Session?) throws {
        if let session {
            try write(session, to: "session.json")
        } else if FileManager.default.fileExists(atPath: url("session.json").path) {
            try FileManager.default.removeItem(at: url("session.json"))
        }
    }

    // MARK: Settings

    public func loadSettings() throws -> SoundSettings? {
        try read(SoundSettings.self, from: "settings.json", maxSchema: 1)
    }

    public func saveSettings(_ settings: SoundSettings) throws {
        try write(settings, to: "settings.json")
    }
}
