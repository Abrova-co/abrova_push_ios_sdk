import Foundation
import UserNotifications
#if canImport(Intents)
import Intents
#endif

/// Chat-style notifications: the sender's photo and name on the notification, and the messages of one conversation
/// grouped together.
///
/// A message is shown this way when its data has a `conversationId`. Every other message is left as it is. Keys
/// (the same on every Abrova Push SDK):
/// - `conversationId` (required): groups the conversation's notifications.
/// - `senderName`: who wrote it (else the title).
/// - `senderId`: tells two senders with the same name apart.
/// - `senderAvatarUrl`: an https image for the sender's photo.
/// - `conversationTitle`: the group's name (shown for groups).
/// - `conversationIsGroup`: `true` for a group.
///
/// Grouping works everywhere. The photo needs iOS 15+, and the app must have the **Communication Notifications**
/// capability and `INSendMessageIntent` in `NSUserActivityTypes` of its Info.plist; without them the notification is
/// shown as before, grouped.
public enum AbrovaPushConversation {

    /// The conversation a notification belongs to (nil = not a chat message).
    public struct Info: Equatable {
        public let id: String
        public let senderName: String
        public let senderId: String?
        public let senderAvatarUrl: URL?
        public let title: String?
        public let isGroup: Bool
    }

    /// Reads the conversation keys from a notification's userInfo (APNs puts message data at the top level).
    public static func info(from userInfo: [AnyHashable: Any], fallbackSender: String) -> Info? {
        func text(_ key: String) -> String? {
            guard let value = userInfo[key] else { return nil }
            let s = (value as? String) ?? "\(value)"
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard let id = text("conversationId") else { return nil }
        let avatar = text("senderAvatarUrl").flatMap(URL.init(string:)).flatMap { url -> URL? in
            let scheme = url.scheme?.lowercased()
            return scheme == "https" || scheme == "http" ? url : nil
        }
        let groupValue = userInfo["conversationIsGroup"]
        let isGroup = (groupValue as? Bool) ?? ((groupValue as? String)?.lowercased() == "true")
        return Info(
            id: String(id.prefix(200)),
            senderName: text("senderName") ?? (fallbackSender.isEmpty ? "?" : fallbackSender),
            senderId: text("senderId"),
            senderAvatarUrl: avatar,
            title: text("conversationTitle"),
            isGroup: isGroup
        )
    }

    /// The notification as a conversation notification, or `content` unchanged when it isn't a chat message.
    /// Calls `completion` once, within about 5 seconds (the sender's photo is downloaded first).
    public static func content(
        for content: UNNotificationContent,
        completion: @escaping (UNNotificationContent) -> Void
    ) {
        guard let info = info(from: content.userInfo, fallbackSender: content.title),
              let mutable = content.mutableCopy() as? UNMutableNotificationContent else {
            completion(content)
            return
        }
        mutable.threadIdentifier = info.id

        guard let avatarUrl = info.senderAvatarUrl else {
            completion(communication(mutable, info: info, image: nil))
            return
        }
        var request = URLRequest(url: avatarUrl)
        request.timeoutInterval = 5
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            completion(communication(mutable, info: info, image: ok ? data : nil))
        }.resume()
    }

    /// Adds the sender (INSendMessageIntent) on iOS 15+; anything that fails leaves the grouped content.
    private static func communication(_ content: UNMutableNotificationContent, info: Info, image: Data?) -> UNNotificationContent {
        #if canImport(Intents) && !os(macOS)
        if #available(iOS 15.0, *) {
            let handle = INPersonHandle(value: info.senderId ?? info.senderName, type: .unknown)
            let sender = INPerson(
                personHandle: handle,
                nameComponents: nil,
                displayName: info.senderName,
                image: image.map { INImage(imageData: $0) },
                contactIdentifier: nil,
                customIdentifier: info.senderId
            )
            let groupName = info.isGroup ? info.title.map { INSpeakableString(spokenPhrase: $0) } : nil
            // A group shows as one when it has more than one recipient: the reader and the sender.
            let me = INPerson(
                personHandle: INPersonHandle(value: "abrova_me", type: .unknown),
                nameComponents: nil, displayName: nil, image: nil, contactIdentifier: nil, customIdentifier: nil, isMe: true
            )
            let intent = INSendMessageIntent(
                recipients: info.isGroup ? [me, sender] : nil,
                outgoingMessageType: .outgoingMessageText,
                content: content.body,
                speakableGroupName: groupName,
                conversationIdentifier: info.id,
                serviceName: nil,
                sender: sender,
                attachments: nil
            )
            if info.isGroup, let image = image {
                intent.setImage(INImage(imageData: image), forParameterNamed: \.speakableGroupName)
            }
            let interaction = INInteraction(intent: intent, response: nil)
            interaction.direction = .incoming
            interaction.donate(completion: nil)
            if let updated = try? content.updating(from: intent) {
                return updated
            }
        }
        #endif
        return content
    }
}
