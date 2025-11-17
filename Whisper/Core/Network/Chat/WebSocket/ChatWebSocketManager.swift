//
//  ChatWebSocketManager.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation
import Combine

// MARK: - WebSocket Message Types
enum WebSocketMessageType: String, Codable {
    case chatMessage = "chat_message"
    case typing = "typing"
    case readReceipt = "read_receipt"
    case userStatus = "user_status"
    case error = "error"
}

// MARK: - WebSocket Incoming Message
struct WebSocketIncomingMessage: Codable {
    let type: WebSocketMessageType
    let message: Message?
    let user: User?
    let isTyping: Bool?
    let userId: String?
    let messageIds: [String]?
    let status: String?
    let errorMessage: String?
    
    enum CodingKeys: String, CodingKey {
        case type
        case message
        case user
        case isTyping = "is_typing"
        case userId = "user_id"
        case messageIds = "message_ids"
        case status
        case errorMessage = "error_message"
    }
}

// MARK: - WebSocket Outgoing Message
struct WebSocketOutgoingMessage: Codable {
    let type: String
    let messageType: String?
    let content: String?
    let encryptedContent: String?
    let replyTo: String?
    let assetId: String?
    let isTyping: Bool?
    let messageIds: [String]?
    
    enum CodingKeys: String, CodingKey {
        case type
        case messageType = "message_type"
        case content
        case encryptedContent = "encrypted_content"
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
    private let maxReconnectAttempts = 5
    private let reconnectDelay: TimeInterval = 3.0
    
    private var currentRoomId: String?
    private var currentAccessToken: String?
    
    // 메시지 수신을 위한 PassthroughSubject
    let receivedMessage = PassthroughSubject<WebSocketIncomingMessage, Never>()
    let typingIndicator = PassthroughSubject<(user: User, isTyping: Bool), Never>()
    let readReceipt = PassthroughSubject<(userId: String, messageIds: [String]), Never>()
    let userStatus = PassthroughSubject<(userId: String, status: String), Never>()
    
    private init() {}
    
    // MARK: - 연결
    func connect(roomId: String, accessToken: String) {
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
        reconnectAttempts = 0
        
        receiveMessage()
    }
    
    // MARK: - 연결 해제
    func disconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession = nil
        isConnected = false
        currentRoomId = nil
        currentAccessToken = nil
    }
    
    // MARK: - 메시지 전송
    func sendMessage(_ message: WebSocketOutgoingMessage) {
        guard let task = webSocketTask,
              task.state == .running else {
            print("WebSocket is not connected")
            return
        }
        
        guard let jsonData = try? JSONEncoder().encode(message),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            print("Failed to encode message")
            return
        }
        
        let wsMessage = URLSessionWebSocketTask.Message.string(jsonString)
        task.send(wsMessage) { error in
            if let error = error {
                print("Failed to send message: \(error)")
            }
        }
    }
    
    // MARK: - 메시지 수신
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                self.handleMessage(message)
                self.receiveMessage()  // 다음 메시지 수신 대기
                
            case .failure(let error):
                print("WebSocket receive error: \(error)")
                self.handleDisconnection()
            }
        }
    }
    
    // MARK: - 메시지 처리
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            guard let data = text.data(using: .utf8) else {
                print("Failed to convert string to data")
                return
            }
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            guard let incomingMessage = try? decoder.decode(WebSocketIncomingMessage.self, from: data) else {
                print("Failed to decode WebSocket message")
                return
            }
            
            Task { @MainActor in
                switch incomingMessage.type {
                case .chatMessage:
                    if incomingMessage.message != nil {
                        self.receivedMessage.send(incomingMessage)
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
            
        case .data(let data):
            print("Received binary data: \(data.count) bytes")
            
        @unknown default:
            break
        }
    }
    
    // MARK: - 연결 끊김 처리
    private func handleDisconnection() {
        isConnected = false
        reconnectTimer?.invalidate()
        
        if reconnectAttempts < maxReconnectAttempts,
           let roomId = currentRoomId,
           let token = currentAccessToken {
            reconnectAttempts += 1
            reconnectTimer = Timer.scheduledTimer(withTimeInterval: reconnectDelay, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.connect(roomId: roomId, accessToken: token)
                }
            }
        } else {
            connectionError = "최대 재연결 시도 횟수 초과"
        }
    }
    
    // MARK: - URL 생성
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

