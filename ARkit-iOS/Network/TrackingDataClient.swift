import Foundation
import Network

/// Protocol for tracking connection status
protocol TrackingDataClientDelegate: AnyObject {
    func clientDidConnect(_ client: TrackingDataClient)
    func clientDidDisconnect(_ client: TrackingDataClient)
    func client(_ client: TrackingDataClient, didEncounterError error: Error)
}

/// Network client that sends gaze tracking data from iPhone to Mac
class TrackingDataClient {
    weak var delegate: TrackingDataClientDelegate?
    
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var isConnected = false
    private let serviceType = "_eyetracking._tcp"
    private let serviceDomain = "local"
    
    /// Start discovering Mac server via Bonjour
    func startDiscovery() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = false
        
        browser = NWBrowser(for: .bonjour(type: serviceType, domain: serviceDomain), using: parameters)
        
        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            for result in results {
                switch result.endpoint {
                case .service(let name, _, _, _):
                    print("Found Mac server: \(name)")
                    // Connect to the first server found
                    self?.connect(to: result.endpoint)
                    return
                default:
                    break
                }
            }
        }
        
        browser?.start(queue: .main)
        print("iPhone: Searching for Mac server...")
    }
    
    /// Connect to Mac using manual IP address
    /// - Parameters:
    ///   - ipAddress: Mac's IP address (e.g., "192.168.1.100")
    ///   - port: Port number (default: 8080)
    func connectToMac(ipAddress: String, port: UInt16 = 8080) {
        let host = NWEndpoint.Host(ipAddress)
        let port = NWEndpoint.Port(rawValue: port)!
        let endpoint = NWEndpoint.hostPort(host: host, port: port)
        connect(to: endpoint)
    }
    
    private func connect(to endpoint: NWEndpoint) {
        // Close existing connection if any
        disconnect()
        
        let connection = NWConnection(to: endpoint, using: .tcp)
        
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            
            switch state {
            case .ready:
                print("iPhone: Connected to Mac!")
                self.isConnected = true
                self.connection = connection
                self.delegate?.clientDidConnect(self)
                
            case .failed(let error):
                print("iPhone: Connection failed: \(error)")
                self.isConnected = false
                self.delegate?.client(self, didEncounterError: error)
                
            case .waiting(let error):
                print("iPhone: Connection waiting: \(error)")
                
            case .cancelled:
                print("iPhone: Connection cancelled")
                self.isConnected = false
                self.delegate?.clientDidDisconnect(self)
                
            default:
                break
            }
        }
        
        connection.start(queue: .main)
    }
    
    /// Send gaze tracking data to Mac
    /// - Parameter data: GazeTrackingData to send
    func sendGazeData(_ data: GazeTrackingData) {
        guard isConnected, let connection = connection else {
            return
        }
        
        guard let jsonData = DataSerializer.serialize(data) else {
            print("iPhone: Failed to serialize gaze data")
            return
        }
        
        // Send data with newline delimiter for easier parsing
        var dataToSend = jsonData
        dataToSend.append("\n".data(using: .utf8)!)
        
        connection.send(content: dataToSend, completion: .contentProcessed { [weak self] error in
            if let error = error {
                print("iPhone: Send error: \(error)")
                self?.delegate?.client(self!, didEncounterError: error)
            }
        })
    }
    
    /// Send a command to Mac
    /// - Parameter command: Command string (e.g., "startMacCalibration")
    func sendCommand(_ command: String) {
        guard isConnected, let connection = connection else {
            print("iPhone: Cannot send command - not connected")
            return
        }
        
        let commandDict: [String: String] = ["command": command]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: commandDict),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            print("iPhone: Failed to serialize command")
            return
        }
        
        var dataToSend = jsonString.data(using: .utf8)!
        dataToSend.append("\n".data(using: .utf8)!)
        
        connection.send(content: dataToSend, completion: .contentProcessed { [weak self] error in
            if let error = error {
                print("iPhone: Send command error: \(error)")
                self?.delegate?.client(self!, didEncounterError: error)
            } else {
                print("iPhone: Command sent: \(command)")
            }
        })
    }
    
    /// Disconnect from Mac
    func disconnect() {
        browser?.cancel()
        browser = nil
        
        connection?.cancel()
        connection = nil
        isConnected = false
    }
    
    deinit {
        disconnect()
    }
}
