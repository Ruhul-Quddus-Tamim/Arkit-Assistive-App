import Foundation
import Network

/// Protocol for receiving gaze tracking data
protocol TrackingDataServerDelegate: AnyObject {
    func server(_ server: TrackingDataServer, didReceiveGazeData data: GazeTrackingData)
    func server(_ server: TrackingDataServer, didConnect client: String)
    func server(_ server: TrackingDataServer, didDisconnect client: String)
    func server(_ server: TrackingDataServer, didEncounterError error: Error)
}

/// Network server that receives gaze tracking data from iPhone
class TrackingDataServer {
    weak var delegate: TrackingDataServerDelegate?
    
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let port: UInt16 = 8080
    private let serviceType = "_eyetracking._tcp"
    private var isRunning = false
    
    /// Start the server and begin listening for connections
    func start() {
        guard !isRunning else {
            print("Mac: Server already running")
            return
        }
        
        // Use pre-configured TCP parameters (simpler than init(tls:tcp:))
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        
        do {
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            print("Mac: Failed to create listener: \(error)")
            delegate?.server(self, didEncounterError: error)
            return
        }
        
        // Set up Bonjour service
        listener?.service = NWListener.Service(
            name: "EyeTrackingServer",
            type: serviceType,
            domain: "local",
            txtRecord: nil
        )
        
        // Handle new connections
        listener?.newConnectionHandler = { [weak self] connection in
            guard let self = self else { return }
            let clientID = UUID().uuidString
            print("Mac: New iPhone connected: \(clientID)")
            self.delegate?.server(self, didConnect: clientID)
            self.handleConnection(connection, clientID: clientID)
        }
        
        // Start listening
        listener?.start(queue: .main)
        isRunning = true
        print("Mac: Server started on port \(port). Waiting for iPhone...")
    }
    
    private func handleConnection(_ connection: NWConnection, clientID: String) {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            
            switch state {
            case .ready:
                print("Mac: Connection ready from \(clientID)")
                self.receiveData(from: connection, clientID: clientID)
                
            case .failed(let error):
                print("Mac: Connection failed: \(error)")
                self.delegate?.server(self, didEncounterError: error)
                self.removeConnection(connection, clientID: clientID)
                
            case .cancelled:
                print("Mac: Connection cancelled: \(clientID)")
                self.delegate?.server(self, didDisconnect: clientID)
                self.removeConnection(connection, clientID: clientID)
                
            default:
                break
            }
        }
        
        connection.start(queue: .main)
        connections.append(connection)
    }
    
    private func receiveData(from connection: NWConnection, clientID: String) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Mac: Receive error: \(error)")
                self.delegate?.server(self, didEncounterError: error)
                self.removeConnection(connection, clientID: clientID)
                return
            }
            
            if let data = data, !data.isEmpty {
                // Process received data
                self.processReceivedData(data)
                
                // Continue receiving
                if !isComplete {
                    self.receiveData(from: connection, clientID: clientID)
                }
            }
        }
    }
    
    private func processReceivedData(_ data: Data) {
        // Split by newline (each JSON object is on a separate line)
        let dataString = String(data: data, encoding: .utf8) ?? ""
        let lines = dataString.components(separatedBy: "\n").filter { !$0.isEmpty }
        
        for line in lines {
            guard let lineData = line.data(using: .utf8) else {
                print("Mac: Failed to convert line to data")
                continue
            }
            
            guard let gazeData = DataSerializer.deserialize(lineData) else {
                print("Mac: Failed to deserialize gaze data. Raw JSON: \(line.prefix(200))")
                continue
            }
            
            // Notify delegate
            delegate?.server(self, didReceiveGazeData: gazeData)
        }
    }
    
    private func removeConnection(_ connection: NWConnection, clientID: String) {
        if let index = connections.firstIndex(where: { $0 === connection }) {
            connections.remove(at: index)
        }
        connection.cancel()
    }
    
    /// Stop the server
    func stop() {
        listener?.cancel()
        listener = nil
        
        for connection in connections {
            connection.cancel()
        }
        connections.removeAll()
        
        isRunning = false
        print("Mac: Server stopped")
    }
    
    deinit {
        stop()
    }
}
