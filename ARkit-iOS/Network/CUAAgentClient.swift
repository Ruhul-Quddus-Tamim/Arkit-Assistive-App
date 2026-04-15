import Foundation

/// Delegate for CUA Agent WebSocket client
protocol CUAAgentClientDelegate: AnyObject {
    func cuaAgentClientDidConnect(_ client: CUAAgentClient)
    func cuaAgentClientDidDisconnect(_ client: CUAAgentClient)
    func cuaAgentClient(_ client: CUAAgentClient, didReceiveMessage type: String, message: String)
    func cuaAgentClient(_ client: CUAAgentClient, didEncounterError error: Error)
}

/// WebSocket client for sending commands to the Computer Use Agent on Mac
class CUAAgentClient {
    weak var delegate: CUAAgentClientDelegate?

    private var webSocketTask: URLSessionWebSocketTask?
    private var currentMacIP: String = "192.168.0.178"
    private var currentPort: Int = 8765

    private static let macIPKey = "CUAAgentClient.macIP"
    private static let portKey = "CUAAgentClient.port"
    private static let defaultMacIP = "192.168.0.178"
    private static let defaultPort = 8765

    var isConnected: Bool {
        webSocketTask != nil
    }

    var lastMacIP: String {
        get { UserDefaults.standard.string(forKey: Self.macIPKey) ?? Self.defaultMacIP }
        set { UserDefaults.standard.set(newValue, forKey: Self.macIPKey) }
    }

    var lastPort: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: Self.portKey)
            return stored > 0 ? stored : Self.defaultPort
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.portKey) }
    }

    init() {
        currentMacIP = lastMacIP
        currentPort = lastPort
    }

    /// Connect to the CUA agent server on Mac
    func connect(macIP: String? = nil, port: Int? = nil) {
        let ip = macIP ?? lastMacIP
        let portValue = port ?? lastPort
        currentMacIP = ip
        currentPort = portValue
        lastMacIP = ip
        lastPort = portValue

        let urlString = "ws://\(ip):\(portValue)/ws"
        guard let url = URL(string: urlString) else {
            let error = NSError(domain: "CUAAgentClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.cuaAgentClient(self!, didEncounterError: error)
            }
            return
        }

        disconnect()

        let request = URLRequest(url: url)
        webSocketTask = URLSession.shared.webSocketTask(with: request)
        webSocketTask?.resume()
        receiveMessage()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.cuaAgentClientDidConnect(self)
        }

        Logger.info("CUAAgentClient: Connecting to \(urlString)")
    }

    /// Reconnect using last saved Mac IP and port
    func reconnect() {
        connect(macIP: lastMacIP, port: lastPort)
    }

    /// Send a command to the CUA agent
    func send(command: String) {
        let payload: [String: String] = ["command": command]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
            Logger.error("CUAAgentClient: Failed to serialize command")
            return
        }
        let message = URLSessionWebSocketTask.Message.data(data)
        webSocketTask?.send(message) { [weak self] error in
            if let error = error, let self = self {
                Logger.error("CUAAgentClient: Send failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.delegate?.cuaAgentClient(self, didEncounterError: error)
                }
            }
        }
    }

    /// Disconnect from the server
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.cuaAgentClientDidDisconnect(self)
        }
        Logger.info("CUAAgentClient: Disconnected")
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let msg):
                switch msg {
                case .data(let data):
                    self.handleJSON(data)
                case .string(let text):
                    if let data = text.data(using: .utf8) {
                        self.handleJSON(data)
                    }
                @unknown default:
                    break
                }
                self.receiveMessage()
            case .failure(let error):
                DispatchQueue.main.async {
                    self.webSocketTask = nil
                    self.delegate?.cuaAgentClientDidDisconnect(self)
                    self.delegate?.cuaAgentClient(self, didEncounterError: error)
                }
                return
            }
        }
    }

    private func handleJSON(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String,
              let message = json["message"] as? String else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.cuaAgentClient(self, didReceiveMessage: type, message: message)
        }
    }
}
