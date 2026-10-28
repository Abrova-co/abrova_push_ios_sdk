import Foundation

/// SDK public configuration - these are the production Abrova Push server endpoints.
/// These values are public and shipped with the SDK.
internal struct SdkCredentials {
    /// Production API URL - public endpoint for SDK users
    static let apiUrl = "https://push-api.abrova.ir"

    /// Production PN Protocol gateway host - public endpoint for real-time messaging
    static let pnHost = "pn-tcp.abrova.ir"

    /// Production PN Protocol gateway port (TLS)
    static let pnPort: UInt16 = 8883

    /// Enable TLS/SSL by default for secure connections
    static let pnSecure: Bool = true
}
