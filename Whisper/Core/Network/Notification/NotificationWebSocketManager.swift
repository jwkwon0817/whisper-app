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
    
    enum CodingKeys: String, CodingKey {
        case friendId = "friend_id"
        case invitationId = "invitation_id"
        case roomId = "room_id"
        case userId = "user_id"
        case userName = "user_name"
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
        guard let url = buildWebSocketURL(token: accessToken) else {
            connectionError = "Invalid WebSocket URL"
            return
        }
        
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        urlSession = session
        
        webSocketTask?.resume()
        isConnected = true
        connectionError = nil
        
        receiveNotification()
    }
    
    // MARK: - 연결 해제
    func disconnect() {
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
                print("Notification WebSocket receive error: \(error)")
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
            guard let data = text.data(using: .utf8) else {
                return
            }
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let type = json["type"] as? String,
                   type == "notification",
                   let notificationData = json["notification"] as? [String: Any],
                   let notificationJsonData = try? JSONSerialization.data(withJSONObject: notificationData),
                   let notification = try? decoder.decode(AppNotification.self, from: notificationJsonData) {
                    Task { @MainActor in
                        self.receivedNotification.send(notification)
                    }
                }
            } catch {
                print("Failed to decode notification: \(error)")
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

