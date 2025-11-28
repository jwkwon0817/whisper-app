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
    case messageUpdate = "message_update"
    case messageDelete = "message_delete"
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
        
        // errorMessage는 명시적으로 있거나, message 필드가 문자열인 경우 그 값을 사용
        if let errorMsg = try? container.decode(String.self, forKey: .errorMessage) {
            errorMessage = errorMsg
        } else if type == .error, let messageStr = try? container.decode(String.self, forKey: .message) {
            // 에러 타입이고 message가 문자열인 경우
            errorMessage = messageStr
        } else {
            errorMessage = nil
        }
    }
}

// MARK: - WebSocket Outgoing Message
struct WebSocketOutgoingMessage: Codable {
    let type: String
    let messageType: String?
    let content: String?
    let encryptedContent: String?  // AES 암호화된 메시지 (하이브리드 방식) 또는 RSA 암호화된 메시지 (기존 방식)
    let encryptedSessionKey: String?  // RSA 암호화된 AES 세션 키 (하이브리드 방식) - 상대방 공개키로 암호화
    let selfEncryptedSessionKey: String?  // RSA 암호화된 AES 세션 키 (하이브리드 방식) - 내 공개키로 암호화 (양방향 복호화용)
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
    private let maxReconnectDelay: TimeInterval = 60.0 // 최대 재연결 대기 시간 (60초)
    private var isReconnecting = false  // 재연결 중복 방지
    
    // Ping Timer
    private var pingTimer: Timer?
    
    var currentRoomId: String?
    private var currentAccessToken: String?
    
    // 메시지 수신을 위한 PassthroughSubject
    let receivedMessage = PassthroughSubject<WebSocketIncomingMessage, Never>()
    let typingIndicator = PassthroughSubject<(user: User, isTyping: Bool), Never>()
    let readReceipt = PassthroughSubject<(userId: String, messageIds: [String]), Never>()
    let messageUpdate = PassthroughSubject<Message, Never>()
    let messageDelete = PassthroughSubject<String, Never>()
    let userStatus = PassthroughSubject<(userId: String, status: String), Never>()
    
    private init() {}
    
    // MARK: - 연결
    func connect(roomId: String, accessToken: String, isReconnect: Bool = false) {
        #if DEBUG
        print("\n" + String(repeating: "=", count: 80))
        print("🔌 [ChatWebSocket] 연결 시도 (재연결: \(isReconnect))")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📍 Room ID: \(roomId)")
        #endif
        
        guard let url = buildWebSocketURL(roomId: roomId, token: accessToken) else {
            #if DEBUG
            print("❌ [ChatWebSocket] WebSocket URL 생성 실패")
            print(String(repeating: "=", count: 80) + "\n")
            #endif
            connectionError = "Invalid WebSocket URL"
            return
        }
        
        #if DEBUG
        print("🌐 WebSocket URL: \(url.absoluteString)")
        #endif
        
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
        
        #if DEBUG
        print("✅ [ChatWebSocket] 연결 시작")
        print(String(repeating: "=", count: 80) + "\n")
        #endif
        
        startPingTimer()
        receiveMessage()
    }
    
