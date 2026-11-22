// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Kalam",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Kalam",
            path: "Sources/Kalam",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("LocalAuthentication"),
                .linkedFramework("UserNotifications"),
                // Apple Intelligence (macOS 26+) is optional: weak-link so Kalam still launches on macOS 14/15.
                .unsafeFlags(["-Xlinker", "-weak_framework", "-Xlinker", "FoundationModels"]),
            ]
        )
    ]
)
