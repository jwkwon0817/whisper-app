//
//  MessageEncryptionHandler.swift
//  Whisper
//
//  Created by Refactoring on 11/28/25.
//

import Foundation

@MainActor
final class MessageEncryptionHandler {
    private let cryptoManager: E2EECryptoManager
    private let decryptedCache: DecryptedMessageCache
    private let userService: UserService
    
    private(set) var decryptedMessages: [String: String] = [:]
    private(set) var publicKeyCache: [String: String] = [:]
    private(set) var decryptingMessageIds: Set<String> = []
    private(set) var sentMessageContents: [String: String] = [:]
    
    private let roomId: String
    
    var onDecryptionComplete: ((String, String) -> Void)?
    var onError: ((String) -> Void)?
    
    init(
        roomId: String,
        cryptoManager: E2EECryptoManager = .shared,
        decryptedCache: DecryptedMessageCache = .shared,
        userService: UserService = NetworkManager.shared.userService
    ) {
        self.roomId = roomId
        self.cryptoManager = cryptoManager
        self.decryptedCache = decryptedCache
        self.userService = userService
    }
    
    func loadCachedDecryptedMessages() async {
        let cached = await decryptedCache.getAll(roomId: roomId)
        if !cached.isEmpty {
            decryptedMessages = cached
        }
    }
    
    func saveDecryptedMessage(messageId: String, content: String) {
        decryptedMessages[messageId] = content
        
        Task {
            await decryptedCache.save(roomId: roomId, messageId: messageId, decryptedContent: content)
        }
    }
    
    func removeDecryptedMessage(messageId: String) async {
        decryptedMessages.removeValue(forKey: messageId)
        decryptingMessageIds.remove(messageId)
        await decryptedCache.remove(roomId: roomId, messageId: messageId)
    }
    
    func storeSentMessageContent(encryptedContent: String, originalContent: String) {
        sentMessageContents[encryptedContent] = originalContent
    }
    
    func getSentMessageContent(for encryptedContent: String) -> String? {
        return sentMessageContents[encryptedContent]
    }
    
    func removeSentMessageContent(for encryptedContent: String) {
        sentMessageContents.removeValue(forKey: encryptedContent)
    }
    
    func getDecryptedContent(for messageId: String) -> String? {
        return decryptedMessages[messageId]
    }
    
    func fetchUserPublicKey(userId: String) async throws -> String {
        if let cachedKey = publicKeyCache[userId] {
            return cachedKey
        }
        
        let publicKey = try await userService.getUserPublicKey(userId: userId)
        publicKeyCache[userId] = publicKey
        
        return publicKey
    }
    
    func preloadRecipientPublicKey(currentUserId: String, members: [ChatRoomMember]) async {
        guard let otherMember = members.first(where: { $0.user.id != currentUserId }) else {
            return
        }
        
        if publicKeyCache[otherMember.user.id] != nil {
            return
        }
        
        do {
            let publicKey = try await fetchUserPublicKey(userId: otherMember.user.id)
            publicKeyCache[otherMember.user.id] = publicKey
        } catch {
        }
    }
    
    func encryptMessage(
        _ content: String,
        recipientPublicKeyPEM: String,
        selfPublicKeyPEM: String?
    ) async throws -> E2EECryptoManager.HybridEncryptionResult {
        return try await cryptoManager.encryptMessageHybrid(
            content,
            recipientPublicKeyPEM: recipientPublicKeyPEM,
            selfPublicKeyPEM: selfPublicKeyPEM
        )
    }
    
    func decryptMessage(
        messageId: String,
        encryptedContent: String,
        encryptedSessionKey: String?,
        isSelfKey: Bool = false,
        force: Bool = false
    ) async {
        if !force {
        guard !decryptingMessageIds.contains(messageId) else { return }
        }
        decryptingMessageIds.insert(messageId)
        
        guard let password = KeychainHelper.getItem(forAccount: "user_password") else {
            decryptingMessageIds.remove(messageId)
            onError?("보안 비밀번호를 찾을 수 없습니다. 다시 로그인해주세요.")
            return
        }
        
        let cryptoManager = self.cryptoManager
        
        let result: String? = await Task.detached(priority: .userInitiated) {
            do {
                let decryptedContent: String
                
                if isSelfKey, let key = encryptedSessionKey {
                    decryptedContent = try await cryptoManager.decryptMessageHybridWithSelfKey(
                        encryptedContent,
                        selfEncryptedSessionKey: key,
                        password: password
                    )
                } else {
                    decryptedContent = try await cryptoManager.decryptMessage(
                        encryptedContent,
                        encryptedSessionKey: encryptedSessionKey,
                        password: password
                    )
                }
                
                return decryptedContent
            } catch {
                return nil
            }
        }.value
        
        decryptingMessageIds.remove(messageId)
        
        if let decryptedContent = result {
            saveDecryptedMessage(messageId: messageId, content: decryptedContent)
            onDecryptionComplete?(messageId, decryptedContent)
        }
    }
    
