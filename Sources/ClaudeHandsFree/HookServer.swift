import Foundation
import Network

final class HookServer {
    static let shared = HookServer()

    private var listener: NWListener?
    private let port: UInt16 = 27182

    func start() {
        do {
            let params = NWParameters.tcp
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)

            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            listener?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("[HandsFree] Hook server listening on port \(self.port)")
                case .failed(let error):
                    print("[HandsFree] Hook server failed: \(error)")
                default:
                    break
                }
            }

            listener?.start(queue: .global(qos: .userInitiated))
        } catch {
            print("[HandsFree] Failed to start hook server: \(error)")
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        accumulate(connection: connection, buffer: Data())
    }

    private func accumulate(connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] data, _, isComplete, error in
            guard let self = self else {
                connection.cancel()
                return
            }

            var buf = buffer
            if let data = data {
                buf.append(data)
            }

            // Check if we have a complete HTTP request (headers + body based on Content-Length)
            if let raw = String(data: buf, encoding: .utf8), self.isRequestComplete(raw) {
                self.processHTTP(raw: raw, connection: connection)
            } else if isComplete || error != nil {
                // Connection closed — try to process what we have
                if let raw = String(data: buf, encoding: .utf8) {
                    self.processHTTP(raw: raw, connection: connection)
                } else {
                    connection.cancel()
                }
            } else {
                // Keep reading
                self.accumulate(connection: connection, buffer: buf)
            }
        }
    }

    private func isRequestComplete(_ raw: String) -> Bool {
        // Find header/body separator
        guard let separatorRange = raw.range(of: "\r\n\r\n") else {
            // Also try \n\n
            guard let altRange = raw.range(of: "\n\n") else { return false }
            // We found headers, assume body follows
            let body = String(raw[altRange.upperBound...])
            return !body.isEmpty || raw.lowercased().contains("content-length: 0")
        }

        let headers = String(raw[..<separatorRange.lowerBound]).lowercased()
        let body = String(raw[separatorRange.upperBound...])

        // Extract Content-Length
        if let clRange = headers.range(of: "content-length: ") {
            let afterCL = headers[clRange.upperBound...]
            let lengthStr = afterCL.prefix(while: { $0.isNumber })
            if let expectedLength = Int(lengthStr) {
                return body.utf8.count >= expectedLength
            }
        }

        // No Content-Length — if we have body data, consider it complete
        return !body.isEmpty
    }

    private func processHTTP(raw: String, connection: NWConnection) {
        var body = raw

        // Extract request path
        let isNotification = raw.contains("/hook/notification")

        // Extract body after HTTP headers
        if raw.hasPrefix("POST") || raw.hasPrefix("GET") || raw.hasPrefix("PUT") {
            if let range = raw.range(of: "\r\n\r\n") {
                body = String(raw[range.upperBound...])
            } else if let range = raw.range(of: "\n\n") {
                body = String(raw[range.upperBound...])
            }
        }

        // Trim any trailing whitespace/newlines
        body = body.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !body.isEmpty,
              let jsonData = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let message = json["message"] as? String else {
            sendResponse(connection: connection, status: 400, body: "Invalid JSON or missing 'message'")
            return
        }

        DispatchQueue.main.async {
            if isNotification {
                AppState.shared.handleNotificationMessage(message)
            } else {
                AppState.shared.handleHookMessage(message)
            }
        }

        sendResponse(connection: connection, status: 200, body: "OK")
    }

    private func sendResponse(connection: NWConnection, status: Int, body: String) {
        let statusText = status == 200 ? "OK" : "Bad Request"
        let bodyBytes = body.utf8.count

        let response = "HTTP/1.1 \(status) \(statusText)\r\nContent-Type: text/plain\r\nContent-Length: \(bodyBytes)\r\nConnection: close\r\n\r\n\(body)"

        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
