import Foundation
import Combine

// MARK: - Claude Event Models

struct ClaudeEvent: Codable, Identifiable {
    let id: String
    let type: String
    let timestamp: Date?
    let payload: EventPayload

    struct EventPayload: Codable {
        let command: String?
        let summary: String?
        let riskLevel: String?
        let description: String?
        let requiresApproval: Bool?
    }
}

struct ApprovalResponse: Codable {
    let eventId: String
    let approved: Bool
    let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case approved
        case timestamp
    }
}

// MARK: - WebSocket Bridge

@MainActor
final class WebSocketBridge: ObservableObject {
    @Published private(set) var isConnected: Bool = false
    @Published private(set) var lastError: String?
    @Published var currentEvent: ClaudeEvent?

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var host: String
    private var port: Int
    private var reconnectAttempts: Int = 0
    private let maxReconnectAttempts: Int = 5
    private var isIntentionalDisconnect: Bool = false

    init(host: String = "localhost", port: Int = 8080) {
        self.host = host
        self.port = port
    }

    func connect() {
        guard webSocketTask == nil else { return }

        isIntentionalDisconnect = false
        let urlString = "ws://\(host):\(port)/relay"
        guard let url = URL(string: urlString) else {
            lastError = "Invalid WebSocket URL"
            return
        }

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        urlSession = URLSession(configuration: configuration)

        webSocketTask = urlSession?.webSocketTask(with: url)
        webSocketTask?.resume()
        isConnected = true
        reconnectAttempts = 0
        lastError = nil

        receiveMessage()
    }

    func disconnect() {
        isIntentionalDisconnect = true
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession = nil
        isConnected = false
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor in
                guard let self = self else { return }

                switch result {
                case .success(let message):
                    self.handleMessage(message)
                    self.receiveMessage()

                case .failure(let error):
                    self.lastError = error.localizedDescription
                    self.isConnected = false
                    self.attemptReconnect()
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            decodeAndProcess(text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                decodeAndProcess(text)
            }
        @unknown default:
            lastError = "Unknown message type received"
        }
    }

    private func decodeAndProcess(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let event = try decoder.decode(ClaudeEvent.self, from: data)
            currentEvent = event
        } catch {
            lastError = "Failed to decode event: \(error.localizedDescription)"
        }
    }

    func sendApproval(eventId: String, approved: Bool) {
        let response = ApprovalResponse(
            eventId: eventId,
            approved: approved,
            timestamp: Date()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(response),
              let jsonString = String(data: data, encoding: .utf8) else {
            lastError = "Failed to encode approval response"
            return
        }

        let message = URLSessionWebSocketTask.Message.string(jsonString)
        webSocketTask?.send(message) { [weak self] error in
            Task { @MainActor in
                if let error = error {
                    self?.lastError = "Failed to send approval: \(error.localizedDescription)"
                }
            }
        }
    }

    private func attemptReconnect() {
        guard !isIntentionalDisconnect,
              reconnectAttempts < maxReconnectAttempts else {
            if reconnectAttempts >= maxReconnectAttempts {
                lastError = "Max reconnection attempts reached"
            }
            return
        }

        reconnectAttempts += 1
        let delay = Double(reconnectAttempts) * 2.0

        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            connect()
        }
    }

    func updateConnection(host: String, port: Int) {
        self.host = host
        self.port = port
        if isConnected {
            disconnect()
            connect()
        }
    }
}
