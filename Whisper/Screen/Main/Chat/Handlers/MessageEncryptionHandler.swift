//
//  MessageEncryptionHandler.swift
//  Whisper
//
//  Created by Refactoring on 11/28/25.
//

import Foundation

/// 메시지 암호화/복호화를 담당하는 핸들러
@MainActor
final class MessageEncryptionHandler {
    
    // MARK: - Dependencies
    
    private let cryptoManager: E2EECryptoManager
    private let decryptedCache: DecryptedMessageCache
    private let userService: UserService
    
    // MARK: - State
    
    private(set) var decryptedMessages: [String: String] = [:]
    private(set) var publicKeyCache: [String: String] = [:]
    private(set) var decryptingMessageIds: Set<String> = []
    private(set) var sentMessageContents: [String: String] = [:]
    
    private let roomId: String
    
    // MARK: - Callbacks
    
    var onDecryptionComplete: ((String, String) -> Void)?
    var onError: ((String) -> Void)?
    
    // MARK: - Init
    
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
    
    // MARK: - Public Methods
    
    /// 캐시된 복호화 메시지 로드
    func loadCachedDecryptedMessages() async {
        let cached = await decryptedCache.getAll(roomId: roomId)
        if !cached.isEmpty {
            decryptedMessages = cached
            #if DEBUG
            print("📦 [MessageEncryptionHandler] 캐시된 복호화 메시지 로드 완료 - 개수: \(cached.count)")
            #endif
        }
    }
    
    /// 복호화된 메시지 저장
    func saveDecryptedMessage(messageId: String, content: String) {
        decryptedMessages[messageId] = content
        
        Task {
            await decryptedCache.save(roomId: roomId, messageId: messageId, decryptedContent: content)
        }
    }
    
    /// 복호화된 메시지 삭제
    func removeDecryptedMessage(messageId: String) async {
        decryptedMessages.removeValue(forKey: messageId)
        decryptingMessageIds.remove(messageId)
        await decryptedCache.remove(roomId: roomId, messageId: messageId)
    }
    
    /// 전송된 원본 메시지 내용 저장 (임시)
    func storeSentMessageContent(encryptedContent: String, originalContent: String) {
        sentMessageContents[encryptedContent] = originalContent
    }
    
    /// 전송된 원본 메시지 내용 가져오기
    func getSentMessageContent(for encryptedContent: String) -> String? {
        return sentMessageContents[encryptedContent]
    }
    
    /// 전송된 원본 메시지 내용 삭제
    func removeSentMessageContent(for encryptedContent: String) {
        sentMessageContents.removeValue(forKey: encryptedContent)
    }
    
    /// 복호화된 내용 가져오기
    func getDecryptedContent(for messageId: String) -> String? {
        return decryptedMessages[messageId]
    }
    
    /// 사용자 공개키 가져오기
    func fetchUserPublicKey(userId: String) async throws -> String {
        // 캐시에 있으면 반환
        if let cachedKey = publicKeyCache[userId] {
            return cachedKey
        }
        
        let publicKey = try await userService.getUserPublicKey(userId: userId)
        publicKeyCache[userId] = publicKey
        
        #if DEBUG
        print("✅ [MessageEncryptionHandler] 공개키 가져오기 및 캐싱 완료: \(userId)")
        #endif
        
        return publicKey
    }
    
    /// 수신자 공개키 미리 로드
    func preloadRecipientPublicKey(currentUserId: String, members: [ChatRoomMember]) async {
        guard let otherMember = members.first(where: { $0.user.id != currentUserId }) else {
            return
        }
        
        // 이미 캐시에 있으면 스킵
        if publicKeyCache[otherMember.user.id] != nil {
            return
        }
        
        do {
            let publicKey = try await fetchUserPublicKey(userId: otherMember.user.id)
            publicKeyCache[otherMember.user.id] = publicKey
            #if DEBUG
            print("✅ [MessageEncryptionHandler] 수신자 공개키 미리 로드 완료: \(otherMember.user.id)")
            #endif
        } catch {
            #if DEBUG
            print("⚠️ [MessageEncryptionHandler] 수신자 공개키 미리 로드 실패: \(error)")
            #endif
        }
    }
    
    /// 메시지 암호화 (하이브리드)
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
    
