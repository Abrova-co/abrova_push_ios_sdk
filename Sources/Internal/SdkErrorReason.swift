import Foundation
import PNProtocol

/// Turns an error into one short reason word for the SDK self-report
/// (`X-Abrova-SDK-Report-Reasons`).
///
/// The word comes only from a fixed list and is chosen by error type, domain
/// and numeric code — never from a message, host, address, URL, topic, user,
/// device or app value. The cause chain is walked (up to 8 levels), every
/// matching word is collected, and the one with the highest priority wins.
internal enum SdkErrorReason {
    /// Domain of the internal error that carries an API answer's HTTP status as its code.
    static let httpErrorDomain = "ir.abrova.push.http"

    /// How deep the cause chain is followed.
    static let maxDepth = 8

    /// Priority after `mqtt<N>` / `http<NNN>` (which always win), best first.
    static let priority: [String] = [
        "cert", "tls_handshake", "tls", "timeout", "dns", "refused", "noroute", "offline",
        "reset", "eof", "socket", "parse", "state", "arg", "security", "oom", "cancelled",
    ]

    /// Network type words the report accepts.
    static let netWords: Set<String> = ["wifi", "cellular", "ethernet", "vpn", "none", "other"]

    /// An error carrying an HTTP status, for `http<NNN>`.
    static func httpError(status: Int) -> NSError {
        return NSError(domain: httpErrorDomain, code: status, userInfo: nil)
    }

    /// The reason word for `error`, `other` when nothing matches.
    static func classify(_ error: Error?) -> String {
        var found: [String] = []
        var current = error
        var depth = 0
        while let e = current, depth < maxDepth {
            if let word = word(for: e) { found.append(word) }
            current = underlying(of: e)
            depth += 1
        }
        // A numeric MQTT/HTTP code is the most specific; the first one in the chain wins.
        if let numeric = found.first(where: { $0.hasPrefix("mqtt") || $0.hasPrefix("http") }) {
            return numeric
        }
        for word in priority where found.contains(word) { return word }
        return "other"
    }

    // MARK: - One level

    private static func word(for error: Error) -> String? {
        // Swift types first: casting any Error to NSError always succeeds.
        if let pn = error as? PNError { return word(for: pn) }
        if let sdk = error as? AbrovaPushError { return word(for: sdk.errorCode) }
        if error is DecodingError || error is EncodingError { return "parse" }
        if let url = error as? URLError { return urlWord(url.code.rawValue) }

        let ns = error as NSError
        switch ns.domain {
        case httpErrorDomain:
            return ns.code >= 400 && ns.code <= 599 ? "http\(ns.code)" : nil
        case NSURLErrorDomain:
            return urlWord(ns.code)
        case NSPOSIXErrorDomain:
            return posixWord(Int32(ns.code))
        case "kCFStreamErrorDomainNetDB":
            return "dns"
        case "kCFStreamErrorDomainSSL", NSOSStatusErrorDomain:
            return sslWord(ns.code)
        case "kCFErrorDomainCFNetwork":
            return cfNetworkWord(ns.code)
        case "MGCDAsyncSocketErrorDomain", "GCDAsyncSocketErrorDomain":
            return asyncSocketWord(ns.code)
        case NSCocoaErrorDomain:
            return cocoaWord(ns.code)
        default:
            return nil
        }
    }

    private static func underlying(of error: Error) -> Error? {
        if let pn = error as? PNError { return pn.underlyingError }
        if let sdk = error as? AbrovaPushError { return sdk.cause }
        if let decoding = error as? DecodingError {
            switch decoding {
            case .typeMismatch(_, let c), .valueNotFound(_, let c), .keyNotFound(_, let c), .dataCorrupted(let c):
                return c.underlyingError
            @unknown default:
                return nil
            }
        }
        let ns = error as NSError
        return ns.userInfo[NSUnderlyingErrorKey] as? Error
    }

    // MARK: - Mappings

    /// PN protocol errors. Its numeric codes are its own, not MQTT reason codes,
    /// so they map to words; the broker's CONNACK code becomes `mqtt<N>`.
    private static func word(for error: PNError) -> String? {
        if let ack = connAckCode(error) { return "mqtt\(ack)" }
        switch error.code {
        case .connectionTimeout: return "timeout"
        case .notConnected: return "state"
        case .invalidConfig: return "arg"
        case .invalidMessage: return "parse"
        case .authExpired: return "security"
        default:
            // The connect timer of PN protocol 0.2.x has no own code.
            return error.message == PNErrorShape.connectTimedOut ? "timeout" : nil
        }
    }

    /// CONNACK return code (1-5) of a broker rejection. PN protocol 0.2.x
    /// passes it only in its own fixed text "Connection rejected: <name>",
    /// matched here exactly against CocoaMQTT's case names.
    static func connAckCode(_ error: PNError) -> Int? {
        let prefix = PNErrorShape.rejectedPrefix
        guard error.message.hasPrefix(prefix) else { return nil }
        let name = String(error.message.dropFirst(prefix.count))
        return PNErrorShape.connAckCodes[name]
    }

