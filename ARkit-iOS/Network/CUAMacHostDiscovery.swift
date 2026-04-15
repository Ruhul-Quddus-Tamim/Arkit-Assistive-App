import Foundation
import Darwin
import Network

/// Finds a machine on the same Wi‑Fi subnet that accepts TCP on the CUA WebSocket port.
/// Does **not** require any Mac eye-tracking app — only something listening on that port (your CUA server).
final class CUAMacHostDiscovery {
    private var cancelled = false
    private let workQueue = DispatchQueue(label: "com.arkit.cua.discovery", qos: .userInitiated, attributes: .concurrent)
    private var timeoutWorkItem: DispatchWorkItem?

    /// - Parameters:
    ///   - port: Same as `CUAAgentClient` WebSocket port (default 8765).
    ///   - overallTimeout: Give up after this many seconds even if the scan is not done.
    ///   - completion: First host that accepts TCP on `port`, or `nil`.
    func discoverHost(port: UInt16 = 8765, probeTimeout: TimeInterval = 0.2, overallTimeout: TimeInterval = 25, completion: @escaping (String?) -> Void) {
        cancelled = false

        guard let myIP = Self.deviceWiFiIPv4() else {
            Logger.info("CUAMacHostDiscovery: no Wi‑Fi IPv4 on this iPhone")
            DispatchQueue.main.async { completion(nil) }
            return
        }

        let parts = myIP.split(separator: ".").compactMap { Int(String($0)) }
        guard parts.count == 4 else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        let prefix = "\(parts[0]).\(parts[1]).\(parts[2])."
        let candidates = (1 ... 254).map { "\(prefix)\($0)" }.filter { $0 != myIP }

        let overall = DispatchWorkItem { [weak self] in
            self?.cancelled = true
        }
        timeoutWorkItem = overall
        workQueue.asyncAfter(deadline: .now() + overallTimeout, execute: overall)

        workQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let foundLock = NSLock()
            var foundIP: String?

            let group = DispatchGroup()
            let pool = DispatchSemaphore(value: 48)

            for ip in candidates {
                if self.cancelled { break }
                foundLock.lock()
                let done = foundIP != nil
                foundLock.unlock()
                if done { break }

                group.enter()
                pool.wait()
                self.workQueue.async {
                    if self.cancelled {
                        pool.signal()
                        group.leave()
                        return
                    }
                    self.tcpAcceptsConnection(host: ip, port: port, timeout: probeTimeout) { ok in
                        if ok {
                            foundLock.lock()
                            if foundIP == nil {
                                foundIP = ip
                                Logger.info("CUAMacHostDiscovery: host \(ip):\(port) reachable")
                            }
                            foundLock.unlock()
                        }
                        pool.signal()
                        group.leave()
                    }
                }
            }

            group.notify(queue: .main) { [weak self] in
                self?.timeoutWorkItem?.cancel()
                self?.timeoutWorkItem = nil
                completion(foundIP)
            }
        }
    }

    func cancel() {
        cancelled = true
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
    }

    /// Primary Wi‑Fi IPv4 (typically `en0`), not cellular.
    private static func deviceWiFiIPv4() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let addr = ptr {
            let interface = addr.pointee
            guard interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) else {
                ptr = interface.ifa_next
                continue
            }
            let name = String(cString: interface.ifa_name)
            guard name == "en0" else {
                ptr = interface.ifa_next
                continue
            }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let saLen = socklen_t(interface.ifa_addr.pointee.sa_len)
            let err = getnameinfo(interface.ifa_addr, saLen, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            if err == 0 {
                let s = String(cString: host)
                if s != "127.0.0.1", !s.hasPrefix("169.254.") {
                    return s
                }
            }
            ptr = interface.ifa_next
        }
        return nil
    }

    private func tcpAcceptsConnection(host: String, port: UInt16, timeout: TimeInterval, completion: @escaping (Bool) -> Void) {
        if cancelled {
            completion(false)
            return
        }

        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!)
        let connection = NWConnection(to: endpoint, using: .tcp)

        var finished = false
        let finishLock = NSLock()
        func finish(_ ok: Bool) {
            finishLock.lock()
            defer { finishLock.unlock() }
            guard !finished else { return }
            finished = true
            connection.cancel()
            completion(ok)
        }

        var timeoutTask: DispatchWorkItem?
        let timeoutWork = DispatchWorkItem {
            finish(false)
        }
        timeoutTask = timeoutWork

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                timeoutTask?.cancel()
                finish(true)
            case .failed, .cancelled:
                timeoutTask?.cancel()
                finish(false)
            default:
                break
            }
        }

        connection.start(queue: workQueue)
        workQueue.asyncAfter(deadline: .now() + timeout, execute: timeoutWork)
    }
}
