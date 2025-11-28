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

/// 읽음 확인 처리를 담당하는 핸들러
@MainActor
final class ReadReceiptHandler {
    
    // MARK: - Dependencies
    
    private let roomId: String
    private let wsManager: ChatWebSocketManager
    private let apiService: ChatService
    
    // MARK: - State
    
    private var unreadMessageIds: Set<String> = []
    private var pendingReadIds: Set<String> = []
    private var readReceiptTask: Task<Void, Never>?
    
    // MARK: - Callbacks
    
    var onMessagesMarkedAsRead: (([String]) -> Void)?
    var onReadReceiptFailed: (([String: Bool]) -> Void)? // original read status for rollback
    
    // MARK: - Init
    
    init(
        roomId: String,
        wsManager: ChatWebSocketManager = .shared,
        apiService: ChatService = NetworkManager.shared.chatService
    ) {
        self.roomId = roomId
        self.wsManager = wsManager
        self.apiService = apiService
    }
    
    // MARK: - Public Methods
    
    /// 메시지가 화면에 나타났을 때 호출
    func onMessageAppear(_ message: Message) {
        guard !message.isFromCurrentUser && !message.isRead else { return }
        guard !pendingReadIds.contains(message.id) else { return }
        
        unreadMessageIds.insert(message.id)
        
        // 디바운스 처리
        readReceiptTask?.cancel()
        readReceiptTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Constants.readReceiptDebounceNanoseconds)
            
            guard !Task.isCancelled, !unreadMessageIds.isEmpty else { return }
            
            let idsToMark = Array(unreadMessageIds)
            unreadMessageIds.removeAll()
            
            await markMessagesAsRead(messageIds: idsToMark)
        }
    }
    
    /// 메시지들을 읽음 처리
    func markMessagesAsRead(messageIds: [String]) async {
        let newIds = messageIds.filter { !pendingReadIds.contains($0) }
        guard !newIds.isEmpty else { return }
        
        pendingReadIds.formUnion(newIds)
        
        // 낙관적 업데이트를 위한 콜백 호출
        onMessagesMarkedAsRead?(newIds)
        
        #if DEBUG
        print("✅ [ReadReceiptHandler] 즉시 읽음 처리 (낙관적 업데이트) - 개수: \(newIds.count)")
        #endif
        
        // WebSocket으로 읽음 확인 전송
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
        
        // API 호출
        do {
            try await apiService.markMessagesAsRead(roomId: roomId, messageIds: newIds)
            pendingReadIds.subtract(newIds)
            
            #if DEBUG
            print("✅ [ReadReceiptHandler] 읽음 처리 API 호출 성공")
            #endif
        } catch {
            pendingReadIds.subtract(newIds)
            
            #if DEBUG
            print("❌ [ReadReceiptHandler] 읽음 처리 API 호출 실패 (롤백 필요): \(error)")
            #endif
            
            // 롤백을 위한 정보 전달 (모두 false로 롤백)
            let rollbackStatus = Dictionary(uniqueKeysWithValues: newIds.map { ($0, false) })
            onReadReceiptFailed?(rollbackStatus)
        }
    }
    
    /// 보류 중인 읽음 확인 즉시 전송
    func flushPendingReadReceipts() async {
        readReceiptTask?.cancel()
        readReceiptTask = nil
        
        if !unreadMessageIds.isEmpty {
            let idsToMark = Array(unreadMessageIds)
            unreadMessageIds.removeAll()
            await markMessagesAsRead(messageIds: idsToMark)
        }
    }
    
    /// 정리
    func cleanup() {
        readReceiptTask?.cancel()
        readReceiptTask = nil
        unreadMessageIds.removeAll()
        pendingReadIds.removeAll()
    }
}

