//
//  ChatWebSocketManager.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation
import Combine

enum WebSocketMessageType: String, Codable {
    case chatMessage = "chat_message"
    case typing = "typing"
    case readReceipt = "read_receipt"
    case messageUpdate = "message_update"
    case messageDelete = "message_delete"
    case userStatus = "user_status"
    case error = "error"
}

struct WebSocketIncomingMessage: Codable {
    let type: WebSocketMessageType
    let message: Message?
    let user: User?
    let isTyping: Bool?
    let userId: String?
    let messageIds: [String]?
    let messageId: String?
    let status: String?
    let errorMessage: String?
    
    enum CodingKeys: String, CodingKey {
        case type
        case message
        case user
        case isTyping = "is_typing"
        case userId = "user_id"
        case messageIds = "message_ids"
        case messageId = "message_id"
        case status
        case errorMessage = "error_message"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        type = try container.decode(WebSocketMessageType.self, forKey: .type)
        
        // message 필드는 Message 객체일 수도 있고, 에러 메시지의 경우 문자열일 수도 있음
        if let messageValue = try? container.decode(Message.self, forKey: .message) {
            message = messageValue
        } else {
            message = nil
        }
        
        user = try? container.decode(User.self, forKey: .user)
        isTyping = try? container.decode(Bool.self, forKey: .isTyping)
        userId = try? container.decode(String.self, forKey: .userId)
        messageIds = try? container.decode([String].self, forKey: .messageIds)
        messageId = try? container.decode(String.self, forKey: .messageId)
        status = try? container.decode(String.self, forKey: .status)
        
        if let errorMsg = try? container.decode(String.self, forKey: .errorMessage) {
            errorMessage = errorMsg
        } else if type == .error, let messageStr = try? container.decode(String.self, forKey: .message) {
            errorMessage = messageStr
        } else {
            errorMessage = nil
        }
    }
}

struct WebSocketOutgoingMessage: Codable {
    let type: String
    let messageType: String?
    let content: String?
    let encryptedContent: String?
    let encryptedSessionKey: String?
    let selfEncryptedSessionKey: String?
    let replyTo: String?
    let assetId: String?
    let isTyping: Bool?
    let messageIds: [String]?
    
    enum CodingKeys: String, CodingKey {
        case type
        case messageType = "message_type"
        case content
        case encryptedContent = "encrypted_content"
        case encryptedSessionKey = "encrypted_session_key"
        case selfEncryptedSessionKey = "self_encrypted_session_key"
        case replyTo = "reply_to"
        case assetId = "asset_id"
        case isTyping = "is_typing"
        case messageIds = "message_ids"
    }
}

// MARK: - Chat WebSocket Manager
@MainActor
class ChatWebSocketManager: ObservableObject {
    static let shared = ChatWebSocketManager()
    
    @Published var isConnected = false
    @Published var connectionError: String?
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var reconnectTimer: Timer?
    private var reconnectAttempts = 0
    private let maxReconnectDelay: TimeInterval = 60.0
    private var isReconnecting = false
    
    // Ping Timer
    private var pingTimer: Timer?
    
    var currentRoomId: String?
    private var currentAccessToken: String?
    
    let receivedMessage = PassthroughSubject<WebSocketIncomingMessage, Never>()
    let typingIndicator = PassthroughSubject<(user: User, isTyping: Bool), Never>()
    let readReceipt = PassthroughSubject<(userId: String, messageIds: [String]), Never>()
    let messageUpdate = PassthroughSubject<Message, Never>()
    let messageDelete = PassthroughSubject<String, Never>()
    let userStatus = PassthroughSubject<(userId: String, status: String), Never>()
    
    private init() {}
    
    func connect(roomId: String, accessToken: String, isReconnect: Bool = false) {
        guard let url = buildWebSocketURL(roomId: roomId, token: accessToken) else {
            connectionError = "Invalid WebSocket URL"
            return
        }
        
        currentRoomId = roomId
        currentAccessToken = accessToken
        
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        urlSession = session
        
        webSocketTask?.resume()
        isConnected = true
        connectionError = nil
        
        if !isReconnect {
            reconnectAttempts = 0
        }
        
        startPingTimer()
        receiveMessage()
    }
    
