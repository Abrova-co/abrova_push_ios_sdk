// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "AbrovaPush",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "AbrovaPush",
            targets: ["AbrovaPush"]
        ),
    ],
    dependencies: [
        // PN Protocol - Abrova Push's messaging protocol layer
        .package(url: "https://center.abrova.ir/abrova/pn-protocol-ios.git", from: "0.2.2"),
    ],
    targets: [
        .target(
            name: "AbrovaPush",
            dependencies: [.product(name: "PNProtocol", package: "pn-protocol-ios")],
            path: "Sources",
            sources: [
                "AbrovaPush.swift",
                "AbrovaPushConfig.swift",
                "AbrovaPushDelegate.swift",
                "AbrovaPushMessage.swift",
                "AbrovaPushError.swift",
                "AbrovaPushLogger.swift",
                "ApiClient.swift",
                "PNSocketManager.swift",
                "VoIPManager.swift",
                "NotificationManager.swift",
                "AbrovaPushServiceExtension.swift",
                "AbrovaPushShared.swift",
                "Internal/RegistrationRefresh.swift",
                "Utils/AbrovaPushDispatch.swift",
                "Utils/NetworkConfig.swift",
                "InApp/InAppMessage.swift",
                "InApp/InAppMessageManager.swift",
                "InApp/InAppMessageView.swift",
                "Inbox/InboxMessage.swift",
                "Inbox/InboxManager.swift",
                "ABTesting/ABTest.swift",
                "ABTesting/ABTestingManager.swift",
                "Internal/SdkCredentials.swift",
                "Internal/InstallId.swift",
                "Internal/MqttEndpoints.swift",
                "Internal/ConnectivityMonitor.swift",
                "Internal/UserToken.swift",
                "Internal/UserTokenStore.swift",
                "Internal/SdkDiagnostics.swift"
            ],
            resources: [.copy("PrivacyInfo.xcprivacy")]
        ),
        .testTarget(
            name: "AbrovaPushTests",
            dependencies: ["AbrovaPush"],
            path: "Tests"
        ),
    ]
)
