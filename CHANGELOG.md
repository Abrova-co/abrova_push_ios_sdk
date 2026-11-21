# Changelog

## [0.1.23] - 2026-11-22
### Added
- Notifications turned off: `AbrovaPush.shared.areNotificationsEnabled(completion:)`,
  `setNotificationPermissionListener(_:)` (checked at `initialize` and each time the app becomes active, e.g. back
  from Settings) and `openNotificationSettings()` (this app's notification settings on iOS 16+, the app's settings
  page before). The SDK also tells Abrova, so the Console shows these devices and why their messages were not seen.
- In-app messages update at once: when you publish or change one in the Console, apps that are open fetch the list
  again within a minute and show a message whose trigger is session start. Unchanged lists cost almost nothing.
- Banner position: `InAppMessageContent.position` (`top` or `bottom`, as chosen in the Console); translations keep it.
### Changed
- The built-in in-app display looks like the Console's preview: image 2:1 in a modal and full screen, 3:1 in a card,
  a small square in a banner; a banner at the top or the bottom with its buttons; a card at the bottom without dimming;
  close button on the panel corner (left for right-to-left text); button styles as in the Console.
- The registration refresh at launch also runs when notifications are not allowed (it never asks for permission).
### Fixed
- A banner or card no longer dims and blocks the app behind it.
- After a message was handed to a Flutter or React Native app, no later in-app message could show in that session.

## [0.1.22] - 2026-11-18

### Added
- With `sendDiagnostics` on (default), error reports now also say why a connection failed: a short reason from a fixed
  list (for example timeout, dns, tls), the port and the network type (Wi-Fi/mobile). Never a message, address, user
  or device detail.
- New error code 1007 `connectionSetupFailed`: a connection that could not be set up before any network traffic.

### Fixed
- Connection errors are now included in the error reports.
- A missing gateway host no longer stops the app; it is reported as `connectionSetupFailed`.

### Security
- Tokens are never written to logs.

## [0.1.21] - 2026-11-15

### Added
- Chat-style (communication) notifications: `AbrovaPushConversation` and
  `AbrovaPushServiceExtension.conversationContent(for:completion:)`. A message whose data has a `conversationId` is
  grouped by conversation, and on iOS 15+ shows the sender's photo and name (INSendMessageIntent). Keys: `conversationId` (required), `senderName`, `senderId`, `senderAvatarUrl`, `conversationTitle`, `conversationIsGroup`.
  The photo needs the app's Communication Notifications capability and `INSendMessageIntent` in
  `NSUserActivityTypes`; messages shown by the SDK itself get the same treatment. Messages without `conversationId`
  look as before.

## [0.1.20] - 2026-11-06

### Added
- Notification channels: `AbrovaPushMessage.channelId` and `channel`. When the SDK shows a message itself, the
  channel's interruption level (iOS 15+: passive, active, time-sensitive) and sound apply. Over APNs, Abrova sets the
  interruption level. `sound: "none"` now shows the notification without a sound.

## [0.1.19] - 2026-10-29

### Fixed
- A notification is shown only once, even when the same message arrives twice (for example after a reconnect, or over both the connection and PushKit).

## [0.1.18] - 2026-10-28

### Added
- Opened, clicked and dismissed tracking: a tap on a notification is reported as `opened`, a tap on an action button as `clicked` (with the action's id). `dismissed` is reported when iOS tells the app, which it does only for notification categories registered with `.customDismissAction`. Done automatically by `handleNotificationResponse(userInfo:actionIdentifier:)` and the SDK's own notification delegate; sent in the background once per message and never delays opening the app.
- `reportNotificationResponse(userInfo:actionIdentifier:)` for apps that handle notification responses themselves without calling `handleNotificationResponse`.

### Changed
- Connection logs now follow `AbrovaPushLogger.logLevel` instead of always printing, and never include message content outside debug builds.

## [0.1.17] - 2026-10-14

### Added
- `sendDiagnostics` (default `true`): the SDK sends counts of its own errors, by error code, with its next request. Counts only, no personal data.
- Privacy manifests (`PrivacyInfo.xcprivacy`) for `AbrovaPushSDK` and `AbrovaPushSDKExtension`.

### Changed
- Inside the Flutter or React Native SDK, requests also name the native SDK version.

## [0.1.16] - 2026-10-02

### Changed
- The signed user token is kept in the Keychain instead of UserDefaults. A token saved by 0.1.15 is moved over on first launch.

## [0.1.15] - 2026-10-02

### Added
- Signed user tokens (optional): `tokenProvider` in the config, `setTokenProvider(_:)` and `setUserToken(_:)`. The token is sent as `x-user-token` on every request, renewed before it expires and retried once when the server reports it expired.
- `onAuthError` and the delegate's `didFailWithAuthError` report a refused token or a failing provider.

Apps that do not set a token provider are not affected.

## [0.1.14] - 2026-09-29

### Changed
- Faster, steadier realtime connection on poor networks: reconnects right away when the network returns or changes and when the app comes to the foreground; retries back off to at most 60 seconds and never stop; dead connections are detected sooner.
- Supports extra gateway addresses from the server, with automatic failover.

### Fixed
- The realtime connection did not come back after the app returned from the background.

## [0.1.13] - 2026-09-18

### Added
- `installId` on register, so a reinstall no longer leaves a stale device behind.

## [0.1.12] - 2026-09-14

### Added
- SDK identity: the SDK reports its name and version (`AbrovaPush.sdkVersion`).
- `autoRefresh` (default on): keeps a registered device up to date on launch. Never asks for permission.
- Delivery confirmation from the app: foreground notifications, socket messages and taps. `handleRemoteNotification(userInfo:)` for apps with their own notification delegate.

### Fixed
- `unregister()` now detaches the user on the server, so a logged-out user stops receiving pushes.

### Changed
- Delivery confirmations are sent once per message, shared with the Notification Service Extension through the App Group.

## [0.1.11] - 2026-09-09

### Fixed
- 0.1.10's `AbrovaPushSDK/Extension` subspec crashed apps at launch with `Symbol not found: AbrovaPushSDK.AbrovaPush.shared`. Both subspecs built a framework named `AbrovaPushSDK`, so the extension's cut-down copy overwrote the app's when embedded. The extension half now ships as a separate pod, `AbrovaPushSDKExtension`, with its own module name.

### Changed
- **Migration from 0.1.10:** in your extension target, replace `pod 'AbrovaPushSDK/Extension'` with `pod 'AbrovaPushSDKExtension'`, and `import AbrovaPushSDK` with `import AbrovaPushSDKExtension`.

## [0.1.10] - 2026-09-08

### Fixed
- `AbrovaPushSDK` could not be linked into a Notification Service Extension — the SDK uses `UIApplication.shared`, which app extensions may not call, so delivery confirmation did not build. The pod is now split: `AbrovaPushSDK` (unchanged, for your app) and `AbrovaPushSDK/Extension`, which carries only `AbrovaPushServiceExtension` and is extension-safe.

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.9] - 2026-09-08

### Added
- Delivery confirmation from a Notification Service Extension. Set `appGroup` in the config and the SDK shares the device identity with the extension, so the server learns a notification actually arrived.
- `appGroup` on `AbrovaPushConfig.builder()`.

### Fixed
- `AbrovaPushServiceExtension` was missing from the Swift Package Manager sources list, so SPM users could not reference it. CocoaPods was unaffected.
- A VoIP token could linger on the device record when PushKit was disabled.

## [0.1.8] - 2026-08-23

### Added
- App build number captured alongside app version.

## [0.1.7] - 2026-08-23

### Added
- Device attributes captured automatically for segment filters.
