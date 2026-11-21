import Foundation
import PNProtocol

/// Manager that wraps PNSocket for the Abrova Push SDK.
/// Replaces the old MqttManager with the new PN Protocol.
internal class PNSocketManager: NSObject {
    static let TAG = "PNSocketManager"
    private var socket: PNSocket?
    private let abrovaPushConfig: AbrovaPushConfig
    private let appId: String
    private let deviceId: String
    private let appIdentifier: String
    private let subscriptionId: String?
    private var hasSubscribedOnce: Bool = false  // Track if initial subscription is done

    // Strong reference to connection listener to prevent deallocation
    private var connectionListener: ConnectionListener?
    // Same for the error listener: the socket holds listeners weakly.
    private var errorListener: PNErrorHandler?

    // Strong references to message handlers to prevent deallocation
    private var messageHandlers: [PNMessageHandler] = []

    weak var delegate: PNSocketManagerDelegate?

    protocol PNSocketManagerDelegate: AnyObject {
        func pnSocketManager(_ manager: PNSocketManager, didConnect success: Bool)
        func pnSocketManager(_ manager: PNSocketManager, didDisconnect error: Error?)
        func pnSocketManager(_ manager: PNSocketManager, didReceiveMessage message: String, channel: String)
    }

    /// Timings for the socket. Keepalive is short so a dead connection on a
    /// lossy network is noticed quickly; the server resends anything missed.
    static let keepAliveSeconds: UInt16 = 30
    static let connectTimeoutSeconds: TimeInterval = 15
    static let pingTimeoutSeconds: TimeInterval = 15

    private let endpointMemory: MqttEndpointMemory
    private let networkKind: () -> NetworkKind
    private let reportNet: () -> String?
    private let diagnostics: SdkDiagnostics
    /// Port of the endpoint the live connection uses (for a lost connection's report).
    private var connectedPort: Int?

    init(
        config: AbrovaPushConfig,
        appId: String,
        deviceId: String,
        appIdentifier: String = "_default",
        subscriptionId: String? = nil,
        endpointMemory: MqttEndpointMemory = MqttEndpointMemory(),
        networkKind: @escaping () -> NetworkKind = { .other },
        reportNet: @escaping () -> String? = { nil },
        diagnostics: SdkDiagnostics = .shared
    ) {
        self.abrovaPushConfig = config
        self.appId = appId
        self.deviceId = deviceId
        self.appIdentifier = appIdentifier
        self.subscriptionId = subscriptionId
        self.endpointMemory = endpointMemory
        self.networkKind = networkKind
        self.reportNet = reportNet
        self.diagnostics = diagnostics
        super.init()
    }

    /// Endpoints to try for the current network type, best first.
    func orderedEndpoints() -> [PNEndpoint] {
        return MqttEndpointOrder.ordered(
            server: abrovaPushConfig.pnEndpoints,
            fallback: abrovaPushConfig.defaultPNEndpoint,
            lastGood: endpointMemory.lastGood(for: networkKind())
        )
    }

    /// Build the socket configuration.
    func makePNConfig(clientId: String) -> PNConfig {
        let c = abrovaPushConfig
        var builder = PNConfigBuilder()
            .gateway(c.pnHost)
            .port(c.pnPort)
            .secure(c.pnSecure)
            .endpoints(orderedEndpoints())
            .clientId(clientId)
            .heartbeatInterval(PNSocketManager.keepAliveSeconds)
            .connectionTimeout(PNSocketManager.connectTimeoutSeconds)
            .pingTimeout(PNSocketManager.pingTimeoutSeconds)
            .freshStart(true)
            .autoReconnect(c.autoReconnect)
            .maxReconnectAttempts(max(0, c.maxReconnectAttempts))  // 0 = never give up
            .reconnectDelay(Double(max(c.initialReconnectDelayMs, 100)) / 1000.0)
            .maxReconnectDelay(Double(max(c.maxReconnectDelayMs, c.initialReconnectDelayMs, 100)) / 1000.0)

        // JWT token auth (per-device authentication)
        if let token = c.pnToken {
            builder = builder.auth(.basic(username: "jwt", password: token))
        }
        return builder.build()
    }

