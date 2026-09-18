import ProjectDescription

private let bundleIdRoot = "app.yancey.exodus.exodus-ios"
private let developmentTeam = "YLF27G9ZMT"
private let deploymentTargets = DeploymentTargets.iOS("27.0")

private func moduleTarget(
    name: String,
    dependencies: [TargetDependency] = []
) -> Target {
    .target(
        name: name,
        destinations: .iOS,
        product: .staticFramework,
        bundleId: "\(bundleIdRoot).\(name)",
        deploymentTargets: deploymentTargets,
        buildableFolders: [BuildableFolder(stringLiteral: "Sources/\(name)")],
        dependencies: dependencies
    )
}

let project = Project(
    name: "ExodusIos",
    settings: .settings(base: ["SWIFT_VERSION": "6.0"]),
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            productName: "Exodus",
            bundleId: bundleIdRoot,
            deploymentTargets: deploymentTargets,
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchScreen": [:],
                    "NSAppTransportSecurity": [
                        "NSAllowsLocalNetworking": true
                    ],
                    "NSLocalNetworkUsageDescription":
                        "Exodus 需要访问本地网络以连接到你电脑上运行的 Exodus 服务。"
                ]
            ),
            buildableFolders: ["Sources/App", "Resources/App"],
            dependencies: [
                .target(name: "ChatFeature"),
                .target(name: "SettingsFeature"),
                .target(name: "PhilharmonicFeature"),
                .target(name: "NetworkingKit")
            ],
            settings: .settings(
                base: [
                    "DEVELOPMENT_TEAM": .string(developmentTeam),
                    "CODE_SIGN_STYLE": "Automatic"
                ]
            )
        ),
        moduleTarget(name: "Models"),
        .target(
            name: "ModelsTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "\(bundleIdRoot).ModelsTests",
            deploymentTargets: deploymentTargets,
            buildableFolders: ["Tests/ModelsTests"],
            dependencies: [.target(name: "Models")]
        ),
        moduleTarget(name: "NetworkingKit", dependencies: [.target(name: "Models")]),
        moduleTarget(
            name: "ChatFeature",
            dependencies: [.target(name: "NetworkingKit"), .target(name: "Models")]
        ),
        moduleTarget(
            name: "SettingsFeature",
            dependencies: [.target(name: "NetworkingKit"), .target(name: "Models")]
        ),
        moduleTarget(name: "PhilharmonicFeature", dependencies: [.target(name: "Models")])
    ]
)