    // MARK: - Ping Timer
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
                #if DEBUG
                print("❌ [ChatWebSocket] Ping 실패: \(error)")
                #endif
                // Ping 실패 시 연결 끊김으로 간주하고 재연결 시도
                Task { @MainActor [weak self] in
                    self?.handleDisconnection()
                }
            } else {
                #if DEBUG
                // print("✅ [ChatWebSocket] Ping 성공")
                #endif
            }
        }
    }
    
    // MARK: - 연결 해제
    func disconnect() {
        #if DEBUG
        print("\n" + String(repeating: "=", count: 80))
        print("🔌 [ChatWebSocket] 연결 해제")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        if let roomId = currentRoomId {
            print("📍 Room ID: \(roomId)")
        }
        print(String(repeating: "=", count: 80) + "\n")
        #endif
        
        stopPingTimer()
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        reconnectAttempts = 0  // 재연결 카운터 초기화
        isReconnecting = false  // 재연결 플래그 초기화
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
            #if DEBUG
            print("⚠️ [ChatWebSocket] 메시지 전송 실패 - WebSocket이 연결되지 않음")
            #endif
            return
        }
        
        guard let jsonData = try? JSONEncoder().encode(message),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            #if DEBUG
            print("❌ [ChatWebSocket] 메시지 인코딩 실패")
            #endif
            return
        }
        
        #if DEBUG
        print("\n" + String(repeating: "-", count: 80))
        print("📤 [ChatWebSocket] 메시지 전송")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📋 Type: \(message.type)")
        if let messageType = message.messageType {
            print("📋 Message Type: \(messageType)")
        }
        if let content = message.content {
            print("📋 Content: \(content)")
        }
        if let encryptedContent = message.encryptedContent {
            let preview = String(encryptedContent.prefix(50)) + "..."
            print("📋 Encrypted Content: \(preview)")
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
        print("📦 전체 메시지 (마스킹 전):")
        print(jsonString)
        print("📦 전체 메시지 (마스킹 후):")
        print(maskSensitiveData(jsonString))
        print(String(repeating: "-", count: 80) + "\n")
        #endif
        
        let wsMessage = URLSessionWebSocketTask.Message.string(jsonString)
        task.send(wsMessage) { error in
            if let error = error {
                #if DEBUG
                print("❌ [ChatWebSocket] 메시지 전송 실패: \(error)")
                #endif
            } else {
                #if DEBUG
                print("✅ [ChatWebSocket] 메시지 전송 성공")
                #endif
            }
        }
    }
    
    // MARK: - 민감한 정보 마스킹
    private func maskSensitiveData(_ text: String) -> String {
        var masked = text
        masked = masked.replacingOccurrences(
            of: #""encrypted_content"\s*:\s*"([^"]{0,50})[^"]*""#,
            with: #""encrypted_content":"$1..."#,
            options: .regularExpression
        )
        return masked
    }
    
    // MARK: - 메시지 수신
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                self.handleMessage(message)
                self.receiveMessage()
                
            case .failure(let error):
                #if DEBUG
                print("\n" + String(repeating: "=", count: 80))
                print("❌ [ChatWebSocket] 메시지 수신 실패")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("🔴 Error: \(error.localizedDescription)")
                print(String(repeating: "=", count: 80) + "\n")
                #endif
                self.handleDisconnection()
            }
        }
    }
    
    // MARK: - 메시지 처리
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            #if DEBUG
            print("\n" + String(repeating: "-", count: 80))
            print("📨 [ChatWebSocket] 메시지 수신")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("📦 원본 메시지:")
            print(maskSensitiveData(text))
            #endif
            
            guard let data = text.data(using: .utf8) else {
                #if DEBUG
                print("❌ [ChatWebSocket] 문자열을 데이터로 변환 실패")
                print(String(repeating: "-", count: 80) + "\n")
                #endif
                return
            }
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            do {
                let incomingMessage = try decoder.decode(WebSocketIncomingMessage.self, from: data)
                #if DEBUG
                print("✅ [ChatWebSocket] 메시지 디코딩 성공")
                print("📋 Type: \(incomingMessage.type)")
                if let message = incomingMessage.message {
                    print("📋 Message ID: \(message.id)")
                    print("📋 Message Type: \(message.messageType)")
                    print("📋 Sender: \(message.sender.name)")
                }
                if let user = incomingMessage.user {
                    print("📋 User: \(user.name)")
                }
                if let isTyping = incomingMessage.isTyping {
                    print("📋 Is Typing: \(isTyping)")
                }
                print(String(repeating: "-", count: 80) + "\n")
                #endif
                
                Task { @MainActor in
                    switch incomingMessage.type {
                    case .chatMessage:
                        if let message = incomingMessage.message {
                            #if DEBUG
                            print("📨 [ChatWebSocket] chatMessage 처리 - Message ID: \(message.id)")
                            print("   encryptedContent 존재: \(message.encryptedContent != nil)")
                            print("   encryptedSessionKey 존재: \(message.encryptedSessionKey != nil)")
                            print("   sender: \(message.sender.name) (ID: \(message.sender.id))")
                            #endif
                            self.receivedMessage.send(incomingMessage)
                        } else {
                            #if DEBUG
                            print("⚠️ [ChatWebSocket] chatMessage 타입이지만 message가 nil")
                            #endif
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
                            #if DEBUG
                            print("✏️ [ChatWebSocket] messageUpdate 처리 - Message ID: \(message.id)")
                            #endif
                            self.messageUpdate.send(message)
                        }
                        
                    case .messageDelete:
                        if let messageId = incomingMessage.messageId {
                            #if DEBUG
                            print("🗑️ [ChatWebSocket] messageDelete 처리 - Message ID: \(messageId)")
                            #endif
                            self.messageDelete.send(messageId)
                        }
                        
                    case .userStatus:
                        if let userId = incomingMessage.userId,
                           let status = incomingMessage.status {
                            self.userStatus.send((userId: userId, status: status))
                        }
                        
                    case .error:
                        if let errorMessage = incomingMessage.errorMessage {
                            #if DEBUG
                            print("❌ [ChatWebSocket] 에러 메시지 수신: \(errorMessage)")
                            print("   이는 서버 측 에러입니다. 전송한 메시지 형식을 확인하세요.")
                            #endif
                            self.connectionError = errorMessage
                            
                            // 에러 발생 시 사용자에게 알림 (선택사항)
                            #if DEBUG
                            print("⚠️ [ChatWebSocket] 서버 에러로 인해 메시지 전송이 실패했을 수 있습니다.")
                            #endif
                        }
                    }
                }
            } catch {
                #if DEBUG
                print("❌ [ChatWebSocket] 메시지 디코딩 실패: \(error)")
                print("   원본 메시지: \(text)")
                if let json = try? JSONSerialization.jsonObject(with: data) {
                    print("   JSON 구조: \(json)")
                }
                #endif
                return
            }
            
        case .data(let data):
            #if DEBUG
            print("📦 [ChatWebSocket] 바이너리 데이터 수신: \(data.count) bytes")
            #endif
            
        @unknown default:
            break
        }
    }
    
    // MARK: - 연결 끊김 처리
    private func handleDisconnection() {
        // 이미 재연결 중이면 무시 (중복 방지)
        guard !isReconnecting else {
            #if DEBUG
            print("⚠️ [ChatWebSocket] 이미 재연결 중 - 무시")
            #endif
            return
        }
        
        isConnected = false
        stopPingTimer()
        reconnectTimer?.invalidate()
        
        if let roomId = currentRoomId,
           let token = currentAccessToken {
            isReconnecting = true
            reconnectAttempts += 1
            
            // Exponential Backoff: 1, 2, 4, 8, 16, 32, 60, 60... (최대 60초)
            let backoffDelay = pow(2.0, Double(reconnectAttempts - 1))
            let delay = min(backoffDelay, maxReconnectDelay)
            
            #if DEBUG
            print("⚠️ [ChatWebSocket] 연결 끊김 감지 - 재연결 시도 (시도: \(reconnectAttempts), 대기: \(delay)초)")
            #endif
            
            reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.isReconnecting = false
                    self?.connect(roomId: roomId, accessToken: token, isReconnect: true)
                }
            }
        } else {
            #if DEBUG
            print("❌ [ChatWebSocket] 재연결 정보 부족")
            #endif
            isReconnecting = false
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
