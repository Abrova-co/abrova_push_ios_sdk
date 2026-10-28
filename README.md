# Abrova Push iOS SDK

Native iOS SDK for real-time push notifications via pn-protocol. No Firebase dependency.

## Features

- Real-time push via pn-protocol
- APNs support for background delivery
- Rich notifications with images and action buttons
- In-app messaging (modal, banner, fullscreen, card)
- Message inbox with persistent storage
- Topic subscription for targeted messaging
- A/B testing support
- User segmentation
- Analytics and delivery tracking
- VoIP push support (optional)

## Installation

The SDK is published on [Abrova Center](https://center.abrova.ir).

### Swift Package Manager (recommended)

In Xcode: File → Add Package Dependencies → Enter:

```
https://center.abrova.ir/abrova/abrova-push-ios-sdk.git
```

Select version `0.1.19` or later.

### CocoaPods

The SDK and the protocol package it uses both come from Abrova Center:

```ruby
pod 'PNProtocol', :git => 'https://center.abrova.ir/abrova/pn-protocol-ios.git', :tag => '0.2.2'
pod 'AbrovaPushSDK', :git => 'https://center.abrova.ir/abrova/abrova-push-ios-sdk.git', :tag => '0.1.19'
```

## Quick Start

### 1. Initialize in AppDelegate

```swift
import AbrovaPush

func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

    let config = AbrovaPushConfig(apiKey: "your_api_key_here")
    AbrovaPush.shared.initialize(config: config)
    AbrovaPush.shared.delegate = self

    // Request notification permission
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
        if granted {
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    // Register device
    AbrovaPush.shared.register(userId: "user_123") // userId is optional

    return true
}
```

### 2. Forward APNs token

```swift
func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    AbrovaPush.shared.setAPNsToken(deviceToken)
}
```

### 3. Set up delegate

```swift
extension AppDelegate: AbrovaPushDelegate {

    func abrovaPush(_ abrovaPush: AbrovaPush, didRegisterWithDeviceId deviceId: String) {
        print("Registered: \(deviceId)")
    }

    func abrovaPush(_ abrovaPush: AbrovaPush, didReceiveMessage message: AbrovaPushMessage) {
        print("Message: \(message.title ?? "")")
    }

    func abrovaPush(_ abrovaPush: AbrovaPush, didTapNotification message: AbrovaPushMessage) {
        // Handle notification tap
    }

    func abrovaPush(_ abrovaPush: AbrovaPush, didChangeConnectionState connected: Bool) {
        print("Connected: \(connected)")
    }

    func abrovaPush(_ abrovaPush: AbrovaPush, didFailWithError error: Error) {
        print("Error: \(error)")
    }
}
```

## Device Management

### User ID

```swift
// Set user ID (after login)
AbrovaPush.shared.setUserId("user_123")

// Clear user ID (after logout)
AbrovaPush.shared.clearUserId()
```

### Signed user tokens

Optional. If your backend issues Abrova user tokens, give the SDK a `tokenProvider` and it sends the token with every request, so the server can verify which user a device belongs to. It is the same token, and the same function, you pass to Abrova Chat.

```swift
// Returns the token from your backend, or nil when no user is signed in.
let tokenProvider: () async throws -> String? = {
    try await MyBackend.fetchAbrovaToken()
}

let config = AbrovaPushConfig(apiKey: "ab_live_your_api_key", tokenProvider: tokenProvider)
AbrovaPush.shared.initialize(config: config)

AbrovaPush.shared.onAuthError = { event in
    print("Abrova token problem: \(event.code)")  // e.g. send the user to login
}
```

The SDK caches the token, renews it shortly before it expires and forgets it on `clearUserId()`. You can also set the provider later with `setTokenProvider(_:)`, or pass a token you fetched yourself with `setUserToken(_:)`. Without a provider nothing changes.

### Topics

```swift
// Subscribe
AbrovaPush.shared.subscribeTopic("news")

// Unsubscribe
AbrovaPush.shared.unsubscribeTopic("news")
```

## In-App Messages

```swift
// Trigger messages
AbrovaPush.shared.triggerInAppOnAppOpen()
AbrovaPush.shared.triggerInAppEvent("viewed_product")

// Set up callback
AbrovaPush.shared.setInAppMessageCallback(handler)
```

## Message Inbox

```swift
// Fetch messages
AbrovaPush.shared.getInboxMessages(
    filter: InboxFilter(limit: 50),
    onSuccess: { response in
        let messages = response.messages
        let unread = response.unreadCount
    },
    onError: { error in print(error) }
)

// Real-time updates
AbrovaPush.shared.setInboxCallback(handler)

// Mark as read
AbrovaPush.shared.markInboxMessageAsRead(messageId: "msg_123")

// Get unread count
let count = AbrovaPush.shared.getInboxManager().getUnreadCount()
```

## A/B Testing

```swift
let manager = AbrovaPush.shared.getABTestingManager()

// Get active tests
manager.getActiveTests { result in
    // handle tests
}

// Get variant assignment
manager.getVariant(testId: "test_123") { result in
    if case .success(let variant) = result {
        print("Assigned to: \(variant.variantName)")
    }
}

// Track events
manager.trackEvent(testId: "test_123", variantId: "variant_456", event: .clicked) { _ in }
```

## Configuration

```swift
let config = AbrovaPushConfig.builder(apiKey: "your_key")
    .usePushKit(false)           // VoIP push (only for calling apps)
    .useAPNs(true)               // Standard APNs (recommended)
    .showNotificationInForeground(true)
    .autoConnect(true)
    .autoReconnect(true)
    .build()
```

| Option | Default | Description |
|--------|---------|-------------|
| `usePushKit` | `false` | Enable VoIP push (calling apps only) |
| `useAPNs` | `true` | Enable standard APNs |
| `showNotificationInForeground` | `false` | Show notifications when app is active |
| `autoConnect` | `true` | Auto-connect when app enters foreground |
| `autoReconnect` | `true` | Auto-reconnect with exponential backoff |
| `autoRefresh` | `true` | Refresh the registration on launch when it may be stale (see below) |
| `sendDiagnostics` | `true` | Send counts of the SDK's own errors (by error code, no personal data) with its requests |
| `appGroup` | `nil` | App Group shared with a Notification Service Extension, for delivery confirmation |

### Automatic registration refresh

Once this install has registered, `initialize(config:)` keeps the server's device record fresh on its own. It re-sends the registration in the background when 24 hours have passed since the last successful one, or when the app version or build, the SDK version, the push token or the user id has changed; otherwise it does nothing. It never prompts for notification permission, and only runs when permission was already granted. An explicit `register()` always registers. Turn it off with `autoRefresh: false`.

## Delivery Confirmation

APNs only confirms that Apple *accepted* a notification, not that it reached the device. The SDK reports a real delivery (`POST /receipts/delivered`) whenever it sees a message:

| How the message arrived | Reported by | Needs |
|--------|---------|-------------|
| SDK socket (app in foreground) | the SDK | nothing |
| APNs, app in foreground | the SDK, from `willPresent` | the SDK as `UNUserNotificationCenter` delegate, or a call to `handleRemoteNotification(userInfo:)` from your own |
| APNs, user taps it | the SDK, from `handleNotificationResponse` | nothing |
| APNs, app in background or not running | your Notification Service Extension | `AbrovaPushSDKExtension` + an App Group |

iOS does not run your app when a notification arrives in the background, so **background APNs deliveries are confirmed only with a Notification Service Extension**. Add the extension target, `pod 'AbrovaPushSDKExtension'` to it, enable the same App Group on both targets, pass it as `appGroup` in the config, and call `AbrovaPushServiceExtension.didReceive(_:apiKey:appGroup:)` from the extension (see the doc comment on `AbrovaPushServiceExtension`).

Each message is reported once: the app and the extension share a small list of reported message ids through the App Group, so a notification the extension already confirmed is not reported again when the app shows or opens it.

If you handle silent pushes, forward them too:

```swift
func application(_ application: UIApplication,
                 didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                 fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
    AbrovaPush.shared.handleRemoteNotification(userInfo: userInfo)
    completionHandler(.noData)
}
```

### Wrapper SDKs

`wrapperSdkName` / `wrapperSdkVersion` exist for Abrova's official Flutter and React Native wrappers, which report their own identity instead of the native one. Apps should not set them. `AbrovaPush.sdkVersion` returns the native SDK version.

## Requirements

- iOS 13.0+
- Swift 5.7+
- Xcode 14+

## VoIP Push (Optional)

For calling apps (Jitsi, WebRTC), add the [AbrovaPush VoIP SDK](https://github.com/Abrova-co/abrova_push_voip_ios_sdk):

```swift
// Swift Package Manager
.package(url: "https://center.abrova.ir/abrova/abrova-push-voip-ios-sdk.git", from: "0.1.2")

// CocoaPods
pod 'AbrovaPushVoip', :git => 'https://center.abrova.ir/abrova/abrova-push-voip-ios-sdk.git', :tag => '0.1.2'
```

```swift
import AbrovaPushVoip

// Initialize VoIP SDK
let voipConfig = VoipConfig(appName: "MyApp", supportsVideo: true)
AbrovaPushVoip.shared.initialize(config: voipConfig)
AbrovaPushVoip.shared.delegate = self

// Enable VoIP in AbrovaPush config
let config = AbrovaPushConfig.builder(apiKey: "ab_live_your_api_key")
    .usePushKit(true)
    .build()
```

```swift
extension AppDelegate: AbrovaPushVoipDelegate {
    func voip(_ voip: AbrovaPushVoip, didAcceptCall callData: VoipCallData) {
        // Connect to your calling service
    }

    func voip(_ voip: AbrovaPushVoip, didDeclineCall callData: VoipCallData) {
        // Handle decline
    }
}
```

To trigger an incoming call, send a push with `type: "voip_call"` in the data:

```json
{
  "title": "Incoming Call",
  "body": "John Doe is calling",
  "data": {
    "type": "voip_call",
    "callerName": "John Doe",
    "callerId": "user_456",
    "callerAvatar": "https://example.com/avatar.jpg",
    "callType": "video"
  }
}
```

The `type: "voip_call"` triggers VoIP delivery (PushKit). Without it, the message is delivered as a regular push notification. See the [VoIP SDK README](https://github.com/Abrova-co/abrova_push_voip_ios_sdk) for full setup guide.

The Push SDK works independently without VoIP. VoIP is only needed for apps with real calling features.

## Example App

The `Example/` folder contains a complete demo app with:
- Push notification receiving
- In-app message triggers
- Inbox management
- A/B test variant assignment
- VoIP calling (toggle on/off)
- Settings and debugging tools

## Links

- [Abrova Push](https://abrova.ir/cloud/abrova-push) - Learn more about Abrova Push
- [Documentation](https://abrova.ir/cloud/abrova-push/docs/quick-start) - Full documentation and guides
- [Abrova Console](https://console.abrova.ir) - Manage your push notifications

## License

MIT License - see [LICENSE](LICENSE) for details.
