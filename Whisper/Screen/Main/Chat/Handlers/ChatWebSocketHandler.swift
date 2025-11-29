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

@MainActor
final class ChatWebSocketHandler {
    
    private let roomId: String
    private let wsManager: ChatWebSocketManager
    
    private var cancellables = Set<AnyCancellable>()
    private var isDisconnected = false
    private var wasDisconnected = false
    
    var onNewMessage: ((Message) -> Void)?
    var onTypingIndicator: ((User, Bool) -> Void)?
    var onReadReceipt: ((String, [String]) -> Void)?
    var onMessageUpdate: ((Message) -> Void)?
    var onMessageDelete: ((String) -> Void)?
    var onUserStatusChange: ((String, String) -> Void)?
    var onConnectionStatusChange: ((Bool) -> Void)?
    var onReconnected: (() async -> Void)?
    
    init(
        roomId: String,
        wsManager: ChatWebSocketManager = .shared
    ) {
        self.roomId = roomId
        self.wsManager = wsManager
    }
    
    func connect() {
        guard let accessToken = KeychainHelper.getItem(forAccount: "accessToken") else {
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
    
    func disconnect() {
        guard !isDisconnected else { return }
        isDisconnected = true
        
        cancellables.removeAll()
        
        if wsManager.currentRoomId == roomId {
            wsManager.disconnect()
        }
    }
    
    func setupSubscriptions() {
        setupConnectionSubscription()
        setupMessageSubscription()
        setupTypingSubscription()
        setupReadReceiptSubscription()
        setupMessageUpdateSubscription()
        setupMessageDeleteSubscription()
        setupUserStatusSubscription()
    }
    
    var isConnected: Bool {
        wsManager.isConnected && wsManager.currentRoomId == roomId
    }
    
    var currentRoomId: String? {
        wsManager.currentRoomId
    }
    
    private func setupConnectionSubscription() {
        wsManager.$isConnected
            .sink { [weak self] isConnected in
                Task { @MainActor in
                    guard let self = self, !self.isDisconnected else { return }
                    
                    self.onConnectionStatusChange?(isConnected)
                    
                    if !isConnected {
                        self.wasDisconnected = true
                        if let accessToken = KeychainHelper.getItem(forAccount: "accessToken") {
                            self.wsManager.connect(roomId: self.roomId, accessToken: accessToken)
                        }
                    } else if self.wasDisconnected {
                        self.wasDisconnected = false
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

extension ChatWebSocketHandler {
    static func matchTempMessage(
        newMessage: Message,
        tempMessages: [(index: Int, message: Message)]
    ) -> (index: Int, tempId: String, matchMethod: String)? {
        
        if let encryptedContent = newMessage.encryptedContent {
            if let match = tempMessages.first(where: { $0.message.encryptedContent == encryptedContent }) {
                return (match.index, match.message.id, "encryptedContent")
            }
        }
        
        if let asset = newMessage.asset {
            if let match = tempMessages.first(where: { $0.message.asset?.id == asset.id }) {
                return (match.index, match.message.id, "assetId")
            }
        }
        
        if let content = newMessage.content, !content.isEmpty {
            if let match = tempMessages.first(where: { $0.message.content == content }) {
                return (match.index, match.message.id, "content")
            }
        }
        
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