    /// Connect to gateway
    func connect() {
        let bundleHash = String(abs(Bundle.main.bundleIdentifier?.hashValue ?? 0), radix: 16)
        let clientId = "rp_\(appId)_\(deviceId)_\(bundleHash)"

        if abrovaPushConfig.pnToken == nil {
            Log.w(PNSocketManager.TAG, "No PN token available - connection will likely fail with 'notAuthorized'")
        }

        // Nothing to connect to: count it instead of letting the config builder stop the app.
        guard !abrovaPushConfig.pnHost.trimmingCharacters(in: .whitespaces).isEmpty else {
            Log.e(PNSocketManager.TAG, "Connection setup failed: no gateway host")
            diagnostics.record(AbrovaPushErrorCode.connectionSetupFailed.rawValue,
                               reason: "arg", port: nil, net: reportNet())
            return
        }

        let pnConfig = makePNConfig(clientId: clientId)
        Log.d(PNSocketManager.TAG, "connect() - endpoints: \(pnConfig.endpoints)")

        // Initialize AbrovaPush protocol (closes any previous socket first)
        PNProtocolClient.initialize(pnConfig)
        socket = PNProtocolClient.socket()

        // Add connection listener (must keep strong reference to prevent deallocation)
        connectionListener = ConnectionListener(manager: self)
        socket?.addConnectionListener(connectionListener!)

        // Add error listener (strong reference kept, see errorListener)
        let errorListener = PNErrorHandler { [weak self] error in
            Log.e(PNSocketManager.TAG, "\(error.message)")
            self?.countSocketError(error)
        }
        self.errorListener = errorListener
        socket?.addErrorListener(errorListener)

        socket?.open()
    }

    /// Disconnect from gateway
    func disconnect() {
        socket?.close()
        socket = nil
        connectionListener = nil
        errorListener = nil
        connectedPort = nil
        messageHandlers.removeAll()
        hasSubscribedOnce = false  // Reset subscription state
        PNProtocolClient.shutdown()
        Log.d(PNSocketManager.TAG, "Disconnected")
    }

    /// Reconnect now with the backoff reset.
    ///
    /// - Parameter force: also drop a live connection (network path changed).
    ///   Without it a connected socket is only probed with a ping.
    /// After `disconnect()` this opens a new socket.
    func reconnectNow(force: Bool = false) {
        Log.d(PNSocketManager.TAG, "reconnectNow(force: \(force))")
        guard let socket = socket else {
            connect()
            return
        }
        socket.setEndpoints(orderedEndpoints())
        if !force && socket.state == .connected {
            socket.probe()
            return
        }
        socket.reconnect(force: force)
    }

    /// Public code of a socket error for the SDK self-report (the same codes
    /// the Android SDK counts). A connection attempt that could not even be
    /// started is `connectionSetupFailed`.
    static func errorCode(for error: PNError) -> AbrovaPushErrorCode {
        switch error.code {
        case .connectionFailed:
            return error.message == PNErrorShape.failedToInitiate ? .connectionSetupFailed : .connectionFailed
        case .connectionLost: return .connectionLost
        case .authFailed: return .authenticationFailed
        default: return .unknownError
        }
    }

    /// Port for the report: the live connection's for a lost connection; for a
    /// failed attempt the one all endpoints share (unknown when they differ).
    func reportPort(for error: PNError) -> Int? {
        if error.code == .connectionLost, let port = connectedPort { return port }
        let ports = Set(orderedEndpoints().map { Int($0.port) })
        return ports.count == 1 ? ports.first : nil
    }

    /// Counts a socket error with its reason, port and network type.
    private func countSocketError(_ error: PNError) {
        let code = Self.errorCode(for: error)
        diagnostics.count(code, error: error, port: reportPort(for: error), net: reportNet())
        if error.code == .connectionLost { connectedPort = nil }
    }

    /// Remember the endpoint that just worked for this network type.
    private func rememberConnectedEndpoint() {
        guard let endpoint = socket?.connectedEndpoint else { return }
        connectedPort = Int(endpoint.port)
        endpointMemory.remember(endpoint, for: networkKind())
    }

