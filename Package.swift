// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SuperShot",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "SuperShot", targets: ["SuperShotApp"])],
    targets: [
        .target(name: "DesignSystem"),
        .target(name: "Settings", dependencies: ["DesignSystem", "Hotkeys", "Document", "Export", "AI"]),
        .target(name: "Capture", dependencies: ["DesignSystem"]),
        .target(name: "Export"),
        .target(name: "Document"),
        .target(name: "Recognition"),
        .target(name: "Library", dependencies: ["Document", "Render", "Export"]),
        .target(name: "AI", dependencies: ["Document", "Render", "Recognition", "Export"]),
        .target(name: "Render", dependencies: ["Document"]),
        .target(name: "Editor", dependencies: ["Document", "Render", "DesignSystem", "Export", "Recognition", "AI"]),
        .target(name: "Hotkeys", dependencies: ["DesignSystem"]),
        .executableTarget(name: "SuperShotApp", dependencies: ["DesignSystem", "Settings", "Capture", "Export", "Hotkeys", "Document", "Render", "Editor", "Recognition", "Library", "AI"]),
        .testTarget(name: "SettingsTests", dependencies: ["Settings"]),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"]),
        .testTarget(name: "CaptureTests", dependencies: ["Capture"]),
        .testTarget(name: "ExportTests", dependencies: ["Export"]),
        .testTarget(name: "HotkeysTests", dependencies: ["Hotkeys"]),
        .testTarget(name: "DocumentTests", dependencies: ["Document"]),
        .testTarget(name: "RenderTests", dependencies: ["Render", "Document"], resources:[.copy("Fixtures")]),
        .testTarget(name: "EditorTests", dependencies: ["Editor"]),
        .testTarget(name: "RecognitionTests", dependencies: ["Recognition"]),
        .testTarget(name: "LibraryTests", dependencies: ["Library", "Document", "Export"]),
        .testTarget(name: "AITests", dependencies: ["AI", "Recognition"])
    ]
)
