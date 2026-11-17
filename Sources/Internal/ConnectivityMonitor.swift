import Foundation
import Network

/// Watches the network path and reports when a connection is worth retrying
/// right away: the network came back, or it moved to another interface
/// (Wi-Fi <-> cellular), which usually kills the old socket.
internal final class ConnectivityMonitor {
    /// Called on the main queue. `interfaceChanged` is true when the path moved
    /// to a different interface while it stayed usable.
    var onChange: ((_ kind: NetworkKind, _ interfaceChanged: Bool) -> Void)?

    /// Current network type (main queue).
    private(set) var currentKind: NetworkKind = .other

    /// Network type word for the SDK self-report (`wifi`, `cellular`,
    /// `ethernet`, `vpn`, `none`, `other`); nil until the first path report (main queue).
    private(set) var currentNet: String?

    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "ir.abrova.push.connectivity")
    private var lastSatisfied: Bool?
    private var lastInterfaces: [String] = []

    var isRunning: Bool { monitor != nil }

    func start() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            let kind = ConnectivityMonitor.kind(of: path)
            let interfaces = path.availableInterfaces.map { $0.name }
            let net = ConnectivityMonitor.reportNet(of: path)
            DispatchQueue.main.async {
                self?.currentNet = net
                self?.handle(satisfied: satisfied, kind: kind, interfaces: interfaces)
            }
        }
        self.monitor = monitor
        monitor.start(queue: queue)
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
        lastSatisfied = nil
        lastInterfaces = []
        currentNet = nil
    }

    private func handle(satisfied: Bool, kind: NetworkKind, interfaces: [String]) {
        guard monitor != nil else { return }
        let previousSatisfied = lastSatisfied
        let previousInterfaces = lastInterfaces
        lastSatisfied = satisfied
        lastInterfaces = interfaces
        currentKind = kind

        // First report is the baseline, not a change.
        guard let wasSatisfied = previousSatisfied, satisfied else { return }

        if !wasSatisfied {
            onChange?(kind, false)
        } else if interfaces.first != previousInterfaces.first {
            onChange?(kind, true)
        }
    }

    static func kind(of path: NWPath) -> NetworkKind {
        if path.usesInterfaceType(.wifi) { return .wifi }
        if path.usesInterfaceType(.cellular) { return .cellular }
        return .other
    }

    static func reportNet(of path: NWPath) -> String {
        guard path.status == .satisfied else { return "none" }
        return reportNet(interfaceNames: path.availableInterfaces.map { $0.name },
                         wifi: path.usesInterfaceType(.wifi),
                         cellular: path.usesInterfaceType(.cellular),
                         ethernet: path.usesInterfaceType(.wiredEthernet))
    }

    /// The first (preferred) interface decides VPN: a tunnel (`utun`, `ipsec`,
    /// `ppp`) carries the traffic even while Wi-Fi or cellular sits under it.
    /// The name is only looked at here, never sent.
    static func reportNet(interfaceNames: [String], wifi: Bool, cellular: Bool, ethernet: Bool) -> String {
        if let first = interfaceNames.first,
           ["utun", "ipsec", "ppp"].contains(where: { first.hasPrefix($0) }) {
            return "vpn"
        }
        if wifi { return "wifi" }
        if cellular { return "cellular" }
        if ethernet { return "ethernet" }
        return "other"
    }
}
