import XCTest
@testable import WorkoutCore

final class StoreTests: XCTestCase {
    var store: FileStore!

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        store = FileStore(directory: dir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: store.directory)
    }

    func testEmptyStoreReturnsNil() throws {
        XCTAssertNil(try store.loadMenus())
        XCTAssertNil(try store.loadSession())
        XCTAssertNil(try store.loadSettings())
    }

    func testRoundTrips() throws {
        let menus = PersonalMenus.all()
        try store.saveMenus(menus)
        XCTAssertEqual(try store.loadMenus(), menus)

        var session = Session(menu: mixedMenu, at: Date())
        session.apply(.complete, at: Date().addingTimeInterval(1.234))
        try store.saveSession(session)
        let loaded = try XCTUnwrap(try store.loadSession())
        XCTAssertEqual(loaded.stepIndex, session.stepIndex)
        XCTAssertEqual(loaded.completedExercises, 1)
        // Times are stored with millisecond precision.
        guard case .running(_, let savedEnd) = loaded.phase, case .running(_, let end) = session.phase else {
            return XCTFail("expected running rest")
        }
        XCTAssertEqual(savedEnd.timeIntervalSince1970, end.timeIntervalSince1970, accuracy: 0.002)
        try store.saveSession(nil)
        XCTAssertNil(try store.loadSession())

        var settings = SoundSettings()
        settings.finish = false
        try store.saveSettings(settings)
        XCTAssertEqual(try store.loadSettings(), settings)
    }

    func testNewerSchemaIsNotOverwrittenOrMisread() throws {
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let url = store.directory.appendingPathComponent("menus.json")
        try Data(#"{"schemaVersion": 99, "menus": []}"#.utf8).write(to: url)
        XCTAssertThrowsError(try store.loadMenus()) { error in
            XCTAssertEqual(error as? FileStore.StoreError, .unsupportedSchema(found: 99))
        }
    }

    func testMenusFileShape() throws {
        try store.saveMenus([PersonalMenus.chest()])
        let data = try Data(contentsOf: store.directory.appendingPathComponent("menus.json"))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["schemaVersion"] as? Int, 1)
        let first = (object?["menus"] as? [[String: Any]])?.first
        XCTAssertEqual(first?["name"] as? String, "CHEST")
        XCTAssertEqual(first?["rounds"] as? Int, 3)
        XCTAssertNotNil(first?["restBetweenRounds"])
    }
}
