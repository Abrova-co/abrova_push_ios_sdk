import XCTest
@testable import AbrovaPush

/// The new options (askNotificationPermission, autoInAppTriggers) keep today's behaviour by default, and both can be
/// turned off from the init and the builder. (The repeat-trigger guard itself is covered by the Android SDK's
/// InAppAutoTriggerTest; the logic is the same.)
final class InAppAutoTriggerTests: XCTestCase {

    func testDefaultsKeepTodaysBehaviour() {
        let config = AbrovaPushConfig(apiKey: "k")
        XCTAssertTrue(config.askNotificationPermission)
        XCTAssertTrue(config.autoInAppTriggers)
        let own = AbrovaPushConfig.builder(apiKey: "k").askNotificationPermission(false).autoInAppTriggers(false).build()
        XCTAssertFalse(own.askNotificationPermission)
        XCTAssertFalse(own.autoInAppTriggers)
        XCTAssertEqual(InAppMessageManager.repeatTriggerSeconds, 5)
    }
}
