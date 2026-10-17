// swift-tools-version: 5.10
// Progression core for workout-timer: menus, step plan, session state machine, auto-chain
// limit check, Live Activity / notification plans and file storage. No UI or OS frameworks,
// so it can be unit-tested with `swift test` and mirrored on Android later.
import PackageDescription

let package = Package(
    name: "WorkoutCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "WorkoutCore", targets: ["WorkoutCore"])],
    targets: [
        .target(name: "WorkoutCore"),
        .testTarget(name: "WorkoutCoreTests", dependencies: ["WorkoutCore"]),
    ]
)
