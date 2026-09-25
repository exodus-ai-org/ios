// swift-tools-version: 6.0
import PackageDescription

#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        productTypes: [
            "Markdown": .staticFramework
        ]
    )
#endif

let package = Package(
    name: "ExodusIos",
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.9.0")
    ]
)
