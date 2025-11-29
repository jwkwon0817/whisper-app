//
//  ChatRoomViewModel.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//  Refactored on 11/28/25.
//

import Combine
import SwiftUI

private enum Constants {
    static let typingAutoStopInterval: TimeInterval = 3.0
}

@MainActor
class ChatRoomViewModel: ObservableObject {
    // MARK: - Published State
    
    @Published var room: ChatRoom?
    @Published var messages: [Message] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var typingUsers: [User] = []
    @Published var onlineUsers: Set<String> = []
    @Published var isDecrypting = false
    @Published var isSending = false
    
    private let roomId: String
    private let apiService: ChatService
    
    private let encryptionHandler: MessageEncryptionHandler
    private let sendingHandler: MessageSendingHandler
    private let readReceiptHandler: ReadReceiptHandler
    private let webSocketHandler: ChatWebSocketHandler
    private let cacheManager: MessageCacheManager
    
    private var currentPage = 1
    private var hasMoreMessages = true
    private var typingTimer: Timer?
    private var isDisconnected = false
    private var deletingMessageIds: Set<String> = []
    
    init(roomId: String) {
        self.roomId = roomId
        self.apiService = NetworkManager.shared.chatService
        
        self.encryptionHandler = MessageEncryptionHandler(roomId: roomId)
        self.cacheManager = MessageCacheManager(roomId: roomId)
        self.sendingHandler = MessageSendingHandler(
            roomId: roomId,
            encryptionHandler: encryptionHandler
        )
        self.readReceiptHandler = ReadReceiptHandler(roomId: roomId)
        self.webSocketHandler = ChatWebSocketHandler(roomId: roomId)
        
        setupHandlerCallbacks()
        
        Task {
            await encryptionHandler.loadCachedDecryptedMessages()
        }
    }
    
    private func setupHandlerCallbacks() {
        encryptionHandler.onDecryptionComplete = { [weak self] _, _ in
            self?.objectWillChange.send()
        }
        
        encryptionHandler.onError = { [weak self] message in
            guard let self = self else { return }
            if self.errorMessage == nil {
                self.errorMessage = message
                self.showError = true
            }
        }
        
        sendingHandler.onMessageCreated = { [weak self] message in
            self?.messages.append(message)
        }
        
        sendingHandler.onError = { [weak self] message in
            self?.errorMessage = message
            self?.showError = true
        }
        
        sendingHandler.getRoomType = { [weak self] in
            return self?.room?.roomType
        }
        
        sendingHandler.getMembers = { [weak self] in
            return self?.room?.members ?? []
        }
        
        readReceiptHandler.onMessagesMarkedAsRead = { [weak self] messageIds in
            guard let self = self else { return }
            for i in 0 ..< self.messages.count {
                if messageIds.contains(self.messages[i].id) && !self.messages[i].isRead {
                    self.messages[i] = self.messages[i].withReadStatus(true)
                }
            }
        }
        
        readReceiptHandler.onReadReceiptFailed = { [weak self] originalStatus in
            guard let self = self else { return }
            for (id, wasRead) in originalStatus {
                if let index = self.messages.firstIndex(where: { $0.id == id }) {
                    self.messages[index] = self.messages[index].withReadStatus(wasRead)
                }
            }
        }
        
        // WebSocket 핸들러 콜백
        webSocketHandler.onNewMessage = { [weak self] message in
            Task { @MainActor in
                await self?.handleNewMessage(message)
            }
        }
        
        webSocketHandler.onTypingIndicator = { [weak self] user, isTyping in
            guard let self = self else { return }
            if isTyping {
                if !self.typingUsers.contains(where: { $0.id == user.id }) {
                    self.typingUsers.append(user)
                }
            } else {
                self.typingUsers.removeAll { $0.id == user.id }
            }
        }
        
        webSocketHandler.onReadReceipt = { [weak self] _, messageIds in
            guard let self = self,
                  let currentUserId = CurrentUser.shared.id else { return }
            
            var hasUpdate = false
            for (index, message) in self.messages.enumerated() {
                if messageIds.contains(message.id),
                   let sender = message.sender,
                   sender.id == currentUserId && !message.isRead
                {
                    self.messages[index] = message.withReadStatus(true)
                    hasUpdate = true
                }
            }
            
            if hasUpdate {
                self.objectWillChange.send()
            }
        }
        
        webSocketHandler.onMessageUpdate = { [weak self] updatedMessage in
            Task { @MainActor in
                await self?.handleMessageUpdate(updatedMessage)
            }
        }
        
        webSocketHandler.onMessageDelete = { [weak self] messageId in
            Task { @MainActor in
                await self?.handleMessageDelete(messageId)
            }
        }
        
        webSocketHandler.onUserStatusChange = { [weak self] userId, status in
            guard let self = self else { return }
            if status == "online" {
                self.onlineUsers.insert(userId)
            } else {
                self.onlineUsers.remove(userId)
            }
        }
        
        webSocketHandler.onReconnected = { [weak self] in
            await self?.loadMessages(page: 1, useCache: false)
        }
    }
    
