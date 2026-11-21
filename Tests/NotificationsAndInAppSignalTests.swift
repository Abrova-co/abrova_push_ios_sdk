import XCTest
@testable import AbrovaPush

/// notificationsEnabled on register (with an older server that refuses the field), the in-app fetch's ETag/304,
/// the banner position and the refresh reason when notifications are turned on or off.
final class NotificationsAndInAppSignalTests: XCTestCase {

    private let refusedKey = "abrova_push.notifications_field_refused_at"

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        UserDefaults.standard.removeObject(forKey: refusedKey)
    }

    override func tearDown() {
        MockURLProtocol.reset()
        UserDefaults.standard.removeObject(forKey: refusedKey)
        super.tearDown()
    }

    private func makeClient() -> ApiClient {
        ApiClient(
            config: AbrovaPushConfig(apiKey: "ab_test_key"),
            session: RetryingURLSession(protocolClasses: [MockURLProtocol.self])
        )
    }

    private func body(_ request: URLRequest) -> [String: Any] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                data.append(buffer, count: n)
            }
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private func register(_ client: ApiClient, enabled: Bool?) -> Result<ApiClient.RegisterResponse, Error>? {
        let done = expectation(description: "register")
        var outcome: Result<ApiClient.RegisterResponse, Error>?
        client.registerDevice(deviceId: "d1", pushToken: nil, apnsToken: nil, userId: nil, metadata: nil,
                              notificationsEnabled: enabled) { result in
            outcome = result
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        return outcome
    }

    func testRegisterSendsNotificationsEnabled() {
        MockURLProtocol.requestHandler = { _ in MockURLProtocol.mockResponse(json: ["id": "r1", "deviceId": "d1", "message": "ok"]) }
        let result = register(makeClient(), enabled: false)
        if case .failure(let error)? = result { XCTFail("\(error)") }
        XCTAssertEqual(body(MockURLProtocol.recordedRequests[0])["notificationsEnabled"] as? Bool, false)
    }

    func testOlderServerGetsTheRegisterAgainWithoutTheField() {
        MockURLProtocol.requestHandler = { request in
            if self.body(request)["notificationsEnabled"] != nil {
                return MockURLProtocol.mockResponse(statusCode: 400, json: [
                    "statusCode": 400, "message": ["property notificationsEnabled should not exist"]
                ])
            }
            return MockURLProtocol.mockResponse(json: ["id": "r1", "deviceId": "d1", "message": "ok"])
        }
        let client = makeClient()
        let result = register(client, enabled: true)

        if case .failure(let error)? = result { XCTFail("\(error)") }
        XCTAssertEqual(MockURLProtocol.recordedRequests.count, 2)
        XCTAssertNil(body(MockURLProtocol.recordedRequests[1])["notificationsEnabled"])
        XCTAssertTrue(ApiClient.notificationsFieldRefusedRecently())

        // For a day the field is left out at once.
        MockURLProtocol.recordedRequests = []
        _ = register(client, enabled: true)
        XCTAssertEqual(MockURLProtocol.recordedRequests.count, 1)
        XCTAssertNil(body(MockURLProtocol.recordedRequests[0])["notificationsEnabled"])
    }

    func testAnotherBadRequestIsAnErrorNotARetry() {
        MockURLProtocol.requestHandler = { _ in
            MockURLProtocol.mockResponse(statusCode: 400, json: ["message": ["deviceId must be a string"]])
        }
        let result = register(makeClient(), enabled: true)
        guard case .failure? = result else { return XCTFail("expected an error") }
        XCTAssertEqual(MockURLProtocol.recordedRequests.count, 1)
    }

    func testInAppFetchSendsTheEtagAndReads304AsUnchanged() {
        let client = makeClient()
        MockURLProtocol.requestHandler = { request in
            if request.value(forHTTPHeaderField: "If-None-Match") == "W/\"abc\"" {
                return (HTTPURLResponse(url: request.url!, statusCode: 304, httpVersion: nil, headerFields: nil)!, nil)
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                           headerFields: ["ETag": "W/\"abc\""])!
            return (response, Data("{\"messages\":[]}".utf8))
        }

        var first: ApiClient.InAppFetchResult?
        let one = expectation(description: "first")
        client.fetchInAppMessages(params: ["deviceId": "d1"], etag: nil) { result in
            first = try? result.get()
            one.fulfill()
        }
        wait(for: [one], timeout: 5)
        XCTAssertEqual(first?.etag, "W/\"abc\"")
        XCTAssertEqual(first?.notModified, false)

        var second: ApiClient.InAppFetchResult?
        let two = expectation(description: "second")
        client.fetchInAppMessages(params: ["deviceId": "d1"], etag: first?.etag) { result in
            second = try? result.get()
            two.fulfill()
        }
        wait(for: [two], timeout: 5)
        XCTAssertEqual(second?.notModified, true)
    }

    func testBannerPositionIsReadKeptForTranslationsAndHandedToWrappers() {
        let content = InAppMessageContent.fromJson(["title": "Hi", "body": "b", "position": "bottom"])
        XCTAssertEqual(content?.position, "bottom")
        XCTAssertEqual(content?.toDictionary()["position"] as? String, "bottom")
        XCTAssertNil(InAppMessageContent.fromJson(["title": "a", "body": "b", "position": "middle"])?.position)
        let translated = InAppMessageContent(title: "سلام", body: "ب").withPosition("bottom")
        XCTAssertEqual(translated.position, "bottom")
    }

    func testTurningNotificationsOffIsAReasonToRefresh() {
        let stored = RegistrationFingerprint(appVersion: "1", appBuild: "1", sdkIdentity: "ios/1", apnsToken: nil,
                                             voipToken: nil, userId: nil, notificationsEnabled: true)
        var current = stored
        current.notificationsEnabled = false
        XCTAssertEqual(RegistrationRefresh.reason(hasRegistered: true, lastSuccess: Date(), now: Date(),
                                                  stored: stored, current: current), .notificationsChanged)
        current.notificationsEnabled = nil // not checked yet: no reason
        XCTAssertNil(RegistrationRefresh.reason(hasRegistered: true, lastSuccess: Date(), now: Date(),
                                                stored: stored, current: current))
    }

    func testRightToLeftFollowsTheText() {
        XCTAssertTrue(InAppMessageView.isRightToLeft(InAppMessageContent(title: "سلام", body: ""), locale: Locale(identifier: "en")))
        XCTAssertFalse(InAppMessageView.isRightToLeft(InAppMessageContent(title: "Hello", body: ""), locale: Locale(identifier: "en")))
        XCTAssertTrue(InAppMessageView.isRightToLeft(InAppMessageContent(title: "Hello", body: ""), locale: Locale(identifier: "fa")))
    }
}
