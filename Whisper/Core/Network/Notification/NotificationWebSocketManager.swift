//
//  NotificationWebSocketManager.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation
import Combine

// MARK: - Notification Model
struct AppNotification: Identifiable, Codable {
    let id: String
    let type: NotificationType
    let data: NotificationData
    let createdAt: String
    
    enum NotificationType: String, Codable {
        case friendRequest = "friend_request"
        case groupChatInvitation = "group_chat_invitation"
        case newMessage = "new_message"
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case type
        case data
        case createdAt = "created_at"
    }
}

// MARK: - Notification Data
struct NotificationData: Codable {
    let friendId: String?
    let invitationId: String?
    let roomId: String?
    let userId: String?
    let userName: String?
    
    // MARK: - Chat Notification Fields
    let messageId: String?
    let messageType: String?
    let content: String?
    let encryptedContent: String?
    let encryptedSessionKey: String?
    let sender: SenderInfo?
    
    enum CodingKeys: String, CodingKey {
        case friendId = "friend_id"
        case invitationId = "invitation_id"
        case roomId = "room_id"
        case userId = "user_id"
        case userName = "user_name"
        
        case messageId = "message_id"
        case messageType = "message_type"
        case content
        case encryptedContent = "encrypted_content"
        case encryptedSessionKey = "encrypted_session_key"
        case sender
    }
}

// MARK: - Sender Info
struct SenderInfo: Codable {
    let id: String
    let name: String
    let profileImage: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case profileImage = "profile_image"
    }
}

// MARK: - Notification WebSocket Manager
@MainActor
class NotificationWebSocketManager: ObservableObject {
    static let shared = NotificationWebSocketManager()
    
    @Published var isConnected = false
    @Published var connectionError: String?
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    
    // 알림 수신을 위한 PassthroughSubject
    let receivedNotification = PassthroughSubject<AppNotification, Never>()
    
    private init() {}
    
    // MARK: - 연결
    func connect(accessToken: String) {
        #if DEBUG
        print("\n" + String(repeating: "=", count: 80))
        print("🔌 [NotificationWebSocket] 연결 시도")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        #endif
        
        guard let url = buildWebSocketURL(token: accessToken) else {
            #if DEBUG
            print("❌ [NotificationWebSocket] WebSocket URL 생성 실패")
            print(String(repeating: "=", count: 80) + "\n")
            #endif
            connectionError = "Invalid WebSocket URL"
            return
        }
        
        #if DEBUG
        print("🌐 WebSocket URL: \(url.absoluteString)")
        #endif
        
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        urlSession = session
        
        webSocketTask?.resume()
        isConnected = true
        connectionError = nil
        
        #if DEBUG
        print("✅ [NotificationWebSocket] 연결 시작")
        print(String(repeating: "=", count: 80) + "\n")
        #endif
        
        receiveNotification()
    }
    
    // MARK: - 연결 해제
    func disconnect() {
        #if DEBUG
        print("\n" + String(repeating: "=", count: 80))
        print("🔌 [NotificationWebSocket] 연결 해제")
        print(String(repeating: "=", count: 80) + "\n")
        #endif
        
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession = nil
        isConnected = false
    }
    
    // MARK: - 알림 수신
    private func receiveNotification() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                self.handleMessage(message)
                self.receiveNotification()  // 다음 알림 수신 대기
                
            case .failure(let error):
                #if DEBUG
                print("\n" + String(repeating: "=", count: 80))
                print("❌ [NotificationWebSocket] 메시지 수신 실패")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("🔴 Error: \(error.localizedDescription)")
                print(String(repeating: "=", count: 80) + "\n")
                #endif
                Task { @MainActor in
                    self.isConnected = false
                }
            }
        }
    }
    
    // MARK: - 메시지 처리
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            #if DEBUG
            print("\n" + String(repeating: "-", count: 80))
            print("📨 [NotificationWebSocket] 메시지 수신")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("📦 원본 메시지:")
            print(text)
            #endif
            
            guard let data = text.data(using: .utf8) else {
                #if DEBUG
                print("❌ [NotificationWebSocket] 문자열을 데이터로 변환 실패")
                print(String(repeating: "-", count: 80) + "\n")
                #endif
                return
            }
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    #if DEBUG
                    print("📋 JSON 구조:")
                    print(json)
                    #endif
                    
                    if let type = json["type"] as? String,
                       type == "notification",
                       let notificationData = json["notification"] as? [String: Any],
                       let notificationJsonData = try? JSONSerialization.data(withJSONObject: notificationData),
                       let notification = try? decoder.decode(AppNotification.self, from: notificationJsonData) {
                        #if DEBUG
                        print("✅ [NotificationWebSocket] 알림 디코딩 성공")
                        print("📋 Notification ID: \(notification.id)")
                        print("📋 Notification Type: \(notification.type)")
                        print(String(repeating: "-", count: 80) + "\n")
                        #endif
                        
                        Task { @MainActor in
                            self.receivedNotification.send(notification)
                        }
                    } else {
                        #if DEBUG
                        print("⚠️ [NotificationWebSocket] 알림 형식이 아님 또는 디코딩 실패")
                        print(String(repeating: "-", count: 80) + "\n")
                        #endif
                    }
                }
            } catch {
                #if DEBUG
                print("❌ [NotificationWebSocket] 알림 디코딩 실패: \(error)")
                print("   원본 메시지: \(text)")
                print(String(repeating: "-", count: 80) + "\n")
                #endif
            }
            
        case .data:
            break
            
        @unknown default:
            break
        }
    }
    
    // MARK: - URL 생성
    private func buildWebSocketURL(token: String) -> URL? {
        let baseURL = EnvironmentVariables.baseURL
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")
        let path = "/ws/notifications/"
        let query = "token=\(token)"
        
        var components = URLComponents(string: baseURL)
        components?.path = path
        components?.query = query
        
        return components?.url
    }
}

