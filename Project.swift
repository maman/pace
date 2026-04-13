import ProjectDescription

let bundleId = "me.mahardi.pace"
let deploymentTarget: DeploymentTargets = .macOS("14.0")
let developmentTeam = "DKL5CLP48A"

let sharedSwiftSettings: SettingsDictionary = [
    "SWIFT_VERSION": "5.0",
    "SWIFT_APPROACHABLE_CONCURRENCY": "YES",
    "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
    "SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY": "YES",
]

let project = Project(
    name: "Pace",
    options: .options(
        defaultKnownRegions: ["en", "Base"],
        developmentRegion: "en"
    ),
    settings: .settings(
        base: sharedSwiftSettings.merging([
            "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
            "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
        ]) { _, new in new },
        configurations: [
            .debug(name: "Debug"),
            .release(name: "Release"),
        ],
        defaultSettings: .recommended
    ),
    targets: [
        .target(
            name: "Pace",
            destinations: .macOS,
            product: .app,
            bundleId: bundleId,
            deploymentTargets: deploymentTarget,
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Pace",
                "CFBundleIconName": "AppIcon",
                "CFBundleIconFile": "AppIcon",
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
                "LSUIElement": true,
                "LSApplicationCategoryType": "public.app-category.utilities",
                "NSAccessibilityUsageDescription": "Pace needs Accessibility to intercept trackpad gestures and record keyboard shortcuts.",
                "NSHumanReadableCopyright": "",
                "SUFeedURL": "https://maman.github.io/pace/appcast.xml",
                "SUPublicEDKey": "e3ermNLuMTNUMMKzq5kHMwaIhufi3sIBSGUBwqyAgW8=",
                "SUEnableAutomaticChecks": true,
                "SUScheduledCheckInterval": 86400,
            ]),
            sources: ["Pace/**/*.swift"],
            resources: [
                "Pace/Assets.xcassets",
                "Pace/Resources/AppIcon.icns",
            ],
            entitlements: .file(path: "Pace/Pace.entitlements"),
            scripts: [
                .pre(
                    script: """
                    if [ "$CONFIGURATION" = "Debug" ]; then
                        tccutil reset Accessibility ${PRODUCT_BUNDLE_IDENTIFIER} 2>/dev/null || true
                    fi
                    """,
                    name: "Reset TCC (Debug)",
                    basedOnDependencyAnalysis: false
                )
            ],
            dependencies: [
                .external(name: "Sparkle"),
            ],
            settings: .settings(
                base: sharedSwiftSettings.merging([
                    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
                    "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
                    "COMBINE_HIDPI_IMAGES": "YES",
                    "ENABLE_APP_SANDBOX": "NO",
                    "ENABLE_PREVIEWS": "YES",
                    "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
                    "ENABLE_USER_SELECTED_FILES": "readonly",
                    "REGISTER_APP_GROUPS": "YES",
                    "STRING_CATALOG_GENERATE_SYMBOLS": "YES",
                    "SWIFT_EMIT_LOC_STRINGS": "YES",
                    "CURRENT_PROJECT_VERSION": "1",
                    "MARKETING_VERSION": "1.0",
                    "DEVELOPMENT_TEAM[sdk=macosx*]": .string(developmentTeam),
                    "LD_RUNPATH_SEARCH_PATHS": [
                        "$(inherited)",
                        "@executable_path/../Frameworks",
                    ],
                ]) { _, new in new },
                configurations: [
                    .debug(name: "Debug", settings: [
                        "CODE_SIGN_IDENTITY": "-",
                        "CODE_SIGN_STYLE": "Automatic",
                    ]),
                    .release(name: "Release", settings: [
                        "CODE_SIGN_IDENTITY[sdk=macosx*]": "Developer ID Application",
                        "CODE_SIGN_STYLE": "Manual",
                        "ENABLE_HARDENED_RUNTIME": "YES",
                        "OTHER_CODE_SIGN_FLAGS": "--timestamp --options=runtime",
                        "VALIDATE_PRODUCT": "YES",
                    ]),
                ]
            )
        ),
        .target(
            name: "PaceTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "\(bundleId).PaceTests",
            deploymentTargets: deploymentTarget,
            infoPlist: .default,
            sources: ["PaceTests/**/*.swift"],
            dependencies: [
                .target(name: "Pace"),
            ],
            settings: .settings(
                base: sharedSwiftSettings.merging([
                    "CODE_SIGN_IDENTITY": "-",
                    "SWIFT_EMIT_LOC_STRINGS": "NO",
                ]) { _, new in new }
            )
        ),
    ]
)