    private func startPingTimer() {
        stopPingTimer()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.sendPing()
        }
    }
    
    private func stopPingTimer() {
        pingTimer?.invalidate()
        pingTimer = nil
    }
    
    private func sendPing() {
        webSocketTask?.sendPing { error in
            if let error = error {
                Task { @MainActor [weak self] in
                    self?.handleDisconnection()
                }
            } else {
            }
        }
    }
    
    func disconnect() {
        
        stopPingTimer()
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        reconnectAttempts = 0
        isReconnecting = false
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession = nil
        isConnected = false
        currentRoomId = nil
        currentAccessToken = nil
    }
    
    func sendMessage(_ message: WebSocketOutgoingMessage) {
        guard let task = webSocketTask,
              task.state == .running else {
            return
        }
        
        guard let jsonData = try? JSONEncoder().encode(message),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }
        

        if let encryptedSessionKey = message.encryptedSessionKey {
            let preview = String(encryptedSessionKey.prefix(50)) + "..."
            print("📋 Encrypted Session Key: \(preview)")
        }
        if let replyTo = message.replyTo {
            print("📋 Reply To: \(replyTo)")
        }
        if let assetId = message.assetId {
            print("📋 Asset ID: \(assetId)")
        }
        
        let wsMessage = URLSessionWebSocketTask.Message.string(jsonString)
        task.send(wsMessage) { error in
            if let error = error {
            } else {
            }
        }
    }
    
    private func maskSensitiveData(_ text: String) -> String {
        var masked = text
        masked = masked.replacingOccurrences(
            of: #""encrypted_content"\s*:\s*"([^"]{0,50})[^"]*""#,
            with: #""encrypted_content":"$1..."#,
            options: .regularExpression
        )
        return masked
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                self.handleMessage(message)
                self.receiveMessage()
                
            case .failure(let error):
                self.handleDisconnection()
            }
        }
    }
    
    // MARK: - 메시지 처리
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            guard let data = text.data(using: .utf8) else {
                return
            }
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            do {
                let incomingMessage = try decoder.decode(WebSocketIncomingMessage.self, from: data)
                
                Task { @MainActor in
                    switch incomingMessage.type {
                    case .chatMessage:
                        if let message = incomingMessage.message {
                            self.receivedMessage.send(incomingMessage)
                        } else {
                        }
                        
                    case .typing:
                        if let user = incomingMessage.user,
                           let isTyping = incomingMessage.isTyping {
                            self.typingIndicator.send((user: user, isTyping: isTyping))
                        }
                        
                    case .readReceipt:
                        if let userId = incomingMessage.userId,
                           let messageIds = incomingMessage.messageIds {
                            self.readReceipt.send((userId: userId, messageIds: messageIds))
                        }
                        
                    case .messageUpdate:
                        if let message = incomingMessage.message {
                            self.messageUpdate.send(message)
                        }
                        
                    case .messageDelete:
                        if let messageId = incomingMessage.messageId {
                            self.messageDelete.send(messageId)
                        }
                        
                    case .userStatus:
                        if let userId = incomingMessage.userId,
                           let status = incomingMessage.status {
                            self.userStatus.send((userId: userId, status: status))
                        }
                        
                    case .error:
                        if let errorMessage = incomingMessage.errorMessage {
                            self.connectionError = errorMessage
                            
                        }
                    }
                }
            } catch {
                return
            }
            
        case .data(let data):
            // Binary data is not expected, ignore
            break
            
        @unknown default:
            break
        }
    }
    
    private func handleDisconnection() {
        guard !isReconnecting else {
            return
        }
        
        isConnected = false
        stopPingTimer()
        reconnectTimer?.invalidate()
        
        if let roomId = currentRoomId,
           let token = currentAccessToken {
            isReconnecting = true
            reconnectAttempts += 1
            
            let backoffDelay = pow(2.0, Double(reconnectAttempts - 1))
            let delay = min(backoffDelay, maxReconnectDelay)
            
            reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.isReconnecting = false
                    self?.connect(roomId: roomId, accessToken: token, isReconnect: true)
                }
            }
        } else {
            isReconnecting = false
        }
    }
    
    private func buildWebSocketURL(roomId: String, token: String) -> URL? {
        let baseURL = EnvironmentVariables.baseURL
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")
        let path = "/ws/chat/\(roomId)/"
        let query = "token=\(token)"
        
        var components = URLComponents(string: baseURL)
        components?.path = path
        components?.query = query
        
        return components?.url
    }
}
