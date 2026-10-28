import UIKit
import UserNotifications
import AbrovaPush

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    static let apiKeyKey = "AbrovaPushSavedApiKey"
    static let userIdKey = "AbrovaPushSavedUserId"

    /// Pre-filled so the example runs without going through onboarding.
    /// Replace with your own key from the Abrova Console.
    static let defaultApiKey = "ab_live_your_api_key"

    static var savedApiKey: String? {
        get { UserDefaults.standard.string(forKey: apiKeyKey) ?? defaultApiKey }
        set { UserDefaults.standard.set(newValue, forKey: apiKeyKey) }
    }

    static var savedUserId: String? {
        get { UserDefaults.standard.string(forKey: userIdKey) }
        set { UserDefaults.standard.set(newValue, forKey: userIdKey) }
    }

    static var isConfigured: Bool {
        guard let key = savedApiKey else { return false }
        return !key.isEmpty
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        #if DEBUG
        AbrovaPush.shared.setLogLevel(.debug)
        #else
        AbrovaPush.shared.setLogLevel(.error)
        #endif

        UNUserNotificationCenter.current().delegate = self

        // If already configured, initialize SDK
        if AppDelegate.isConfigured {
            AppDelegate.initializeSDK()
        }

        return true
    }

    static var isVoipEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "voip_enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "voip_enabled") }
    }

    static func initializeSDK() {
        guard let apiKey = savedApiKey, !apiKey.isEmpty else { return }

        let config = AbrovaPushConfig.builder(apiKey: apiKey)
            .usePushKit(isVoipEnabled)
            .showNotificationInForeground(true)
            .autoConnect(true)
            .build()

        AbrovaPush.shared.initialize(config: config)
        AbrovaPush.shared.delegate = UIApplication.shared.delegate as? AbrovaPushDelegate

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }

        AbrovaPush.shared.register(userId: savedUserId)
        print("[AbrovaPush] SDK initialized with key: \(String(apiKey.prefix(12)))...")
    }

    // MARK: - Scene
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {}

    // MARK: - APNs
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("[AbrovaPush] APNs token: \(token)")
        AbrovaPush.shared.setAPNsToken(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[AbrovaPush] APNs failed: \(error.localizedDescription)")
    }
}

// MARK: - AbrovaPushDelegate
extension AppDelegate: AbrovaPushDelegate {

    func abrovaPush(_ abrovaPush: AbrovaPush, didRegisterWithDeviceId deviceId: String) {
        NotificationCenter.default.post(name: .abrovaPushRegistered, object: nil, userInfo: ["deviceId": deviceId])
    }

    func abrovaPush(_ abrovaPush: AbrovaPush, didReceiveMessage message: AbrovaPushMessage) {
        NotificationCenter.default.post(name: .abrovaPushMessageReceived, object: nil, userInfo: ["message": message])
    }

    func abrovaPush(_ abrovaPush: AbrovaPush, didTapNotification message: AbrovaPushMessage) {
        NotificationCenter.default.post(name: .abrovaPushNotificationTapped, object: nil, userInfo: ["message": message])
    }

    func abrovaPush(_ abrovaPush: AbrovaPush, didChangeConnectionState connected: Bool) {
        NotificationCenter.default.post(name: .abrovaPushConnectionChanged, object: nil, userInfo: ["connected": connected])
    }

    func abrovaPush(_ abrovaPush: AbrovaPush, didChangeAppState state: AppState) {}
    func abrovaPush(_ abrovaPush: AbrovaPush, didFailWithError error: Error) {}
    func abrovaPush(_ abrovaPush: AbrovaPush, didFailWithDetailedError error: AbrovaPushError) {}
}

// MARK: - UNUserNotificationCenterDelegate
extension AppDelegate: UNUserNotificationCenterDelegate {

    // Hand taps to the SDK: it reads APNs and Abrova connection payloads, reports the open
    // (or the action click) and calls abrovaPush(_:didTapNotification:) on the delegate.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        _ = AbrovaPush.shared.handleNotificationResponse(
            userInfo: response.notification.request.content.userInfo,
            actionIdentifier: response.actionIdentifier
        )
        completionHandler()
    }

    // Foreground APNs notification: let the SDK confirm the delivery, then show it.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        AbrovaPush.shared.handleRemoteNotification(userInfo: notification.request.content.userInfo)
        completionHandler([.banner, .sound, .badge])
    }
}
