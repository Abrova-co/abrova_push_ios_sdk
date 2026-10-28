import Foundation

/// Reconnection state information
public struct ReconnectionState {
    public let attempt: Int
    public let nextRetryMs: Int64

    public init(attempt: Int, nextRetryMs: Int64) {
        self.attempt = attempt
        self.nextRetryMs = nextRetryMs
    }

    public func toDictionary() -> [String: Any] {
        return [
            "attempt": attempt,
            "nextRetryMs": nextRetryMs
        ]
    }
}

/// Network state information
public struct NetworkState {
    public let isAvailable: Bool
    public let networkType: String

    public init(isAvailable: Bool, networkType: String) {
        self.isAvailable = isAvailable
        self.networkType = networkType
    }

    public func toDictionary() -> [String: Any] {
        return [
            "isAvailable": isAvailable,
            "networkType": networkType
        ]
    }
}

/// App state information
public struct AppState {
    public let isInForeground: Bool

    public init(isInForeground: Bool) {
        self.isInForeground = isInForeground
    }

    public func toDictionary() -> [String: Any] {
        return ["isInForeground": isInForeground]
    }
}

/// App update information
public struct AppUpdateInfo {
    public let previousVersion: String
    public let currentVersion: String
    public let needsReregistration: Bool

    public init(previousVersion: String, currentVersion: String, needsReregistration: Bool) {
        self.previousVersion = previousVersion
        self.currentVersion = currentVersion
        self.needsReregistration = needsReregistration
    }

    public func toDictionary() -> [String: Any] {
        return [
            "previousVersion": previousVersion,
            "currentVersion": currentVersion,
            "needsReregistration": needsReregistration
        ]
    }
}

/// Delegate protocol for AbrovaPush events
public protocol AbrovaPushDelegate: AnyObject {
    /// Called when a push message is received
    func abrovaPush(_ abrovaPush: AbrovaPush, didReceiveMessage message: AbrovaPushMessage)

    /// Called when connection state changes (MQTT)
    func abrovaPush(_ abrovaPush: AbrovaPush, didChangeConnectionState connected: Bool)

    /// Called when device is registered successfully
    func abrovaPush(_ abrovaPush: AbrovaPush, didRegisterWithDeviceId deviceId: String)

    /// Called when VoIP token is received
    func abrovaPush(_ abrovaPush: AbrovaPush, didReceiveVoIPToken token: String)

    /// Called when APNs device token is received
    func abrovaPush(_ abrovaPush: AbrovaPush, didReceiveAPNsToken token: String)

    /// Called when an error occurs (simple string message)
    func abrovaPush(_ abrovaPush: AbrovaPush, didFailWithError error: Error)

    /// Called when a detailed error occurs with error codes
    func abrovaPush(_ abrovaPush: AbrovaPush, didFailWithDetailedError error: AbrovaPushError)

    /// Called when the SDK is automatically retrying connection with exponential backoff
    func abrovaPush(_ abrovaPush: AbrovaPush, didStartReconnecting state: ReconnectionState)

    /// Called when network connectivity changes
    func abrovaPush(_ abrovaPush: AbrovaPush, didChangeNetworkState state: NetworkState)

    /// Called when the app transitions between foreground and background
    func abrovaPush(_ abrovaPush: AbrovaPush, didChangeAppState state: AppState)

    /// Called when the SDK detects the app was updated
    func abrovaPush(_ abrovaPush: AbrovaPush, didDetectAppUpdate info: AppUpdateInfo)

    /// Called when a notification action button is clicked
    func abrovaPush(_ abrovaPush: AbrovaPush, didReceiveNotificationAction action: NotificationAction, forMessage message: AbrovaPushMessage)

    /// Called when a notification is tapped (for real-time handling when app is in foreground)
    func abrovaPush(_ abrovaPush: AbrovaPush, didTapNotification message: AbrovaPushMessage)

    /// Called when the server refuses the signed user token, or the token provider fails
    func abrovaPush(_ abrovaPush: AbrovaPush, didFailWithAuthError event: AbrovaPushAuthErrorEvent)
}

/// Default implementations (all optional)
public extension AbrovaPushDelegate {
    func abrovaPush(_ abrovaPush: AbrovaPush, didReceiveMessage message: AbrovaPushMessage) {}
    func abrovaPush(_ abrovaPush: AbrovaPush, didChangeConnectionState connected: Bool) {}
    func abrovaPush(_ abrovaPush: AbrovaPush, didRegisterWithDeviceId deviceId: String) {}
    func abrovaPush(_ abrovaPush: AbrovaPush, didReceiveVoIPToken token: String) {}
    func abrovaPush(_ abrovaPush: AbrovaPush, didReceiveAPNsToken token: String) {}
    func abrovaPush(_ abrovaPush: AbrovaPush, didFailWithError error: Error) {}
    func abrovaPush(_ abrovaPush: AbrovaPush, didFailWithDetailedError error: AbrovaPushError) {
        // Default: delegate to simple error handler
        self.abrovaPush(abrovaPush, didFailWithError: error)
    }
    func abrovaPush(_ abrovaPush: AbrovaPush, didStartReconnecting state: ReconnectionState) {}
    func abrovaPush(_ abrovaPush: AbrovaPush, didChangeNetworkState state: NetworkState) {}
    func abrovaPush(_ abrovaPush: AbrovaPush, didChangeAppState state: AppState) {}
    func abrovaPush(_ abrovaPush: AbrovaPush, didDetectAppUpdate info: AppUpdateInfo) {}
    func abrovaPush(_ abrovaPush: AbrovaPush, didReceiveNotificationAction action: NotificationAction, forMessage message: AbrovaPushMessage) {}
    func abrovaPush(_ abrovaPush: AbrovaPush, didTapNotification message: AbrovaPushMessage) {}
    func abrovaPush(_ abrovaPush: AbrovaPush, didFailWithAuthError event: AbrovaPushAuthErrorEvent) {}
}
