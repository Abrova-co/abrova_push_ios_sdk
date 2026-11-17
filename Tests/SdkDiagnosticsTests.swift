import XCTest
@testable import AbrovaPush

/// X-Abrova-SDK-Report (+ -Reasons): counts and reason words only, kept until a 2xx answer, nothing at all when switched off.
final class SdkDiagnosticsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var diag: SdkDiagnostics!

    /// The server's grammar for one reasons entry.
    private let grammar = try! NSRegularExpression(
        pattern: "^(\\d{4}):([a-z][a-z0-9_]{0,19})(?:\\.(\\d{1,5}))?(?:\\.(wifi|cellular|ethernet|vpn|none|other))?=(\\d{1,4})$"
    )

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "SdkDiagnosticsTests")
        defaults.removePersistentDomain(forName: "SdkDiagnosticsTests")
        diag = SdkDiagnostics(defaults: defaults)
    }

    private func matchesGrammar(_ header: String) -> Bool {
        return header.split(separator: " ").allSatisfy { part in
            let s = String(part)
            return grammar.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
        }
    }

    func testCountsByPublicCodeAndFormatsTheHeader() {
        diag.count(.registrationFailed)
        diag.count(.connectionLost)
        diag.count(.connectionLost)
        XCTAssertEqual(diag.pending(), [1400: 1, 1002: 2])
        XCTAssertEqual(SdkDiagnostics.headerValue(diag.pending()), "1002=2 1400=1")
        XCTAssertNil(SdkDiagnostics.headerValue([:]))
    }

    func testBounded() {
        for code in 2000..<2020 { diag.count(code) }
        XCTAssertEqual(diag.pending().count, SdkDiagnostics.maxCodes)
        for _ in 0..<10_050 { diag.count(2000) }
        XCTAssertEqual(diag.pending()[2000], SdkDiagnostics.maxCount)
    }

    func testSwitchedOffCountsKeepsAndSendsNothing() {
        diag.count(1400)
        diag.record(1000, reason: "timeout", port: 8883, net: "wifi")
        diag.setEnabled(false)
        diag.count(1400)
        diag.record(1000, reason: "timeout", port: 8883, net: "wifi")
        XCTAssertTrue(diag.pending().isEmpty)
        XCTAssertTrue(diag.pendingReasons().isEmpty)
        var request = URLRequest(url: URL(string: "https://example.test")!)
        XCTAssertTrue(diag.attach(to: &request).isEmpty)
        XCTAssertNil(request.value(forHTTPHeaderField: SdkDiagnostics.header))
        XCTAssertNil(request.value(forHTTPHeaderField: SdkDiagnostics.reasonsHeader))
        diag.setEnabled(true)
        XCTAssertTrue(diag.pending().isEmpty)
        XCTAssertTrue(diag.pendingReasons().isEmpty)
    }

    func testAttachThenAcknowledgeKeepsLaterCounts() {
        diag.count(1400)
        diag.count(1400)
        var request = URLRequest(url: URL(string: "https://example.test")!)
        let sent = diag.attach(to: &request)
        XCTAssertEqual(request.value(forHTTPHeaderField: SdkDiagnostics.header), "1400=2")
        diag.count(1400) // while the request is in flight
        diag.acknowledge(sent)
        XCTAssertEqual(diag.pending(), [1400: 1])
    }

    // MARK: - Reasons

    func testReasonsHeaderFormat() {
        for _ in 0..<3 { diag.record(1000, reason: "timeout", port: 8883, net: "wifi") }
        for _ in 0..<5 { diag.record(1007, reason: "mqtt5", port: 8883, net: "cellular") }
        diag.record(1402, reason: "http503", port: nil, net: nil)
        diag.record(1400, reason: "dns", port: nil, net: "vpn")

        var request = URLRequest(url: URL(string: "https://example.test")!)
        let report = diag.attach(to: &request)
        let reasons = request.value(forHTTPHeaderField: SdkDiagnostics.reasonsHeader)
        XCTAssertEqual(reasons, "1000:timeout.8883.wifi=3 1007:mqtt5.8883.cellular=5 1400:dns.vpn=1 1402:http503=1")
        XCTAssertEqual(request.value(forHTTPHeaderField: SdkDiagnostics.header), "1000=3 1007=5 1400=1 1402=1")
        XCTAssertTrue(matchesGrammar(reasons ?? ""))
        XCTAssertEqual(report.reasons.count, 4)
    }

    func testEntryOutsideTheGrammarIsNotKeptButTheCodeIsCounted() {
        diag.record(1000, reason: "Connection refused by host.example", port: nil, net: nil)
        diag.record(1000, reason: "timeout", port: 70000, net: "bluetooth")
        XCTAssertEqual(diag.pending(), [1000: 2])
        // Bad port and net are left out; the reason itself is valid.
        XCTAssertEqual(diag.pendingReasons(), ["1000:timeout": 1])
        XCTAssertNil(SdkDiagnostics.entry(code: 1000, reason: "averyveryverylongreasonword", port: nil, net: nil))
        XCTAssertNil(SdkDiagnostics.entry(code: 99, reason: "timeout", port: nil, net: nil))
    }

    func testReasonsClearedOnlyAfterAcknowledge() {
        diag.record(1000, reason: "timeout", port: 8883, net: "wifi")
        diag.record(1000, reason: "timeout", port: 8883, net: "wifi")

        // Not acknowledged (no 2xx): everything stays for the next request.
        var first = URLRequest(url: URL(string: "https://example.test")!)
        _ = diag.attach(to: &first)
        XCTAssertEqual(diag.pendingReasons(), ["1000:timeout.8883.wifi": 2])

        var second = URLRequest(url: URL(string: "https://example.test")!)
        let sent = diag.attach(to: &second)
        XCTAssertEqual(second.value(forHTTPHeaderField: SdkDiagnostics.reasonsHeader), "1000:timeout.8883.wifi=2")
        diag.record(1000, reason: "timeout", port: 8883, net: "wifi") // in flight
        diag.acknowledge(sent)
        XCTAssertEqual(diag.pendingReasons(), ["1000:timeout.8883.wifi": 1])
        XCTAssertEqual(diag.pending(), [1000: 1])
    }

    func testReasonsPersistAcrossInstances() {
        diag.record(1002, reason: "reset", port: 443, net: "cellular")
        let again = SdkDiagnostics(defaults: defaults)
        XCTAssertEqual(again.pendingReasons(), ["1002:reset.443.cellular": 1])
        XCTAssertEqual(again.pending(), [1002: 1])
    }

    func testAtMostSixteenEntriesAndCountCapped() {
        for port in 1...20 { diag.record(1000, reason: "timeout", port: port, net: nil) }
        XCTAssertEqual(diag.pendingReasons().count, SdkDiagnostics.maxReasons)
        XCTAssertNil(diag.pendingReasons()["1000:timeout.17"])
        XCTAssertEqual(diag.pending()[1000], 20, "the 17th entry's code is still counted")

        for _ in 0..<10_050 { diag.record(1000, reason: "timeout", port: 1, net: nil) }
        XCTAssertEqual(diag.pendingReasons()["1000:timeout.1"], SdkDiagnostics.maxCount)
    }

    func testNoEntryForACodeThatIsNotKept() {
        for code in 2000..<2016 { diag.count(code) }
        diag.record(1000, reason: "timeout", port: nil, net: nil)
        XCTAssertNil(diag.pending()[1000])
        XCTAssertTrue(diag.pendingReasons().isEmpty)
    }

    func testHeaderAtMost400Characters() {
        var long: [String: Int] = [:]
        for i in 0..<16 {
            long["\(1000 + i):tls_handshake_abcdef.65535.cellular"] = 9999
        }
        let header = SdkDiagnostics.reasonsHeaderValue(long)!
        XCTAssertLessThanOrEqual(header.value.count, SdkDiagnostics.maxReasonsHeaderLength)
        XCTAssertTrue(matchesGrammar(header.value))
        // Only what was sent is acknowledged; the rest goes with the next request.
        XCTAssertEqual(header.sent.count, header.value.split(separator: " ").count)
        XCTAssertLessThan(header.sent.count, 16)
    }

    func testCountWithErrorClassifies() {
        let timeout = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        diag.count(.registrationFailed, error: AbrovaPushError(errorCode: .registrationFailed, cause: timeout), net: "wifi")
        diag.count(.subscriptionFailed, error: AbrovaPushError(errorCode: .subscriptionFailed, cause: AbrovaPushError.serverError(503)))
        XCTAssertEqual(diag.pendingReasons(), ["1400:timeout.wifi": 1, "1100:http503": 1])
    }
}