    private static func word(for code: AbrovaPushErrorCode) -> String? {
        switch code {
        case .messageParseError: return "parse"
        case .notInitialized, .notConnected, .alreadyConnected, .serviceNotRunning: return "state"
        case .invalidConfig, .missingApiKey, .missingServerUrl, .invalidTopic: return "arg"
        case .connectionTimeout, .messageTimeout: return "timeout"
        default: return nil
        }
    }

    private static func urlWord(_ code: Int) -> String? {
        switch code {
        case NSURLErrorTimedOut: return "timeout"
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: return "dns"
        case NSURLErrorCannotConnectToHost: return "refused"
        case NSURLErrorNotConnectedToInternet, NSURLErrorInternationalRoamingOff,
             NSURLErrorCallIsActive, NSURLErrorDataNotAllowed: return "offline"
        case NSURLErrorNetworkConnectionLost: return "eof"
        case NSURLErrorSecureConnectionFailed: return "tls_handshake"
        case NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateUntrusted,
             NSURLErrorServerCertificateHasUnknownRoot, NSURLErrorServerCertificateNotYetValid: return "cert"
        case NSURLErrorClientCertificateRejected, NSURLErrorClientCertificateRequired: return "tls"
        case NSURLErrorBadServerResponse, NSURLErrorCannotParseResponse,
             NSURLErrorCannotDecodeRawData, NSURLErrorCannotDecodeContentData: return "parse"
        case NSURLErrorBadURL, NSURLErrorUnsupportedURL: return "arg"
        case NSURLErrorAppTransportSecurityRequiresSecureConnection: return "security"
        case NSURLErrorCancelled: return "cancelled"
        default: return nil
        }
    }

    private static func posixWord(_ code: Int32) -> String? {
        switch code {
        case ETIMEDOUT: return "timeout"
        case ECONNREFUSED: return "refused"
        case ENETUNREACH, EHOSTUNREACH, ENETDOWN: return "noroute"
        case ECONNRESET, ECONNABORTED, EPIPE: return "reset"
        case ENOMEM: return "oom"
        case ECANCELED: return "cancelled"
        case EACCES, EPERM: return "security"
        case EINVAL: return "arg"
        default: return "socket"
        }
    }

    /// SecureTransport / TLS status codes (-9800 ... -9899).
    private static func sslWord(_ code: Int) -> String? {
        switch code {
        case -9807, // errSSLXCertChainInvalid
             -9808, // errSSLBadCert
             -9812, // errSSLUnknownRootCert
             -9813, // errSSLNoRootCert
             -9814, // errSSLCertExpired
             -9815, // errSSLCertNotYetValid
             -9825, // errSSLPeerBadCert
             -9826, // errSSLPeerUnsupportedCert
             -9827, // errSSLPeerCertRevoked
             -9828, // errSSLPeerCertExpired
             -9829, // errSSLPeerCertUnknown
             -9836, // errSSLPeerUnknownCA
             -9843: // errSSLHostNameMismatch
            return "cert"
        case -9824: // errSSLHandshakeFail
            return "tls_handshake"
        case -9806: // errSSLClosedAbort
            return "reset"
        case -9805: // errSSLClosedGraceful
            return "eof"
        case -9899 ... -9800:
            return "tls"
        default:
            return nil
        }
    }

    private static func cfNetworkWord(_ code: Int) -> String? {
        switch code {
        case 1, 2: return "dns" // kCFHostErrorHostNotFound, kCFHostErrorUnknown
        default: return urlWord(code)
        }
    }

    private static func asyncSocketWord(_ code: Int) -> String? {
        switch code {
        case 1, 2: return "arg"            // bad config, bad param
        case 3, 4, 5: return "timeout"     // connect / read / write timeout
        case 7: return "eof"               // closed by the peer
        case 6, 8: return "socket"         // read maxed out, other
        default: return nil
        }
    }

    private static func cocoaWord(_ code: Int) -> String? {
        switch code {
        case NSPropertyListReadCorruptError, NSCoderReadCorruptError, NSCoderValueNotFoundError: return "parse"
        case NSUserCancelledError: return "cancelled"
        default: return nil
        }
    }
}

/// Fixed texts of PN protocol 0.2.x errors that carry no code of their own.
/// Compared exactly; never sent anywhere.
internal enum PNErrorShape {
    static let connectTimedOut = "Connection timed out"
    static let failedToInitiate = "Failed to initiate connection"
    static let rejectedPrefix = "Connection rejected: "
    static let connAckCodes: [String: Int] = [
        "unacceptableProtocolVersion": 1,
        "identifierRejected": 2,
        "serverUnavailable": 3,
        "badUsernameOrPassword": 4,
        "notAuthorized": 5,
    ]
}
