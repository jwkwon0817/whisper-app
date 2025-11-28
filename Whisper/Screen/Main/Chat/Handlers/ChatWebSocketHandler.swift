//
//  ChatWebSocketHandler.swift
//  Whisper
//
//  Created by Refactoring on 11/28/25.
//

import Combine
import Foundation

private enum Constants {
    static let reconnectDelayNanoseconds: UInt64 = 500_000_000
    static let tempMessageMatchingInterval: TimeInterval = 3.0
}

/// WebSocket 이벤트 처리를 담당하는 핸들러
@MainActor
final class ChatWebSocketHandler {
    
    // MARK: - Dependencies
    
    private let roomId: String
    private let wsManager: ChatWebSocketManager
    
    // MARK: - State
    
    private var cancellables = Set<AnyCancellable>()
    private var isDisconnected = false
    private var wasDisconnected = false
    
    // MARK: - Callbacks
    
    var onNewMessage: ((Message) -> Void)?
    var onTypingIndicator: ((User, Bool) -> Void)?
    var onReadReceipt: ((String, [String]) -> Void)? // (userId, messageIds)
    var onMessageUpdate: ((Message) -> Void)?
    var onMessageDelete: ((String) -> Void)?
    var onUserStatusChange: ((String, String) -> Void)? // (userId, status)
    var onConnectionStatusChange: ((Bool) -> Void)?
    var onReconnected: (() async -> Void)?
    
    // MARK: - Init
    
    init(
        roomId: String,
        wsManager: ChatWebSocketManager = .shared
    ) {
        self.roomId = roomId
        self.wsManager = wsManager
    }
    
    // MARK: - Public Methods
    
    /// WebSocket 연결
    func connect() {
        guard let accessToken = KeychainHelper.getItem(forAccount: "accessToken") else {
            #if DEBUG
            print("⚠️ [ChatWebSocketHandler] 인증 토큰이 없어 연결할 수 없습니다.")
            #endif
            return
        }
        
        isDisconnected = false
        
        Task {
            if wsManager.currentRoomId != nil && wsManager.currentRoomId != roomId {
                wsManager.disconnect()
                try? await Task.sleep(nanoseconds: Constants.reconnectDelayNanoseconds)
            }
            
            wsManager.connect(roomId: roomId, accessToken: accessToken)
        }
    }
    
    /// WebSocket 연결 해제
    func disconnect() {
        guard !isDisconnected else { return }
        isDisconnected = true
        
        #if DEBUG
        print("🔌 [ChatWebSocketHandler] disconnect 호출됨")
        #endif
        
        cancellables.removeAll()
        
        if wsManager.currentRoomId == roomId {
            wsManager.disconnect()
        }
    }
    
    /// WebSocket 구독 설정
    func setupSubscriptions() {
        #if DEBUG
        print("📡 [ChatWebSocketHandler] setupSubscriptions 시작")
        #endif
        
        setupConnectionSubscription()
        setupMessageSubscription()
        setupTypingSubscription()
        setupReadReceiptSubscription()
        setupMessageUpdateSubscription()
        setupMessageDeleteSubscription()
        setupUserStatusSubscription()
    }
    
    /// 연결 상태 확인
    var isConnected: Bool {
        wsManager.isConnected && wsManager.currentRoomId == roomId
    }
    
    /// 현재 연결된 방 ID
    var currentRoomId: String? {
        wsManager.currentRoomId
    }
    
    // MARK: - Private Methods
    
