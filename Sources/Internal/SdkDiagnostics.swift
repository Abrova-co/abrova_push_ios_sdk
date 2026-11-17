import Foundation

/// SDK self-reports. The SDK counts
/// its own errors by the public `AbrovaPushErrorCode` number every Abrova Push
/// SDK shares, and sends the counts with its next ordinary API request in one
/// header:
///
///     X-Abrova-SDK-Report: 1000=3 1400=1
///
/// Next to it, a breakdown of the same counts by why they happened:
///
///     X-Abrova-SDK-Report-Reasons: 1000:timeout.8883.wifi=3 1400:http503=1
///
/// `<code>:<reason>[.<port>][.<net>]=<count>`. The reason is one word from a
/// fixed list (`SdkErrorReason`), the port is the broker port of a connection
/// error, the net the network type. Never a message, stack trace, key, host,
/// user or device detail. Both are cleared only after the server answered 2xx,
/// so nothing is lost while offline and nothing is counted twice. Switched off
/// with `AbrovaPushConfig.sendDiagnostics = false`: nothing is counted, kept or
/// sent. (Crashes are not counted on iOS: an SDK cannot safely install signal
/// handlers next to the app's own crash reporter.)
internal final class SdkDiagnostics {
    static let shared = SdkDiagnostics(defaults: .standard)

    static let header = "X-Abrova-SDK-Report"
    static let reasonsHeader = "X-Abrova-SDK-Report-Reasons"
    /// Most codes per report and highest count per code (the server accepts no more).
    static let maxCodes = 16
    static let maxCount = 9999
    /// Most reason entries kept and sent, and the longest reasons header.
    static let maxReasons = 16
    static let maxReasonsHeaderLength = 400

    /// What one request carries; acknowledged as a whole after a 2xx answer.
    struct Report: Equatable {
        var counts: [Int: Int] = [:]
        var reasons: [String: Int] = [:]
        var isEmpty: Bool { counts.isEmpty && reasons.isEmpty }
    }

    private static let key = "ir.abrova.push.diagnostics"
    private static let reasonsKey = "ir.abrova.push.diagnostics.reasons"
    /// The server's grammar for one entry key (without `=<count>`).
    private static let entryPattern = try! NSRegularExpression(
        pattern: "^\\d{4}:[a-z][a-z0-9_]{0,19}(?:\\.\\d{1,5})?(?:\\.(?:wifi|cellular|ethernet|vpn|none|other))?$"
    )
    private let defaults: UserDefaults
    private let lock = NSLock()
    private var enabled = true

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// From `AbrovaPush.initialize`; false also forgets what was kept.
    func setEnabled(_ on: Bool) {
        lock.lock(); defer { lock.unlock() }
        enabled = on
        if !on {
            defaults.removeObject(forKey: Self.key)
            defaults.removeObject(forKey: Self.reasonsKey)
        }
    }

    func count(_ code: AbrovaPushErrorCode) { count(code.rawValue) }

    /// Adds one. A 17th distinct code is dropped.
    func count(_ code: Int) {
        record(code, reason: nil, port: nil, net: nil)
    }

    /// Counts `code` and, with it, why: the reason word classified from
    /// `error`, the broker `port` (connection errors only) and the network type.
    func count(_ code: AbrovaPushErrorCode, error: Error?, port: Int? = nil, net: String? = nil) {
        record(code.rawValue, reason: SdkErrorReason.classify(error), port: port, net: net)
    }

    /// Counts `code`; with a `reason` also its breakdown entry. An entry is
    /// kept only for a code that is kept, and a 17th distinct entry is dropped
    /// (its code is still counted).
    func record(_ code: Int, reason: String?, port: Int?, net: String?) {
        lock.lock(); defer { lock.unlock() }
        guard enabled else { return }
        var counts = stored()
        let key = String(code)
        if counts[key] == nil && counts.count >= Self.maxCodes { return }
        counts[key] = min(Self.maxCount, (counts[key] ?? 0) + 1)
        defaults.set(counts, forKey: Self.key)

        guard let reason = reason, let entry = Self.entry(code: code, reason: reason, port: port, net: net) else { return }
        var reasons = storedReasons()
        if reasons[entry] == nil && reasons.count >= Self.maxReasons { return }
        reasons[entry] = min(Self.maxCount, (reasons[entry] ?? 0) + 1)
        defaults.set(reasons, forKey: Self.reasonsKey)
    }

