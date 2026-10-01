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
    options: .options(
        defaultKnownRegions: ["en", "zh-Hant", "zh-HK", "ja", "ko", "fr", "de", "es", "pt-BR", "it"],
        developmentRegion: "en"
    ),
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
                    // Ody on a plain background; LaunchSplash (Sources/App)
                    // picks up from this exact frame and animates it away.
                    "UILaunchScreen": [
                        "UIColorName": "LaunchBackground",
                        "UIImageName": "LaunchLogo"
                    ],
                    "NSAppTransportSecurity": [
                        "NSAllowsLocalNetworking": true
                    ],
                    "NSLocalNetworkUsageDescription":
                        "Exodus needs local network access to connect to the Exodus service running on your computer.",
                    "NSCameraUsageDescription":
                        "Exodus uses the camera to scan the pairing code shown on your computer.",
                    "NSFaceIDUsageDescription":
                        "Exodus uses Face ID to unlock the connection to your computer.",
                    "NSLocationWhenInUseUsageDescription":
                        "Exodus uses your location to show your position on the itinerary map and center the map when you tap the location button.",
                    "NSPhotoLibraryAddUsageDescription":
                        "Exodus saves the images you choose to your photo library.",
                    "NSHealthShareUsageDescription":
                        "Exodus reads your sleep, activity, heart and body data to write your daily health report.",
                    "NSHealthUpdateUsageDescription":
                        "Exodus saves the water you log to Apple Health.",
                    // exodus:// — the widgets' links (WidgetKitShared.DeepLink).
                    "CFBundleURLTypes": [
                        ["CFBundleURLName": "app.yancey.exodus.link", "CFBundleURLSchemes": ["exodus"]]
                    ]
                ]
            ),
            buildableFolders: ["Sources/App", "Resources/App"],
            entitlements: .dictionary([
                "com.apple.developer.healthkit": .boolean(true),
                "com.apple.developer.healthkit.access": .array([]),
                "com.apple.security.application-groups": .array([.string("group.app.yancey.exodus")])
            ]),
            dependencies: [
                .target(name: "ChatFeature"),
                .target(name: "SettingsFeature"),
                .target(name: "PhilharmonicFeature"),
                .target(name: "HealthFeature"),
                .target(name: "OdyKit"),
                .target(name: "WidgetKitShared"),
                .target(name: "NetworkingKit"),
                .target(name: "MarkdownKit")
            ],
            settings: .settings(
                base: [
                    "DEVELOPMENT_TEAM": .string(developmentTeam),
                    "CODE_SIGN_STYLE": "Automatic"
                ]
            )
        ),
        .target(
            name: "AppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "\(bundleIdRoot).AppTests",
            deploymentTargets: deploymentTargets,
            buildableFolders: ["Tests/AppTests"],
            dependencies: [.target(name: "App")]
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
        .target(
            name: "NetworkingKitTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "\(bundleIdRoot).NetworkingKitTests",
            deploymentTargets: deploymentTargets,
            buildableFolders: ["Tests/NetworkingKitTests"],
            dependencies: [.target(name: "NetworkingKit"), .target(name: "Models")]
        ),
        moduleTarget(name: "MarkdownKit", dependencies: [.external(name: "Markdown")]),
        .target(
            name: "MarkdownKitTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "\(bundleIdRoot).MarkdownKitTests",
            deploymentTargets: deploymentTargets,
            buildableFolders: ["Tests/MarkdownKitTests"],
            dependencies: [.target(name: "MarkdownKit")]
        ),
        moduleTarget(
            name: "ChatFeature",
            dependencies: [
                .target(name: "NetworkingKit"), .target(name: "Models"), .target(name: "MarkdownKit")
            ]
        ),
        .target(
            name: "ChatFeatureTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "\(bundleIdRoot).ChatFeatureTests",
            deploymentTargets: deploymentTargets,
            buildableFolders: ["Tests/ChatFeatureTests"],
            dependencies: [
                .target(name: "ChatFeature"), .target(name: "NetworkingKit"), .target(name: "Models")
            ]
        ),
        moduleTarget(
            name: "SettingsFeature",
            dependencies: [.target(name: "NetworkingKit"), .target(name: "Models")]
        ),
        .target(
            name: "SettingsFeatureTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "\(bundleIdRoot).SettingsFeatureTests",
            deploymentTargets: deploymentTargets,
            buildableFolders: ["Tests/SettingsFeatureTests"],
            dependencies: [
                .target(name: "SettingsFeature"), .target(name: "NetworkingKit"), .target(name: "Models")
            ]
        ),
        moduleTarget(name: "PhilharmonicFeature", dependencies: [.target(name: "Models")]),
        moduleTarget(name: "OdyKit"),
        moduleTarget(name: "WidgetKitShared"),
        .target(
            name: "WidgetKitSharedTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "\(bundleIdRoot).WidgetKitSharedTests",
            deploymentTargets: deploymentTargets,
            buildableFolders: ["Tests/WidgetKitSharedTests"],
            dependencies: [.target(name: "WidgetKitShared")]
        ),
        .target(
            name: "OdyKitTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "\(bundleIdRoot).OdyKitTests",
            deploymentTargets: deploymentTargets,
            buildableFolders: ["Tests/OdyKitTests"],
            dependencies: [.target(name: "OdyKit")]
        ),
        moduleTarget(
            name: "HealthFeature",
            dependencies: [
                .target(name: "Models"), .target(name: "NetworkingKit"), .target(name: "MarkdownKit"),
                .target(name: "OdyKit"), .target(name: "WidgetKitShared")
            ]
        ),
        .target(
            name: "HealthFeatureTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "\(bundleIdRoot).HealthFeatureTests",
            deploymentTargets: deploymentTargets,
            buildableFolders: ["Tests/HealthFeatureTests"],
            dependencies: [
                .target(name: "HealthFeature"), .target(name: "NetworkingKit"), .target(name: "Models")
            ]
        )
    ]
)
