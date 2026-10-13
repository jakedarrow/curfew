import Foundation
import Network

public final class LocalBridgeServer: @unchecked Sendable {
    public static let shared = LocalBridgeServer()
    
    private var listener: NWListener?
    private let port: UInt16 = 48200
    private let queue = DispatchQueue(label: "com.smartscreen.bridgeserver")
    
    private init() {}
    
    public func start() {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let portObj = NWEndpoint.Port(rawValue: self.port)!
            let l = try NWListener(using: params, on: portObj)
            self.listener = l
            
            l.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            
            l.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("[Curfew] Local bridge listening on http://127.0.0.1:48200")
                case .failed(let error):
                    print("[Curfew] Local bridge failed: \(error)")
                default:
                    break
                }
            }
            
            l.start(queue: queue)
        } catch {
            print("[Curfew] Could not start NWListener on port \(port): \(error)")
        }
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        readRequest(connection: connection)
    }
    
    private func readRequest(connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self = self, let data = content, let reqStr = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            
            self.processHttpRequest(reqStr: reqStr, connection: connection)
        }
    }
    
    private func processHttpRequest(reqStr: String, connection: NWConnection) {
        let lines = reqStr.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else {
            sendResponse(connection: connection, status: 400, body: "Bad Request")
            return
        }
        
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            sendResponse(connection: connection, status: 400, body: "Bad Request")
            return
        }
        
        let method = parts[0].uppercased()
        let path = parts[1]
        
        // CORS preflight
        if method == "OPTIONS" {
            sendCorsOk(connection: connection)
            return
        }
        
        if path.starts(with: "/api/status") {
            let state = StorageManager.shared.state
            DispatchQueue.main.async { [weak self] in
                let activeApp = AppTracker.shared.activeAppName
                let responseObj: [String: Any] = [
                    "focusModeActive": state.focusModeActive,
                    "activeApp": activeApp,
                    "sessionName": state.currentSessionName,
                    "todayMinutes": state.todayMinutesSpent,
                    "dailyLimitMinutes": state.dailyLimitMinutes
                ]
                if let jsonData = try? JSONSerialization.data(withJSONObject: responseObj),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    self?.sendResponse(connection: connection, status: 200, contentType: "application/json", body: jsonString)
                } else {
                    self?.sendResponse(connection: connection, status: 500, body: "{}")
                }
            }
            return
        }
        
        if path.starts(with: "/api/focus") && method == "POST" {
            if let bodyData = extractBody(reqStr: reqStr) {
                if let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                    if let active = json["active"] as? Bool {
                        StorageManager.shared.update { s in
                            s.focusModeActive = active
                            if let name = json["sessionName"] as? String {
                                s.currentSessionName = name
                            }
                        }
                    }
                }
            }
            sendResponse(connection: connection, status: 200, contentType: "application/json", body: "{\"success\":true}")
            return
        }
        
        if path.starts(with: "/api/watch-event") && method == "POST" {
            if let bodyData = extractBody(reqStr: reqStr) {
                if let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                    if let totalMin = json["totalMinutesToday"] as? Int {
                        StorageManager.shared.update { s in
                            s.todayMinutesSpent = totalMin
                        }
                    }
                }
            }
            sendResponse(connection: connection, status: 200, contentType: "application/json", body: "{\"success\":true}")
            return
        }
        
        sendResponse(connection: connection, status: 404, body: "Not Found")
    }
    
    private func extractBody(reqStr: String) -> Data? {
        let parts = reqStr.components(separatedBy: "\r\n\r\n")
        if parts.count > 1 {
            return parts[1].data(using: .utf8)
        }
        return nil
    }
    
    private func sendCorsOk(connection: NWConnection) {
        let resp = "HTTP/1.1 204 No Content\r\n" +
                   "Access-Control-Allow-Origin: *\r\n" +
                   "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n" +
                   "Access-Control-Allow-Headers: Content-Type, Accept\r\n" +
                   "Connection: close\r\n\r\n"
        connection.send(content: resp.data(using: .utf8), completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }
    
    private func sendResponse(connection: NWConnection, status: Int, contentType: String = "text/plain", body: String) {
        let statusText = status == 200 ? "OK" : (status == 404 ? "Not Found" : "Error")
        let bodyData = body.data(using: .utf8) ?? Data()
        let resp = "HTTP/1.1 \(status) \(statusText)\r\n" +
                   "Content-Type: \(contentType)\r\n" +
                   "Content-Length: \(bodyData.count)\r\n" +
                   "Access-Control-Allow-Origin: *\r\n" +
                   "Connection: close\r\n\r\n" + body
        
        connection.send(content: resp.data(using: .utf8), completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }
}
