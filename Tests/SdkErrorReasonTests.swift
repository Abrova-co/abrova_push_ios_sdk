import XCTest
import PNProtocol
@testable import AbrovaPush

/// Reason words come only from the fixed list, by error type and numeric code.
final class SdkErrorReasonTests: XCTestCase {
    private func url(_ code: Int) -> NSError { NSError(domain: NSURLErrorDomain, code: code) }
    private func posix(_ code: Int32) -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(code)) }
    private func wrap(_ outer: NSError, _ inner: Error) -> NSError {
        NSError(domain: outer.domain, code: outer.code, userInfo: [NSUnderlyingErrorKey: inner])
    }

    func testUrlErrors() {
        XCTAssertEqual(SdkErrorReason.classify(url(NSURLErrorTimedOut)), "timeout")
        XCTAssertEqual(SdkErrorReason.classify(url(NSURLErrorCannotFindHost)), "dns")
        XCTAssertEqual(SdkErrorReason.classify(url(NSURLErrorDNSLookupFailed)), "dns")
        XCTAssertEqual(SdkErrorReason.classify(url(NSURLErrorCannotConnectToHost)), "refused")
        XCTAssertEqual(SdkErrorReason.classify(url(NSURLErrorNotConnectedToInternet)), "offline")
        XCTAssertEqual(SdkErrorReason.classify(url(NSURLErrorNetworkConnectionLost)), "eof")
        XCTAssertEqual(SdkErrorReason.classify(url(NSURLErrorSecureConnectionFailed)), "tls_handshake")
        XCTAssertEqual(SdkErrorReason.classify(url(NSURLErrorServerCertificateUntrusted)), "cert")
        XCTAssertEqual(SdkErrorReason.classify(url(NSURLErrorServerCertificateHasBadDate)), "cert")
        XCTAssertEqual(SdkErrorReason.classify(url(NSURLErrorCancelled)), "cancelled")
        XCTAssertEqual(SdkErrorReason.classify(url(NSURLErrorCannotParseResponse)), "parse")
        XCTAssertEqual(SdkErrorReason.classify(URLError(.timedOut)), "timeout")
    }

    func testErrno() {
        XCTAssertEqual(SdkErrorReason.classify(posix(ETIMEDOUT)), "timeout")
        XCTAssertEqual(SdkErrorReason.classify(posix(ECONNREFUSED)), "refused")
        XCTAssertEqual(SdkErrorReason.classify(posix(ENETUNREACH)), "noroute")
        XCTAssertEqual(SdkErrorReason.classify(posix(EHOSTUNREACH)), "noroute")
        XCTAssertEqual(SdkErrorReason.classify(posix(ENETDOWN)), "noroute")
        XCTAssertEqual(SdkErrorReason.classify(posix(ECONNRESET)), "reset")
        XCTAssertEqual(SdkErrorReason.classify(posix(ECONNABORTED)), "reset")
        XCTAssertEqual(SdkErrorReason.classify(posix(EPIPE)), "reset")
        XCTAssertEqual(SdkErrorReason.classify(posix(ENOTCONN)), "socket")
    }

    func testSocketLibraryAndTls() {
        XCTAssertEqual(SdkErrorReason.classify(NSError(domain: "MGCDAsyncSocketErrorDomain", code: 3)), "timeout")
        XCTAssertEqual(SdkErrorReason.classify(NSError(domain: "MGCDAsyncSocketErrorDomain", code: 7)), "eof")
        XCTAssertEqual(SdkErrorReason.classify(NSError(domain: "kCFStreamErrorDomainNetDB", code: 8)), "dns")
        XCTAssertEqual(SdkErrorReason.classify(NSError(domain: "kCFStreamErrorDomainSSL", code: -9824)), "tls_handshake")
        XCTAssertEqual(SdkErrorReason.classify(NSError(domain: "kCFStreamErrorDomainSSL", code: -9807)), "cert")
        XCTAssertEqual(SdkErrorReason.classify(NSError(domain: "kCFStreamErrorDomainSSL", code: -9810)), "tls")
        XCTAssertEqual(SdkErrorReason.classify(NSError(domain: NSOSStatusErrorDomain, code: -9813)), "cert")
        XCTAssertEqual(SdkErrorReason.classify(NSError(domain: NSOSStatusErrorDomain, code: -50)), "other")
    }

    func testCertBeatsTlsHandshakeAnywhereInTheChain() {
        let chain = wrap(url(NSURLErrorSecureConnectionFailed), url(NSURLErrorServerCertificateUntrusted))
        XCTAssertEqual(SdkErrorReason.classify(chain), "cert")
        let osStatus = wrap(url(NSURLErrorSecureConnectionFailed), NSError(domain: NSOSStatusErrorDomain, code: -9812))
        XCTAssertEqual(SdkErrorReason.classify(osStatus), "cert")
    }

    func testPriorityAcrossTheChain() {
        // A lost connection (eof) caused by a timeout says timeout.
        XCTAssertEqual(SdkErrorReason.classify(wrap(url(NSURLErrorNetworkConnectionLost), posix(ETIMEDOUT))), "timeout")
        // An unknown wrapper falls through to what it wraps.
        let unknown = NSError(domain: "some.other.domain", code: 1, userInfo: [NSUnderlyingErrorKey: posix(ECONNREFUSED)])
        XCTAssertEqual(SdkErrorReason.classify(unknown), "refused")
    }

    func testHttpStatusWins() {
        let error = AbrovaPushError(errorCode: .registrationFailed, cause: AbrovaPushError.serverError(503))
        XCTAssertEqual(SdkErrorReason.classify(error), "http503")
        XCTAssertEqual(SdkErrorReason.classify(AbrovaPushError.serverError(404)), "http404")
        XCTAssertEqual(SdkErrorReason.classify(SdkErrorReason.httpError(status: 200)), "other")
        XCTAssertEqual(AbrovaPushError.serverError(503).toDictionary()["details"] as? String, "HTTP status code: 503")
    }

    func testPNProtocolErrors() {
        XCTAssertEqual(SdkErrorReason.classify(PNError(code: .connectionFailed, message: "Connection rejected: notAuthorized")), "mqtt5")
        XCTAssertEqual(SdkErrorReason.classify(PNError(code: .authFailed, message: "Connection rejected: badUsernameOrPassword")), "mqtt4")
        XCTAssertEqual(SdkErrorReason.classify(PNError(code: .connectionFailed, message: "Connection rejected: serverUnavailable")), "mqtt3")
        // Never mqtt0, never anything from a free-text message.
        XCTAssertEqual(SdkErrorReason.classify(PNError(code: .connectionFailed, message: "Connection rejected: accept")), "other")
        XCTAssertEqual(SdkErrorReason.classify(PNError(code: .connectionFailed, message: "Connection refused")), "other")
        XCTAssertEqual(SdkErrorReason.classify(PNError(code: .connectionFailed, message: "Connection timed out")), "timeout")
        // Ping timeout: a lost connection wrapping the PN timeout.
        let ping = PNError.connectionLost("Ping timed out", PNError(code: .connectionTimeout, message: "Ping timed out"))
        XCTAssertEqual(SdkErrorReason.classify(ping), "timeout")
        let reset = PNError.connectionLost("x", NSError(domain: "MGCDAsyncSocketErrorDomain", code: 8,
                                                         userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(ECONNRESET))]))
        XCTAssertEqual(SdkErrorReason.classify(reset), "reset")
        XCTAssertEqual(SdkErrorReason.classify(PNError.notConnected()), "state")
    }

    func testSwiftTypes() {
        let decoding = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "x"))
        XCTAssertEqual(SdkErrorReason.classify(decoding), "parse")
        XCTAssertEqual(SdkErrorReason.classify(AbrovaPushError.notInitialized), "state")
        XCTAssertEqual(SdkErrorReason.classify(nil), "other")
        struct Custom: Error {}
        XCTAssertEqual(SdkErrorReason.classify(Custom()), "other")
    }

    func testChainDepthIsBounded() {
        var error: NSError = posix(ETIMEDOUT)
        for _ in 0..<20 { error = NSError(domain: "wrap", code: 1, userInfo: [NSUnderlyingErrorKey: error]) }
        XCTAssertEqual(SdkErrorReason.classify(error), "other")
        var near: NSError = posix(ETIMEDOUT)
        for _ in 0..<7 { near = NSError(domain: "wrap", code: 1, userInfo: [NSUnderlyingErrorKey: near]) }
        XCTAssertEqual(SdkErrorReason.classify(near), "timeout")
    }

    func testEveryWordFitsTheGrammar() {
        for word in SdkErrorReason.priority + ["mqtt5", "http503", "other"] {
            XCTAssertNotNil(SdkDiagnostics.entry(code: 1000, reason: word, port: 8883, net: "wifi"), word)
        }
    }

    // MARK: - Socket error codes, port and network type

    func testSocketErrorCodes() {
        XCTAssertEqual(PNSocketManager.errorCode(for: PNError(code: .connectionFailed, message: "Failed to initiate connection")), .connectionSetupFailed)
        XCTAssertEqual(AbrovaPushErrorCode.connectionSetupFailed.rawValue, 1007)
        XCTAssertEqual(AbrovaPushErrorCode.fromCode(1007), .connectionSetupFailed)
        XCTAssertEqual(PNSocketManager.errorCode(for: PNError(code: .connectionFailed, message: "Connection timed out")), .connectionFailed)
        XCTAssertEqual(PNSocketManager.errorCode(for: PNError.connectionLost("x")), .connectionLost)
        XCTAssertEqual(PNSocketManager.errorCode(for: PNError.authFailed("x")), .authenticationFailed)
        XCTAssertEqual(PNSocketManager.errorCode(for: PNError.notConnected()), .unknownError)
    }

    func testReportPort() {
        var config = AbrovaPushConfig(apiKey: "k")
        config.updatePNConfig(host: "a.example", port: 8883, secure: true, token: "t", endpoints: [])
        let single = PNSocketManager(config: config, appId: "a", deviceId: "d")
        XCTAssertEqual(single.reportPort(for: PNError.connectionFailed("x")), 8883)

        config.updatePNConfig(host: "a.example", port: 8883, secure: true, token: "t",
                              endpoints: [PNEndpoint(host: "b.example", port: 443)])
        let mixed = PNSocketManager(config: config, appId: "a", deviceId: "d")
        XCTAssertNil(mixed.reportPort(for: PNError.connectionFailed("x")))
    }

    func testReportNet() {
        XCTAssertEqual(ConnectivityMonitor.reportNet(interfaceNames: ["en0"], wifi: true, cellular: false, ethernet: false), "wifi")
        XCTAssertEqual(ConnectivityMonitor.reportNet(interfaceNames: ["pdp_ip0"], wifi: false, cellular: true, ethernet: false), "cellular")
        XCTAssertEqual(ConnectivityMonitor.reportNet(interfaceNames: ["utun3", "en0"], wifi: true, cellular: false, ethernet: false), "vpn")
        XCTAssertEqual(ConnectivityMonitor.reportNet(interfaceNames: ["en1"], wifi: false, cellular: false, ethernet: true), "ethernet")
        XCTAssertEqual(ConnectivityMonitor.reportNet(interfaceNames: [], wifi: false, cellular: false, ethernet: false), "other")
    }

    func testMissingGatewayHostIsCountedAsSetupFailure() {
        let defaults = UserDefaults(suiteName: "SdkErrorReasonTests")!
        defaults.removePersistentDomain(forName: "SdkErrorReasonTests")
        let diag = SdkDiagnostics(defaults: defaults)
        var config = AbrovaPushConfig(apiKey: "k")
        config.updatePNConfig(host: "", port: 8883, secure: true, token: "t", endpoints: [])
        let manager = PNSocketManager(config: config, appId: "a", deviceId: "d",
                                      reportNet: { "cellular" }, diagnostics: diag)
        manager.connect()
        XCTAssertEqual(diag.pending(), [1007: 1])
        XCTAssertEqual(diag.pendingReasons(), ["1007:arg.cellular": 1])
        XCTAssertFalse(manager.isConnected)
    }
}
