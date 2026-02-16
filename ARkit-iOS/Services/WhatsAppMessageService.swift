import Foundation

/// WhatsApp Business API token - for production, use a backend proxy
private let whatsAppBearerToken = "YOUR_TOKEN"

private let apiURL = "https://graph.facebook.com/v22.0/991282647400373/messages"

/// Service for sending WhatsApp messages via Facebook Graph API
class WhatsAppMessageService {
    static let shared = WhatsAppMessageService()
    
    private let session = URLSession.shared
    
    private init() {}
    
    /// Send a text message to a phone number
    func sendText(to phoneNumber: String, body: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedBody.isEmpty {
            completion(.failure(WhatsAppError.emptyMessage))
            return
        }
        
        let payload: [String: Any] = [
            "messaging_product": "whatsapp",
            "to": phoneNumber.replacingOccurrences(of: "+", with: ""),
            "type": "text",
            "text": ["body": trimmedBody]
        ]
        
        sendRequest(payload: payload) { result in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// Send hello_world template (fallback when outside 24h window)
    func sendTemplate(to phoneNumber: String, templateName: String = "hello_world", completion: @escaping (Result<Void, Error>) -> Void) {
        let payload: [String: Any] = [
            "messaging_product": "whatsapp",
            "to": phoneNumber.replacingOccurrences(of: "+", with: ""),
            "type": "template",
            "template": [
                "name": templateName,
                "language": ["code": "en_US"]
            ]
        ]
        
        sendRequest(payload: payload) { result in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    private func sendRequest(payload: [String: Any], completion: @escaping (Result<Void, Error>) -> Void) {
        guard let url = URL(string: apiURL) else {
            completion(.failure(WhatsAppError.invalidURL))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(whatsAppBearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            completion(.failure(error))
            return
        }
        
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                DispatchQueue.main.async { completion(.failure(WhatsAppError.invalidResponse)) }
                return
            }
            
            if (200...299).contains(httpResponse.statusCode) {
                DispatchQueue.main.async { completion(.success(())) }
            } else {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown"
                Logger.error("WhatsApp API error: \(httpResponse.statusCode) - \(body)")
                DispatchQueue.main.async {
                    completion(.failure(WhatsAppError.apiError(statusCode: httpResponse.statusCode, body: body)))
                }
            }
        }
        task.resume()
    }
}

enum WhatsAppError: LocalizedError {
    case emptyMessage
    case invalidURL
    case invalidResponse
    case apiError(statusCode: Int, body: String)
    
    var errorDescription: String? {
        switch self {
        case .emptyMessage: return "Message cannot be empty"
        case .invalidURL: return "Invalid API URL"
        case .invalidResponse: return "Invalid response from server"
        case .apiError(let code, let body): return "API error \(code): \(body)"
        }
    }
}