    /// `<code>:<reason>[.<port>][.<net>]`, or nil when it would not match the server's grammar.
    static func entry(code: Int, reason: String, port: Int?, net: String?) -> String? {
        var entry = "\(code):\(reason)"
        if let port = port, (1...65535).contains(port) { entry += ".\(port)" }
        if let net = net, SdkErrorReason.netWords.contains(net) { entry += ".\(net)" }
        let range = NSRange(entry.startIndex..., in: entry)
        return entryPattern.firstMatch(in: entry, range: range) != nil ? entry : nil
    }

    /// What would be sent now: code → count.
    func pending() -> [Int: Int] {
        lock.lock(); defer { lock.unlock() }
        guard enabled else { return [:] }
        var out: [Int: Int] = [:]
        for (k, v) in stored() { if let code = Int(k), v > 0 { out[code] = v } }
        return out
    }

    /// Reason entries that would be sent now: entry → count.
    func pendingReasons() -> [String: Int] {
        lock.lock(); defer { lock.unlock() }
        guard enabled else { return [:] }
        return storedReasons().filter { $0.value > 0 }
    }

    /// `1000=3 1400=1`, or nil when there is nothing to send. Codes in ascending order.
    static func headerValue(_ snapshot: [Int: Int]) -> String? {
        guard !snapshot.isEmpty else { return nil }
        return snapshot.keys.sorted().prefix(maxCodes)
            .map { "\($0)=\(min(maxCount, max(1, snapshot[$0] ?? 1)))" }
            .joined(separator: " ")
    }

    /// `1000:timeout.8883.wifi=3 1400:http503=1` and the entries it holds, or
    /// nil when there is nothing to send. Entries in ascending order; at most
    /// 16, and no more than fit in 400 characters.
    static func reasonsHeaderValue(_ snapshot: [String: Int]) -> (value: String, sent: [String: Int])? {
        var parts: [String] = []
        var sent: [String: Int] = [:]
        var length = 0
        for entry in snapshot.keys.sorted() {
            guard parts.count < maxReasons else { break }
            let count = min(maxCount, max(1, snapshot[entry] ?? 1))
            let part = "\(entry)=\(count)"
            let added = (parts.isEmpty ? 0 : 1) + part.count
            if length + added > maxReasonsHeaderLength { continue }
            parts.append(part)
            sent[entry] = snapshot[entry] ?? count
            length += added
        }
        return parts.isEmpty ? nil : (parts.joined(separator: " "), sent)
    }

    /// The server took `report`: subtract it (counts added meanwhile stay for the next request).
    func acknowledge(_ report: Report) {
        lock.lock(); defer { lock.unlock() }
        var counts = stored()
        for (code, sent) in report.counts {
            let key = String(code)
            let left = (counts[key] ?? 0) - sent
            counts[key] = left > 0 ? left : nil
        }
        defaults.set(counts, forKey: Self.key)

        var reasons = storedReasons()
        for (entry, sent) in report.reasons {
            let left = (reasons[entry] ?? 0) - sent
            reasons[entry] = left > 0 ? left : nil
        }
        defaults.set(reasons, forKey: Self.reasonsKey)
    }

    /// Adds the report headers to `request`; returns what they carry (empty = nothing added).
    func attach(to request: inout URLRequest) -> Report {
        var report = Report()
        let counts = pending()
        guard let value = Self.headerValue(counts) else { return report }
        request.setValue(value, forHTTPHeaderField: Self.header)
        report.counts = counts
        if let reasons = Self.reasonsHeaderValue(pendingReasons()) {
            request.setValue(reasons.value, forHTTPHeaderField: Self.reasonsHeader)
            report.reasons = reasons.sent
        }
        return report
    }

    private func stored() -> [String: Int] {
        return defaults.dictionary(forKey: Self.key) as? [String: Int] ?? [:]
    }

    private func storedReasons() -> [String: Int] {
        return defaults.dictionary(forKey: Self.reasonsKey) as? [String: Int] ?? [:]
    }
}