    /// 메시지 복호화
    func decryptMessage(
        messageId: String,
        encryptedContent: String,
        encryptedSessionKey: String?,
        isSelfKey: Bool = false
    ) async {
        // 중복 시도 방지
        guard !decryptingMessageIds.contains(messageId) else { return }
        decryptingMessageIds.insert(messageId)
        
        // Keychain에서 비밀번호 가져오기
        guard let password = KeychainHelper.getItem(forAccount: "user_password") else {
            #if DEBUG
            print("⚠️ [MessageEncryptionHandler] 비밀번호를 찾을 수 없어 메시지 복호화 실패")
            #endif
            decryptingMessageIds.remove(messageId)
            onError?("보안 비밀번호를 찾을 수 없습니다. 다시 로그인해주세요.")
            return
        }
        
        // 복호화를 백그라운드 스레드에서 수행
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
                
                #if DEBUG
                if encryptedSessionKey != nil {
                    print("✅ [MessageEncryptionHandler] 하이브리드 복호화 성공: \(messageId) (SelfKey: \(isSelfKey))")
                } else {
                    print("✅ [MessageEncryptionHandler] 기존 RSA-OAEP 복호화 성공: \(messageId)")
                }
                #endif
                
                return decryptedContent
            } catch {
                #if DEBUG
                print("❌ [MessageEncryptionHandler] 메시지 복호화 실패: \(error)")
                #endif
                return nil
            }
        }.value
        
        decryptingMessageIds.remove(messageId)
        
        if let decryptedContent = result {
            saveDecryptedMessage(messageId: messageId, content: decryptedContent)
            onDecryptionComplete?(messageId, decryptedContent)
            
            #if DEBUG
            print("✅ [MessageEncryptionHandler] 메시지 복호화 완료 및 저장: \(messageId)")
            #endif
        }
    }
    
    /// 여러 메시지 복호화 (배치)
    func decryptMessages(_ messages: [Message], isDirectChat: Bool) async {
        guard isDirectChat || messages.contains(where: { $0.encryptedContent != nil }) else {
            return
        }
        
        for message in messages {
            if let encryptedContent = message.encryptedContent {
                // 이미 복호화되었거나 복호화 중인 메시지는 스킵
                if decryptedMessages[message.id] == nil && !decryptingMessageIds.contains(message.id) {
                    #if DEBUG
                    print("🔍 [MessageEncryptionHandler] 메시지 복호화 시도: \(message.id)")
                    #endif
                    
                    if message.isFromCurrentUser {
                        // 내가 보낸 메시지
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
                        // 상대방이 보낸 메시지
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
    
    /// 메시지 프리로드 복호화 (배치, 병렬 처리)
    func preloadDecryption(messages: [Message]) async {
        #if DEBUG
        print("🔄 [MessageEncryptionHandler] 메시지 프리로드 복호화 시작 - 개수: \(messages.count)")
        #endif
        
        // 먼저 로컬 저장소에서 복원 가능한 메시지들 빠르게 처리
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
        
        // 복호화가 필요한 메시지들 필터링
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
            #if DEBUG
            print("✅ [MessageEncryptionHandler] 복호화할 메시지 없음, 완료")
            #endif
            return
        }
        
        // 배치 처리로 병렬 복호화
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
        
        #if DEBUG
        print("✅ [MessageEncryptionHandler] 메시지 프리로드 복호화 완료")
        #endif
    }
    
    /// 복호화 재시도 (수동)
    func retryDecryption(messages: [Message], isDirectChat: Bool) async {
        #if DEBUG
        print("🔄 [MessageEncryptionHandler] 수동 복호화 재시도")
        #endif
        decryptingMessageIds.removeAll()
        await decryptMessages(messages, isDirectChat: isDirectChat)
    }
    
    /// 복호화 중인지 확인
    func isDecrypting(messageId: String) -> Bool {
        return decryptingMessageIds.contains(messageId)
    }
    
    /// 복호화 시작 마킹
    func markDecrypting(messageId: String) {
        decryptingMessageIds.insert(messageId)
    }
    
    /// 캐시된 공개키 가져오기
    func getCachedPublicKey(for userId: String) -> String? {
        return publicKeyCache[userId]
    }
    
    /// 공개키 캐시 저장
    func cachePublicKey(userId: String, publicKey: String) {
        publicKeyCache[userId] = publicKey
    }
}

