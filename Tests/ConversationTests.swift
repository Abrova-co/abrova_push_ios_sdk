import XCTest
import UserNotifications
@testable import AbrovaPush

/// data.conversationId turns a notification into a conversation notification; other notifications are untouched.
final class ConversationTests: XCTestCase {

    func testReadsTheKeysAsAPNsDeliversThem() {
        let info = AbrovaPushConversation.info(from: [
            "conversationId": "room-1", "senderName": "@kian", "senderId": "u-kian",
            "senderAvatarUrl": "https://cdn.example/k.jpg", "conversationIsGroup": "true", "conversationTitle": "Family",
        ], fallbackSender: "Title")
        XCTAssertEqual(info?.id, "room-1")
        XCTAssertEqual(info?.senderName, "@kian")
        XCTAssertEqual(info?.senderAvatarUrl?.absoluteString, "https://cdn.example/k.jpg")
        XCTAssertEqual(info?.isGroup, true)
        XCTAssertEqual(info?.title, "Family")
    }

    func testNoConversationIdIsNotAConversation() {
        XCTAssertNil(AbrovaPushConversation.info(from: ["senderName": "x"], fallbackSender: "t"))
        XCTAssertNil(AbrovaPushConversation.info(from: ["conversationId": "  "], fallbackSender: "t"))
    }

    func testFallbacksAndBadAvatar() {
        let info = AbrovaPushConversation.info(from: ["conversationId": "r", "senderAvatarUrl": "javascript:x", "conversationIsGroup": true], fallbackSender: "Title")
        XCTAssertEqual(info?.senderName, "Title")
        XCTAssertNil(info?.senderAvatarUrl)
        XCTAssertEqual(info?.isGroup, true)
    }

    func testConversationIsGroupedByItsId() {
        let content = UNMutableNotificationContent()
        content.title = "@kian"
        content.body = "salam"
        content.userInfo = ["conversationId": "room-1", "senderName": "@kian"]
        let done = expectation(description: "content")
        AbrovaPushConversation.content(for: content) { result in
            XCTAssertEqual(result.threadIdentifier, "room-1")
            XCTAssertEqual(result.body, "salam")
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }

    func testOtherNotificationsAreUnchanged() {
        let content = UNMutableNotificationContent()
        content.title = "Lino"
        content.threadIdentifier = "own-thread"
        content.userInfo = ["x": "1"]
        let done = expectation(description: "content")
        AbrovaPushConversation.content(for: content) { result in
            XCTAssertTrue(result === content)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }
}
