import XCTest
@testable import AbrovaPush

/// Unit tests for AbrovaPushConfig
final class AbrovaPushConfigTests: XCTestCase {

    // MARK: - Builder Pattern Tests

    func testBuilder_minimalConfig() {
        let config = AbrovaPushConfig.builder(apiKey: "test_api_key").build()

        XCTAssertEqual(config.apiKey, "test_api_key")
        XCTAssertEqual(config.serverUrl, "https://push-api.abrova.ir")
    }

    func testBuilder_usePushKit() {
        let config = AbrovaPushConfig.builder(apiKey: "test_key")
            .usePushKit(true)
            .build()

        XCTAssertTrue(config.usePushKit)
    }

    func testBuilder_usePushKitFalse() {
        let config = AbrovaPushConfig.builder(apiKey: "test_key")
            .usePushKit(false)
            .build()

        XCTAssertFalse(config.usePushKit)
    }

    func testBuilder_showNotificationInForeground() {
        let config = AbrovaPushConfig.builder(apiKey: "test_key")
            .showNotificationInForeground(true)
            .build()

        XCTAssertTrue(config.showNotificationInForeground)
    }

    func testBuilder_autoConnect() {
        let config = AbrovaPushConfig.builder(apiKey: "test_key")
            .autoConnect(true)
            .build()

        XCTAssertTrue(config.autoConnect)
    }

    func testBuilder_autoConnectFalse() {
        let config = AbrovaPushConfig.builder(apiKey: "test_key")
            .autoConnect(false)
            .build()

        XCTAssertFalse(config.autoConnect)
    }

    func testBuilder_autoReconnect() {
        let configEnabled = AbrovaPushConfig.builder(apiKey: "test_key")
            .autoReconnect(true)
            .build()

        XCTAssertTrue(configEnabled.autoReconnect)

        let configDisabled = AbrovaPushConfig.builder(apiKey: "test_key")
            .autoReconnect(false)
            .build()

        XCTAssertFalse(configDisabled.autoReconnect)
    }

    func testBuilder_chainedConfiguration() {
        let config = AbrovaPushConfig.builder(apiKey: "test_key")
            .usePushKit(false)
            .showNotificationInForeground(true)
            .autoConnect(true)
            .autoReconnect(false)
            .maxReconnectAttempts(5)
            .build()

        XCTAssertEqual(config.apiKey, "test_key")
        XCTAssertFalse(config.usePushKit)
        XCTAssertTrue(config.showNotificationInForeground)
        XCTAssertTrue(config.autoConnect)
        XCTAssertFalse(config.autoReconnect)
        XCTAssertEqual(config.maxReconnectAttempts, 5)
    }

    // MARK: - API Key Validation

    func testApiKey_notEmpty() {
        let config = AbrovaPushConfig.builder(apiKey: "ab_live_abc123").build()
        XCTAssertFalse(config.apiKey.isEmpty)
    }

    func testApiKey_preservesValue() {
        let apiKey = "ab_live_1234567890abcdef"
        let config = AbrovaPushConfig.builder(apiKey: apiKey).build()
        XCTAssertEqual(config.apiKey, apiKey)
    }

    // MARK: - Server URL Tests

    func testServerUrl_defaultValue() {
        let config = AbrovaPushConfig.builder(apiKey: "test").build()
        XCTAssertEqual(config.serverUrl, "https://push-api.abrova.ir")
    }

    // MARK: - Default Values Tests

    func testDefaultValues() {
        let config = AbrovaPushConfig.builder(apiKey: "test").build()

        // Verify defaults (these may vary based on implementation)
        XCTAssertEqual(config.serverUrl, "https://push-api.abrova.ir")
    }
}
