import XCTest
@testable import AbrovaPush

/// Notification channels: the message carries `channelId` and, for a Console channel, its definition.
final class NotificationChannelTests: XCTestCase {
    private let serverJson = """
    {"title":"t","body":"b","channelId":"offers","channel":{"id":"offers","v":3,"name":{"en":"Offers","fa":"پیشنهادها"},"importance":"low","vibrate":false,"sound":"none","ios":"passive"}}
    """

    func testDecodesChannelFromTheServerJson() throws {
        let m = try XCTUnwrap(AbrovaPushMessage.from(json: serverJson))
        XCTAssertEqual(m.channelId, "offers")
        XCTAssertEqual(m.channel, AbrovaPushChannel(id: "offers", v: 3, importance: "low", vibrate: false, sound: "none", ios: "passive"))
    }

    func testPayloadDictionaryAndBridgeRoundTrip() throws {
        let payload: [String: Any] = [
            "title": "t", "body": "b", "channelId": "orders",
            "channel": ["id": "orders", "v": 1, "importance": "high", "vibrate": true, "sound": "default", "ios": "time-sensitive"],
        ]
        let m = try XCTUnwrap(AbrovaPushMessage.from(payload: payload))
        XCTAssertEqual(m.channel?.ios, "time-sensitive")
        let dict = m.toDictionary()
        XCTAssertEqual(dict["channelId"] as? String, "orders")
        XCTAssertEqual((dict["channel"] as? [String: Any])?["importance"] as? String, "high")
        let again = try XCTUnwrap(AbrovaPushMessage.from(payload: dict))
        XCTAssertEqual(again.channel, m.channel)
    }

    func testOldMessagesWithoutAChannelStillDecode() throws {
        let m = try XCTUnwrap(AbrovaPushMessage.from(json: #"{"title":"t","body":"b"}"#))
        XCTAssertNil(m.channelId)
        XCTAssertNil(m.channel)
        // A broken channel object never drops the message.
        let broken = try XCTUnwrap(AbrovaPushMessage.from(json: #"{"title":"t","body":"b","channelId":"x","channel":"oops"}"#))
        XCTAssertEqual(broken.channelId, "x")
        XCTAssertNil(broken.channel)
    }
}