    /// Subscribe to device channels (called only on first connect, not reconnects).
    /// On reconnects, PNSocket.resubscribeChannels() handles re-subscribing
    /// from its activeChannels set automatically.
    private func subscribeToChannels() {
        // Per-install subscription topic — primary delivery channel for every
        // device-targeted message after the subscriptionId migration.
        let subscriptionChannel = subscriptionId.map { "abrova_push/\(appId)/sub/\($0)" }
        let broadcastChannel = "abrova_push/\(appId)/broadcast"

        // DEPRECATED: legacy device-scoped topic. The backend stopped
        // publishing here after the subscriptionId migration. Kept subscribed
        // only to keep older test builds / out-of-tree backends working; will
        // be removed in a future SDK release.
        let deviceChannel = "abrova_push/\(appId)/\(deviceId)/\(appIdentifier)"

        // Shared message handler factory — strong refs are stored in
        // messageHandlers to prevent deallocation while the socket is alive.
        let makeHandler: () -> PNMessageHandler = { [weak self] in
            return PNMessageHandler { [weak self] message in
                guard let self = self else { return }
                let payload = message.payloadAsString()
                // Never the payload itself: it holds the app's message content.
                Log.d(PNSocketManager.TAG, "Message received on \(message.channel) (\(payload.utf8.count) bytes)")
                #if DEBUG
                Log.v(PNSocketManager.TAG, "Message payload: \(payload)")
                #endif
                self.delegate?.pnSocketManager(self, didReceiveMessage: payload, channel: message.channel)
            }
        }

        if let channel = subscriptionChannel {
            let subHandler = makeHandler()
            messageHandlers.append(subHandler)
            Log.d(PNSocketManager.TAG, "Subscribing to \(channel)")
            socket?.stream(channel, mode: .reliable, listener: subHandler)
        }

        let broadcastHandler = makeHandler()
        messageHandlers.append(broadcastHandler)
        Log.d(PNSocketManager.TAG, "Subscribing to \(broadcastChannel)")
        socket?.stream(broadcastChannel, mode: .reliable, listener: broadcastHandler)

        // In-app change signal: the project's in-app messages changed, fetch them again (no polling). It carries
        // no push, so it never reaches the message delegate.
        let signalChannel = "abrova_push/\(appId)/topic/\(PNSocketManager.inAppSignalTopic)"
        let signalHandler = PNMessageHandler { _ in
            Log.d(PNSocketManager.TAG, "In-app messages changed")
            DispatchQueue.main.async { AbrovaPush.shared.handleInAppSignal() }
        }
        messageHandlers.append(signalHandler)
        socket?.stream(signalChannel, mode: .reliable, listener: signalHandler)

        // Legacy stream — DEPRECATED, see comment above.
        let deviceHandler = makeHandler()
        messageHandlers.append(deviceHandler)
        Log.d(PNSocketManager.TAG, "Subscribing to (deprecated) \(deviceChannel)")
        socket?.stream(deviceChannel, mode: .reliable, listener: deviceHandler)

        Log.d(PNSocketManager.TAG, "Subscribed to channels (sub=\(subscriptionChannel != nil), legacy device topic kept for compat)")
    }

    /// Reserved topic the server uses to say the project's in-app messages changed.
    static let inAppSignalTopic = "__in_app"

    var isConnected: Bool {
        return socket?.isConnected() ?? false
    }

    /// Check if the current config matches the given config (host, port, token).
    /// Used to decide whether to reconnect the existing socket or recreate it.
    func hasMatchingConfig(_ config: AbrovaPushConfig) -> Bool {
        return abrovaPushConfig.pnHost == config.pnHost
            && abrovaPushConfig.pnPort == config.pnPort
            && abrovaPushConfig.pnToken == config.pnToken
            && abrovaPushConfig.pnSecure == config.pnSecure
            && abrovaPushConfig.pnEndpoints == config.pnEndpoints
    }

    // MARK: - Connection Listener

    private class ConnectionListener: PNConnectionListener {
        weak var manager: PNSocketManager?

        init(manager: PNSocketManager) {
            self.manager = manager
        }

        func onStateChanged(_ state: PNState) {
            Log.d(PNSocketManager.TAG, "State: \(state)")
        }

        func onConnected() {
            Log.d(PNSocketManager.TAG, "Connected")
            manager?.rememberConnectedEndpoint()
            // Subscribe only on the first connection.
            // On reconnects, PNSocket.resubscribeChannels() handles
            // re-subscribing from its activeChannels set automatically.
            if manager?.hasSubscribedOnce == false {
                manager?.subscribeToChannels()
                manager?.hasSubscribedOnce = true
            } else {
                Log.d(PNSocketManager.TAG, "Reconnected - PNSocket handles resubscription automatically")
            }
            if let manager = manager {
                manager.delegate?.pnSocketManager(manager, didConnect: true)
            }
        }

        func onDisconnected(reason: String?) {
            Log.d(PNSocketManager.TAG, "Disconnected: \(reason ?? "unknown")")
            if let manager = manager {
                manager.delegate?.pnSocketManager(manager, didDisconnect: nil)
            }
        }

        func onReconnecting(attempt: Int, nextRetryMs: Int) {
            Log.d(PNSocketManager.TAG, "Reconnecting: attempt=\(attempt)")
        }
    }
}