    func loadRoom() async {
        isLoading = true
        errorMessage = nil
        isDisconnected = false
        
        webSocketHandler.setupSubscriptions()
        
        do {
            room = try await apiService.fetchChatRoomDetail(roomId: roomId)
            
            if room?.roomType == .direct {
                Task {
                    await preloadRecipientPublicKey()
                }
            }
            
            await loadMessages(page: 1, useCache: true)
            
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000)
                await loadMessages(page: 1, useCache: false)
            }
            
            webSocketHandler.connect()
            
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        
        isLoading = false
    }
    
    func loadMessages(page: Int = 1, useCache: Bool = true) async {
        if page == 1 {
            if useCache && !messages.isEmpty {
                isLoading = false
            } else {
                isLoading = true
            }
        } else {
            isLoadingMore = true
        }
        
        do {
            let response = try await apiService.fetchMessages(roomId: roomId, page: page, pageSize: 50, useCache: useCache)
            
            if page == 1 {
                messages = response.results
            } else {
                messages.insert(contentsOf: response.results, at: 0)
            }
            
            sortMessages()
            
            currentPage = page
            hasMoreMessages = response.hasNext
            
            isLoading = false
            isLoadingMore = false
            
            if let room = room, room.roomType == .direct {
                if page == 1 {
                    isDecrypting = true
                    await encryptionHandler.decryptMessages(messages, isDirectChat: true)
                    isDecrypting = false
                    objectWillChange.send()
                } else {
                    Task {
                        await encryptionHandler.preloadDecryption(messages: response.results)
                    }
                }
            }
            
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            isLoading = false
            isLoadingMore = false
        }
    }
    
    func loadMoreMessages() async {
        guard hasMoreMessages, !isLoadingMore else { return }
        await loadMessages(page: currentPage + 1, useCache: false)
    }
    
    func sendMessage(content: String, replyTo: String? = nil) async {
        guard !isSending else { return }
        
        isSending = true
        let success = await sendingHandler.sendMessage(content: content, replyTo: replyTo)
        isSending = false
        
        if success {
            if let lastMessage = messages.last, lastMessage.id.hasPrefix("temp_") {
                cacheManager.saveSentMessageContent(messageId: lastMessage.id, content: content)
            }
            
            Task {
                await apiService.invalidateMessageCache(for: roomId)
            }
        }
    }
    
    func sendTypingIndicator(isTyping: Bool) {
        sendingHandler.sendTypingIndicator(isTyping: isTyping)
        
        if isTyping {
            typingTimer?.invalidate()
            typingTimer = Timer.scheduledTimer(withTimeInterval: Constants.typingAutoStopInterval, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.sendTypingIndicator(isTyping: false)
                }
            }
        }
    }
    
    func onMessageAppear(_ message: Message) {
        readReceiptHandler.onMessageAppear(message)
    }
    
    func markMessagesAsRead(messageIds: [String]) async {
        await readReceiptHandler.markMessagesAsRead(messageIds: messageIds)
    }
    
    func leaveRoom() async -> Bool {
        do {
            try await apiService.leaveChatRoom(roomId: roomId)
            disconnect()
            
            return true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            
            return false
        }
    }
    
    func disconnect() {
        guard !isDisconnected else { return }
        isDisconnected = true
        
        Task {
            await readReceiptHandler.flushPendingReadReceipts()
        }
        
        typingTimer?.invalidate()
        typingTimer = nil
        
        webSocketHandler.disconnect()
        readReceiptHandler.cleanup()
    }
    
    func deleteMessage(_ message: Message) {
        let messageId = message.id
        
        guard !deletingMessageIds.contains(messageId) else {
            return
        }
        
        deletingMessageIds.insert(messageId)
        
        let originalMessage = messages.first { $0.id == messageId }
        let originalIndex = messages.firstIndex { $0.id == messageId }
        
        withAnimation {
            messages.removeAll { $0.id == messageId }
        }
        
        Task {
            await encryptionHandler.removeDecryptedMessage(messageId: messageId)
        }
        
        Task {
            do {
                try await apiService.deleteMessage(roomId: roomId, messageId: messageId)
                await apiService.invalidateMessageCache(for: roomId)
                deletingMessageIds.remove(messageId)
            } catch {
                deletingMessageIds.remove(messageId)
                
                await MainActor.run {
                    if let originalMessage = originalMessage {
                        withAnimation {
                            if let index = originalIndex, index < messages.count {
                                messages.insert(originalMessage, at: index)
                            } else {
                                messages.append(originalMessage)
                            }
                            sortMessages()
                        }
                    }
                    errorMessage = "메시지 삭제에 실패했습니다."
                    showError = true
                }
            }
        }
    }
    
    func editMessage(_ message: Message, newContent: String) {
        let messageId = message.id
        
        Task {
            do {
                var updatedContent: String?
                var updatedEncryptedContent: String?
                var updatedEncryptedSessionKey: String?
                var updatedSelfEncryptedSessionKey: String?
                
                if room?.roomType == .direct {
                    guard let currentUserId = CurrentUser.shared.id else {
                        throw NSError(domain: "Whisper", code: -1, userInfo: [NSLocalizedDescriptionKey: "사용자 정보를 찾을 수 없습니다."])
                    }
                    
                    guard let otherMember = room?.members.first(where: { $0.user.id != currentUserId }) else {
                        throw NSError(domain: "Whisper", code: -1, userInfo: [NSLocalizedDescriptionKey: "상대방 정보를 찾을 수 없습니다."])
                    }
                    
                    let recipientPublicKeyPEM = try await encryptionHandler.fetchUserPublicKey(userId: otherMember.user.id)
                    
                    var selfPublicKeyPEM: String? = nil
                    do {
                        selfPublicKeyPEM = try await encryptionHandler.fetchUserPublicKey(userId: currentUserId)
                    } catch {}
                    
                    let encryptionResult = try await encryptionHandler.encryptMessage(
                        newContent,
                        recipientPublicKeyPEM: recipientPublicKeyPEM,
                        selfPublicKeyPEM: selfPublicKeyPEM
                    )
                    
                    updatedEncryptedContent = encryptionResult.encryptedContent
                    updatedEncryptedSessionKey = encryptionResult.encryptedSessionKey
                    updatedSelfEncryptedSessionKey = encryptionResult.selfEncryptedSessionKey
                    
                } else {
                    updatedContent = newContent
                }
                
                let updatedMessage = try await apiService.updateMessage(
                    roomId: roomId,
                    messageId: messageId,
                    content: updatedContent,
                    encryptedContent: updatedEncryptedContent,
                    encryptedSessionKey: updatedEncryptedSessionKey,
                    selfEncryptedSessionKey: updatedSelfEncryptedSessionKey
                )
                
                await MainActor.run {
                    if let index = messages.firstIndex(where: { $0.id == messageId }) {
                        messages[index] = updatedMessage
                        if room?.roomType == .direct {
                            encryptionHandler.saveDecryptedMessage(messageId: messageId, content: newContent)
                            cacheManager.saveSentMessageContent(messageId: messageId, content: newContent)
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "메시지 수정에 실패했습니다: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }
    
    func sendImage(_ image: UIImage) async {
        let success = await sendingHandler.sendImage(image)
        if success {
            Task {
                await apiService.invalidateMessageCache(for: roomId)
            }
        }
    }
    
    func sendFile(url: URL) async {
        let success = await sendingHandler.sendFile(url: url)
        if success {
            Task {
                await apiService.invalidateMessageCache(for: roomId)
            }
        }
    }
    
    func getDisplayContent(for message: Message) -> String {
        if let decrypted = encryptionHandler.getDecryptedContent(for: message.id) {
            return decrypted
        }
        
        if let encryptedContent = message.encryptedContent {
            if message.isFromCurrentUser {
                if let originalContent = encryptionHandler.getSentMessageContent(for: encryptedContent) {
                    encryptionHandler.saveDecryptedMessage(messageId: message.id, content: originalContent)
                    cacheManager.saveSentMessageContent(messageId: message.id, content: originalContent)
                    encryptionHandler.removeSentMessageContent(for: encryptedContent)
                    return originalContent
                }
                
                if let savedContent = cacheManager.loadSentMessageContent(messageId: message.id) {
                    encryptionHandler.saveDecryptedMessage(messageId: message.id, content: savedContent)
                    return savedContent
                }
            }
            
            if !encryptionHandler.isDecrypting(messageId: message.id) {
                encryptionHandler.markDecrypting(messageId: message.id)
                
                Task {
                    if message.isFromCurrentUser {
                        if let selfEncryptedSessionKey = message.selfEncryptedSessionKey {
                            await encryptionHandler.decryptMessage(
                                messageId: message.id,
                                encryptedContent: encryptedContent,
                                encryptedSessionKey: selfEncryptedSessionKey,
                                isSelfKey: true
                            )
                        }
                    } else {
                        await encryptionHandler.decryptMessage(
                            messageId: message.id,
                            encryptedContent: encryptedContent,
                            encryptedSessionKey: message.encryptedSessionKey,
                            isSelfKey: false
                        )
                    }
                }
            }
            
            return "[암호화된 메시지]"
        }
        
        return message.displayContent
    }
    
    func getReplyToDisplayContent(for replyTo: ReplyToMessage) -> String {
        if let originalMessage = messages.first(where: { $0.id == replyTo.id }) {
            return getDisplayContent(for: originalMessage)
        }
        
        if let decrypted = encryptionHandler.getDecryptedContent(for: replyTo.id) {
            return decrypted
        }
        
        if let encryptedContent = replyTo.encryptedContent {
            if !encryptionHandler.isDecrypting(messageId: replyTo.id) {
                encryptionHandler.markDecrypting(messageId: replyTo.id)
                
                Task {
                    if replyTo.isFromCurrentUser {
                        if let selfEncryptedSessionKey = replyTo.selfEncryptedSessionKey {
                            await encryptionHandler.decryptMessage(
                                messageId: replyTo.id,
                                encryptedContent: encryptedContent,
                                encryptedSessionKey: selfEncryptedSessionKey,
                                isSelfKey: true
                            )
                        }
                    } else {
                        if let encryptedSessionKey = replyTo.encryptedSessionKey {
                            await encryptionHandler.decryptMessage(
                                messageId: replyTo.id,
                                encryptedContent: encryptedContent,
                                encryptedSessionKey: encryptedSessionKey,
                                isSelfKey: false
                            )
                        }
                    }
                }
            }
            return "[암호화된 메시지]"
        }
        
        return replyTo.displayContent
    }
    
    func retryDecryption() async {
        isDecrypting = true
        await encryptionHandler.retryDecryption(messages: messages, isDirectChat: room?.roomType == .direct)
        isDecrypting = false
        objectWillChange.send()
    }
    
    private func preloadRecipientPublicKey() async {
        guard let currentUserId = CurrentUser.shared.id,
              let members = room?.members else { return }
        
        await encryptionHandler.preloadRecipientPublicKey(currentUserId: currentUserId, members: members)
    }
    
    private func handleNewMessage(_ message: Message) async {
        guard !isDisconnected else { return }
        
        if message.isFromCurrentUser {
            let tempMessages = messages.enumerated()
                .filter { $0.element.id.hasPrefix("temp_") }
                .map { (index: $0.offset, message: $0.element) }
            
            if let match = ChatWebSocketHandler.matchTempMessage(newMessage: message, tempMessages: tempMessages) {
                let tempMessageId = match.tempId
                
                if let decryptedContent = encryptionHandler.getDecryptedContent(for: tempMessageId) {
                    encryptionHandler.saveDecryptedMessage(messageId: message.id, content: decryptedContent)
                    cacheManager.saveSentMessageContent(messageId: message.id, content: decryptedContent)
                    
                    Task {
                        await encryptionHandler.removeDecryptedMessage(messageId: tempMessageId)
                    }
                }
                
                messages.remove(at: match.index)
                sendingHandler.updateSendStatus(tempId: tempMessageId, realId: message.id, status: .sent)
            }
        }
        
        guard !messages.contains(where: { $0.id == message.id }) else { return }
        
        if room?.roomType == .direct, let encryptedContent = message.encryptedContent {
            if encryptionHandler.getDecryptedContent(for: message.id) == nil {
                if message.isFromCurrentUser {
                    if let selfEncryptedSessionKey = message.selfEncryptedSessionKey {
                        await encryptionHandler.decryptMessage(
                            messageId: message.id,
                            encryptedContent: encryptedContent,
                            encryptedSessionKey: selfEncryptedSessionKey,
                            isSelfKey: true
                        )
                    } else if let originalContent = encryptionHandler.getSentMessageContent(for: encryptedContent) {
                        encryptionHandler.saveDecryptedMessage(messageId: message.id, content: originalContent)
                        cacheManager.saveSentMessageContent(messageId: message.id, content: originalContent)
                        encryptionHandler.removeSentMessageContent(for: encryptedContent)
                    } else if let savedContent = cacheManager.loadSentMessageContent(messageId: message.id) {
                        encryptionHandler.saveDecryptedMessage(messageId: message.id, content: savedContent)
                    }
                } else {
                    await encryptionHandler.decryptMessage(
                        messageId: message.id,
                        encryptedContent: encryptedContent,
                        encryptedSessionKey: message.encryptedSessionKey,
                        isSelfKey: false
                    )
                }
            }
        }
        
        messages.append(message)
        sortMessages()
        
        if !message.isFromCurrentUser {
            await readReceiptHandler.markMessagesAsRead(messageIds: [message.id])
        }
    }
    
    private func handleMessageUpdate(_ updatedMessage: Message) async {
        guard let index = messages.firstIndex(where: { $0.id == updatedMessage.id }) else { return }
        
        let oldMessage = messages[index]
        let isContentChanged = oldMessage.encryptedContent != updatedMessage.encryptedContent
        
        messages[index] = updatedMessage
        
        let shouldDecrypt = (room?.roomType == .direct) || (updatedMessage.encryptedContent != nil)
        
        if shouldDecrypt, let encryptedContent = updatedMessage.encryptedContent {
            if isContentChanged || encryptionHandler.getDecryptedContent(for: updatedMessage.id) == nil {
                if updatedMessage.isFromCurrentUser {
                    if let originalContent = encryptionHandler.getSentMessageContent(for: encryptedContent) {
                        encryptionHandler.saveDecryptedMessage(messageId: updatedMessage.id, content: originalContent)
                        cacheManager.saveSentMessageContent(messageId: updatedMessage.id, content: originalContent)
                        encryptionHandler.removeSentMessageContent(for: encryptedContent)
                    } else if let selfEncryptedSessionKey = updatedMessage.selfEncryptedSessionKey {
                        await encryptionHandler.decryptMessage(
                            messageId: updatedMessage.id,
                            encryptedContent: encryptedContent,
                            encryptedSessionKey: selfEncryptedSessionKey,
                            isSelfKey: true,
                            force: true
                        )
                    }
                } else {
                    if let encryptedSessionKey = updatedMessage.encryptedSessionKey {
                        await encryptionHandler.decryptMessage(
                            messageId: updatedMessage.id,
                            encryptedContent: encryptedContent,
                            encryptedSessionKey: encryptedSessionKey,
                            isSelfKey: false,
                            force: true
                        )
                    }
                }
            }
        } else {
            objectWillChange.send()
        }
    }
    
    private func handleMessageDelete(_ messageId: String) async {
        if deletingMessageIds.contains(messageId) { return }
        
        withAnimation {
            messages.removeAll { $0.id == messageId }
        }
        
        await encryptionHandler.removeDecryptedMessage(messageId: messageId)
    }
    
    private func sortMessages() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        messages.sort { m1, m2 in
            guard let date1 = formatter.date(from: m1.createdAt),
                  let date2 = formatter.date(from: m2.createdAt)
            else {
                return m1.createdAt < m2.createdAt
            }
            return date1 < date2
        }
    }
}
