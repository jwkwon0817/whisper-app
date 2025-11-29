//
//  NotificationManager.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation
import Combine
import UserNotifications

@MainActor
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    @Published var unreadCount = 0
    @Published var notifications: [AppNotification] = []
    @Published var friendRequestCount = 0
    
    // 현재 활성화된 채팅방 ID (해당 채팅방의 알림은 표시하지 않음)
    var currentActiveChatRoomId: String?
    
    let friendRequestReceived = PassthroughSubject<AppNotification, Never>()
    let newMessageReceived = PassthroughSubject<AppNotification, Never>()
    
    private let wsManager = NotificationWebSocketManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupSubscriptions()
        requestNotificationPermission()
    }
    
    func connect() {
        if let accessToken = KeychainHelper.getItem(forAccount: "accessToken") {
            wsManager.connect(accessToken: accessToken)
        }
    }
    
    func disconnect() {
        wsManager.disconnect()
    }
    
    private func setupSubscriptions() {
        wsManager.receivedNotification
            .sink { [weak self] notification in
                Task { @MainActor in
                    self?.handleNotification(notification)
                }
            }
            .store(in: &cancellables)
    }
    
    private func handleNotification(_ notification: AppNotification) {
        notifications.insert(notification, at: 0)
        
        switch notification.type {
        case .friendRequest:
            unreadCount += 1
            friendRequestCount += 1
            friendRequestReceived.send(notification)
            
            showLocalNotification(
                title: "새로운 친구 요청",
                body: "\(notification.data.userName ?? "누군가")님이 친구 요청을 보냈습니다.",
                identifier: notification.id
            )
            
        case .newMessage:
            // 현재 활성화된 채팅방의 메시지면 알림 표시하지 않음
            let isActiveRoom = notification.data.roomId != nil && notification.data.roomId == currentActiveChatRoomId
            
            if isActiveRoom {
                #if DEBUG
                print("🔕 [NotificationManager] 현재 채팅방 메시지 - 알림 표시 안함: \(notification.data.roomId ?? "")")
                #endif
                // 활성 채팅방이어도 newMessageReceived는 전송 (채팅방 내 UI 업데이트용)
                newMessageReceived.send(notification)
                return
            }
            
            // 활성 채팅방이 아닌 경우에만 알림 표시
            newMessageReceived.send(notification)
            
            if let senderName = notification.data.sender?.name {
                let messageType = notification.data.messageType ?? "text"
                let content: String
                
                if let providedContent = notification.data.content {
                    content = providedContent
                } else {
                    switch messageType {
                    case "image":
                        content = "📷 사진"
                    case "file":
                        content = "📎 파일"
                    default:
                        content = "새로운 메시지"
                    }
                }
                
                showLocalNotification(
                    title: senderName,
                    body: content,
                    identifier: notification.id
                )
            }
            
        case .groupChatInvitation:
            unreadCount += 1
            showLocalNotification(
                title: "그룹 초대",
                body: "새로운 그룹 채팅 초대가 도착했습니다.",
                identifier: notification.id
            )
        }
    }
    
    func markAsRead(_ notification: AppNotification) {
        if let index = notifications.firstIndex(where: { $0.id == notification.id }) {
            unreadCount = max(0, unreadCount - 1)
            if notification.type == .friendRequest {
                friendRequestCount = max(0, friendRequestCount - 1)
            }
        }
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("알림 권한 요청 실패: \(error)")
            }
        }
    }
    
    private func showLocalNotification(title: String, body: String, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("로컬 알림 추가 실패: \(error)")
            }
        }
    }
}

