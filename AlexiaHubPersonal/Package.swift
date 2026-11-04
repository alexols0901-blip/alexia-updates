// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AlexiaHubPersonal",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "AlexiaHubPersonal", targets: ["AlexiaHubPersonal"])],
    targets: [.executableTarget(name: "AlexiaHubPersonal")]
)