    private func setupConnectionSubscription() {
        wsManager.$isConnected
            .sink { [weak self] isConnected in
                Task { @MainActor in
                    guard let self = self, !self.isDisconnected else { return }
                    
                    #if DEBUG
                    print("🔌 [ChatWebSocketHandler] WebSocket 연결 상태 변경: \(isConnected ? "연결됨" : "연결 끊김")")
                    #endif
                    
                    self.onConnectionStatusChange?(isConnected)
                    
                    if !isConnected {
                        self.wasDisconnected = true
                        // 자동 재연결
                        if let accessToken = KeychainHelper.getItem(forAccount: "accessToken") {
                            #if DEBUG
                            print("🔄 [ChatWebSocketHandler] WebSocket 재연결 시도")
                            #endif
                            self.wsManager.connect(roomId: self.roomId, accessToken: accessToken)
                        }
                    } else if self.wasDisconnected {
                        self.wasDisconnected = false
                        #if DEBUG
                        print("🔄 [ChatWebSocketHandler] WebSocket 재연결 성공 - 최신 메시지 동기화")
                        #endif
                        
                        try? await Task.sleep(nanoseconds: Constants.reconnectDelayNanoseconds)
                        await self.onReconnected?()
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupMessageSubscription() {
        wsManager.receivedMessage
            .sink { [weak self] incomingMessage in
                Task { @MainActor in
                    guard let self = self else { return }
                    guard !self.isDisconnected else { return }
                    guard self.wsManager.currentRoomId == self.roomId else { return }
                    
                    if let message = incomingMessage.message {
                        guard message.room.contains(self.roomId) else { return }
                        self.onNewMessage?(message)
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupTypingSubscription() {
        wsManager.typingIndicator
            .sink { [weak self] user, isTyping in
                Task { @MainActor in
                    guard let self = self else { return }
                    guard let currentUserId = CurrentUser.shared.id,
                          user.id != currentUserId else { return }
                    
                    self.onTypingIndicator?(user, isTyping)
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupReadReceiptSubscription() {
        wsManager.readReceipt
            .sink { [weak self] userId, messageIds in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.onReadReceipt?(userId, messageIds)
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupMessageUpdateSubscription() {
        wsManager.messageUpdate
            .sink { [weak self] updatedMessage in
                Task { @MainActor in
                    guard let self = self else { return }
                    
                    #if DEBUG
                    print("✏️ [ChatWebSocketHandler] 메시지 수정 이벤트 수신 - Message ID: \(updatedMessage.id)")
                    #endif
                    
                    self.onMessageUpdate?(updatedMessage)
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupMessageDeleteSubscription() {
        wsManager.messageDelete
            .sink { [weak self] messageId in
                Task { @MainActor in
                    guard let self = self else { return }
                    
                    #if DEBUG
                    print("🗑️ [ChatWebSocketHandler] 메시지 삭제 이벤트 수신 - Message ID: \(messageId)")
                    #endif
                    
                    self.onMessageDelete?(messageId)
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupUserStatusSubscription() {
        wsManager.userStatus
            .sink { [weak self] userId, status in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.onUserStatusChange?(userId, status)
                }
            }
            .store(in: &cancellables)
    }
}

// MARK: - Helper Extension for Temp Message Matching

extension ChatWebSocketHandler {
    
    /// 임시 메시지와 실제 메시지 매칭
    static func matchTempMessage(
        newMessage: Message,
        tempMessages: [(index: Int, message: Message)]
    ) -> (index: Int, tempId: String, matchMethod: String)? {
        
        // 1. encryptedContent로 매칭 (텍스트 메시지)
        if let encryptedContent = newMessage.encryptedContent {
            if let match = tempMessages.first(where: { $0.message.encryptedContent == encryptedContent }) {
                return (match.index, match.message.id, "encryptedContent")
            }
        }
        
        // 2. asset.id로 매칭 (이미지/파일 메시지)
        if let asset = newMessage.asset {
            if let match = tempMessages.first(where: { $0.message.asset?.id == asset.id }) {
                return (match.index, match.message.id, "assetId")
            }
        }
        
        // 3. content로 매칭 (그룹 채팅 텍스트 메시지)
        if let content = newMessage.content, !content.isEmpty {
            if let match = tempMessages.first(where: { $0.message.content == content }) {
                return (match.index, match.message.id, "content")
            }
        }
        
        // 4. 시간 기반 매칭 (최근 3초 이내 같은 타입의 임시 메시지)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = Date()
        
        if let match = tempMessages.first(where: { item in
            let tempMsg = item.message
            guard tempMsg.messageType == newMessage.messageType else { return false }
            
            if let tempDate = formatter.date(from: tempMsg.createdAt) {
                let timeDiff = now.timeIntervalSince(tempDate)
                return timeDiff < Constants.tempMessageMatchingInterval && timeDiff >= 0
            }
            return false
        }) {
            return (match.index, match.message.id, "timeAndType")
        }
        
        return nil
    }
}

