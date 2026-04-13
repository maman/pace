// swift-tools-version: 5.10
import PackageDescription

#if TUIST
import struct ProjectDescription.PackageSettings

let packageSettings = PackageSettings(
    productTypes: ["Sparkle": .framework]
)
#endif

let package = Package(
    name: "Pace",
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"),
    ]
)
