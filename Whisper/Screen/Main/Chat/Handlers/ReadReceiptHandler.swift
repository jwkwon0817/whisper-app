//
//  ReadReceiptHandler.swift
//  Whisper
//
//  Created by Refactoring on 11/28/25.
//

import Foundation

private enum Constants {
    static let readReceiptDebounceNanoseconds: UInt64 = 300_000_000
}

@MainActor
final class ReadReceiptHandler {
    
    private let roomId: String
    private let wsManager: ChatWebSocketManager
    private let apiService: ChatService
    
    private var unreadMessageIds: Set<String> = []
    private var pendingReadIds: Set<String> = []
    private var readReceiptTask: Task<Void, Never>?
    
    var onMessagesMarkedAsRead: (([String]) -> Void)?
    var onReadReceiptFailed: (([String: Bool]) -> Void)?
    
    init(
        roomId: String,
        wsManager: ChatWebSocketManager = .shared,
        apiService: ChatService = NetworkManager.shared.chatService
    ) {
        self.roomId = roomId
        self.wsManager = wsManager
        self.apiService = apiService
    }
    
    func onMessageAppear(_ message: Message) {
        guard !message.isFromCurrentUser && !message.isRead else { return }
        guard !pendingReadIds.contains(message.id) else { return }
        
        unreadMessageIds.insert(message.id)
        
        readReceiptTask?.cancel()
        readReceiptTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Constants.readReceiptDebounceNanoseconds)
            
            guard !Task.isCancelled, !unreadMessageIds.isEmpty else { return }
            
            let idsToMark = Array(unreadMessageIds)
            unreadMessageIds.removeAll()
            
            await markMessagesAsRead(messageIds: idsToMark)
        }
    }
    
    func markMessagesAsRead(messageIds: [String]) async {
        let newIds = messageIds.filter { !pendingReadIds.contains($0) }
        guard !newIds.isEmpty else { return }
        
        pendingReadIds.formUnion(newIds)
        
        onMessagesMarkedAsRead?(newIds)
        
        if wsManager.isConnected && wsManager.currentRoomId == roomId {
            let message = WebSocketOutgoingMessage(
                type: "read_receipt",
                messageType: nil,
                content: nil,
                encryptedContent: nil,
                encryptedSessionKey: nil,
                selfEncryptedSessionKey: nil,
                replyTo: nil,
                assetId: nil,
                isTyping: nil,
                messageIds: newIds
            )
            wsManager.sendMessage(message)
        }
        
        do {
            try await apiService.markMessagesAsRead(roomId: roomId, messageIds: newIds)
            pendingReadIds.subtract(newIds)
            
        } catch {
            pendingReadIds.subtract(newIds)
            
            let rollbackStatus = Dictionary(uniqueKeysWithValues: newIds.map { ($0, false) })
            onReadReceiptFailed?(rollbackStatus)
        }
    }
    
    func flushPendingReadReceipts() async {
        readReceiptTask?.cancel()
        readReceiptTask = nil
        
        if !unreadMessageIds.isEmpty {
            let idsToMark = Array(unreadMessageIds)
            unreadMessageIds.removeAll()
            await markMessagesAsRead(messageIds: idsToMark)
        }
    }
    
    func cleanup() {
        readReceiptTask?.cancel()
        readReceiptTask = nil
        unreadMessageIds.removeAll()
        pendingReadIds.removeAll()
    }
}