    func decryptMessages(_ messages: [Message], isDirectChat: Bool) async {
        guard isDirectChat || messages.contains(where: { $0.encryptedContent != nil }) else {
            return
        }
        
        for message in messages {
            if let encryptedContent = message.encryptedContent {
                if decryptedMessages[message.id] == nil && !decryptingMessageIds.contains(message.id) {
                    if message.isFromCurrentUser {
                        if let selfEncryptedSessionKey = message.selfEncryptedSessionKey {
                            await decryptMessage(
                                messageId: message.id,
                                encryptedContent: encryptedContent,
                                encryptedSessionKey: selfEncryptedSessionKey,
                                isSelfKey: true
                            )
                        } else if let originalContent = sentMessageContents[encryptedContent] {
                            saveDecryptedMessage(messageId: message.id, content: originalContent)
                        }
                    } else {
                        await decryptMessage(
                            messageId: message.id,
                            encryptedContent: encryptedContent,
                            encryptedSessionKey: message.encryptedSessionKey,
                            isSelfKey: false
                        )
                    }
                }
            }
        }
    }
    
    func preloadDecryption(messages: [Message]) async {
        for message in messages {
            if decryptedMessages[message.id] != nil { continue }
            
            if let encryptedContent = message.encryptedContent {
                if message.isFromCurrentUser {
                    if message.selfEncryptedSessionKey == nil {
                        if let originalContent = sentMessageContents[encryptedContent] {
                            saveDecryptedMessage(messageId: message.id, content: originalContent)
                        }
                    }
                }
            }
        }
        
        let messagesToDecrypt = messages.filter { message in
            guard decryptedMessages[message.id] == nil,
                  message.encryptedContent != nil else { return false }
            
            if message.isFromCurrentUser {
                return message.selfEncryptedSessionKey != nil
            } else {
                return true
            }
        }
        
        guard !messagesToDecrypt.isEmpty else {
            return
        }
        
        let batchSize = 5
        let batches = stride(from: 0, to: messagesToDecrypt.count, by: batchSize).map {
            Array(messagesToDecrypt[$0..<min($0 + batchSize, messagesToDecrypt.count)])
        }
        
        for batch in batches {
            await withTaskGroup(of: Void.self) { group in
                for message in batch {
                    group.addTask { [weak self] in
                        guard let self = self,
                              let encryptedContent = message.encryptedContent else { return }
                        
                        if message.isFromCurrentUser {
                            if let selfEncryptedSessionKey = message.selfEncryptedSessionKey {
                                await self.decryptMessage(
                                    messageId: message.id,
                                    encryptedContent: encryptedContent,
                                    encryptedSessionKey: selfEncryptedSessionKey,
                                    isSelfKey: true
                                )
                            }
                        } else {
                            await self.decryptMessage(
                                messageId: message.id,
                                encryptedContent: encryptedContent,
                                encryptedSessionKey: message.encryptedSessionKey,
                                isSelfKey: false
                            )
                        }
                    }
                }
            }
        }
    }
    
    func retryDecryption(messages: [Message], isDirectChat: Bool) async {
        decryptingMessageIds.removeAll()
        await decryptMessages(messages, isDirectChat: isDirectChat)
    }
    
    func isDecrypting(messageId: String) -> Bool {
        return decryptingMessageIds.contains(messageId)
    }
    
    func markDecrypting(messageId: String) {
        decryptingMessageIds.insert(messageId)
    }
    
    func getCachedPublicKey(for userId: String) -> String? {
        return publicKeyCache[userId]
    }
    
    func cachePublicKey(userId: String, publicKey: String) {
        publicKeyCache[userId] = publicKey
    }
}

