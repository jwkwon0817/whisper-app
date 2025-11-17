//
//  NotificationManager.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation
import Combine
import UserNotifications

// MARK: - Notification Manager
@MainActor
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    @Published var unreadCount = 0
    @Published var notifications: [AppNotification] = []
    @Published var friendRequestCount = 0
    
    // 친구 요청 알림을 위한 PassthroughSubject
    let friendRequestReceived = PassthroughSubject<AppNotification, Never>()
    
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
        unreadCount += 1
        
        // 친구 요청 알림인 경우
        if notification.type == .friendRequest {
            friendRequestCount += 1
            friendRequestReceived.send(notification)
            
            // 로컬 알림 표시
            showLocalNotification(
                title: "새로운 친구 요청",
                body: "\(notification.data.userName ?? "누군가")님이 친구 요청을 보냈습니다.",
                identifier: notification.id
            )
        }
    }
    
    func markAsRead(_ notification: AppNotification) {
        if let index = notifications.firstIndex(where: { $0.id == notification.id }) {
            // 읽음 처리 로직
            unreadCount = max(0, unreadCount - 1)
            if notification.type == .friendRequest {
                friendRequestCount = max(0, friendRequestCount - 1)
            }
        }
    }
    
    // MARK: - 로컬 알림 권한 요청
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("알림 권한 요청 실패: \(error)")
            }
        }
    }
    
    // MARK: - 로컬 알림 표시
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

