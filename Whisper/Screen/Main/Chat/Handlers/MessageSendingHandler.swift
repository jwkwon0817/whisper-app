//
//  MessageSendingHandler.swift
//  Whisper
//
//  Created by Refactoring on 11/28/25.
//

import SwiftUI

/// 메시지 전송을 담당하는 핸들러
@MainActor
final class MessageSendingHandler {
    
    // MARK: - Dependencies
    
    private let roomId: String
    private let wsManager: ChatWebSocketManager
    private let fileUploadService: FileUploadService
    private let encryptionHandler: MessageEncryptionHandler
    
    // MARK: - State
    
    private(set) var isSending = false
    private(set) var messageSendStatus: [String: MessageSendStatus] = [:]
    
    enum MessageSendStatus {
        case sending
        case sent
        case failed(Error)
    }
    
    // MARK: - Callbacks
    
    var onMessageCreated: ((Message) -> Void)?
    var onMessageSent: ((String, String) -> Void)? // (tempId, realId)
    var onError: ((String) -> Void)?
    var getRoomType: (() -> ChatRoom.RoomType?)?
    var getMembers: (() -> [ChatRoomMember])?
    
    // MARK: - Init
    
    init(
        roomId: String,
        wsManager: ChatWebSocketManager = .shared,
        fileUploadService: FileUploadService = NetworkManager.shared.fileUploadService,
        encryptionHandler: MessageEncryptionHandler
    ) {
        self.roomId = roomId
        self.wsManager = wsManager
        self.fileUploadService = fileUploadService
        self.encryptionHandler = encryptionHandler
    }
    
    // MARK: - Public Methods
    
    /// 텍스트 메시지 전송
    func sendMessage(content: String, replyTo: String? = nil) async -> Bool {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard !isSending else { return false }
        
        isSending = true
        defer { isSending = false }
        
        let outgoingMessage: WebSocketOutgoingMessage
        let tempMessageId = generateTempMessageId()
        
        let isDirectChat = getRoomType?() == .direct
        
        if isDirectChat {
            // 현재 사용자 정보 확인
            if CurrentUser.shared.id == nil {
                do {
                    let user = try await NetworkManager.shared.userService.fetchMe()
                    CurrentUser.shared.update(user: user)
                } catch {
                    onError?("사용자 정보를 가져올 수 없습니다.")
                    return false
                }
            }
            
            guard let currentUserId = CurrentUser.shared.id else {
                onError?("사용자 정보를 가져올 수 없습니다.")
                return false
            }
            
            guard let members = getMembers?(),
                  let otherMember = members.first(where: { $0.user.id != currentUserId }) else {
                onError?("상대방 정보를 찾을 수 없습니다.")
                return false
            }
            
            // 공개키 가져오기
            let publicKeyPEM: String
            do {
                publicKeyPEM = try await encryptionHandler.fetchUserPublicKey(userId: otherMember.user.id)
            } catch {
                onError?("상대방의 공개키를 가져올 수 없습니다: \(error.localizedDescription)")
                return false
            }
            
            // 내 공개키 가져오기
            var selfPublicKeyPEM: String? = nil
            do {
                selfPublicKeyPEM = try await encryptionHandler.fetchUserPublicKey(userId: currentUserId)
            } catch {
                // 실패해도 계속 진행
            }
            
            // 암호화
            do {
                let encryptionResult = try await encryptionHandler.encryptMessage(
                    content,
                    recipientPublicKeyPEM: publicKeyPEM,
                    selfPublicKeyPEM: selfPublicKeyPEM
                )
                
                outgoingMessage = WebSocketOutgoingMessage(
                    type: "chat_message",
                    messageType: "text",
                    content: nil,
                    encryptedContent: encryptionResult.encryptedContent,
                    encryptedSessionKey: encryptionResult.encryptedSessionKey,
                    selfEncryptedSessionKey: encryptionResult.selfEncryptedSessionKey,
                    replyTo: replyTo,
                    assetId: nil,
                    isTyping: nil,
                    messageIds: nil
                )
                
                // 원본 내용 저장
                encryptionHandler.storeSentMessageContent(
                    encryptedContent: encryptionResult.encryptedContent,
                    originalContent: content
                )
                
                // 임시 메시지 생성
                let tempMessage = createTempMessage(
                    id: tempMessageId,
                    messageType: Message.MessageType.text,
                    content: nil,
                    encryptedContent: encryptionResult.encryptedContent,
                    encryptedSessionKey: encryptionResult.encryptedSessionKey,
                    selfEncryptedSessionKey: encryptionResult.selfEncryptedSessionKey,
                    replyTo: replyTo
                )
                
                if let tempMessage = tempMessage {
                    messageSendStatus[tempMessageId] = .sending
                    encryptionHandler.saveDecryptedMessage(messageId: tempMessageId, content: content)
                    onMessageCreated?(tempMessage)
                }
                
            } catch {
                onError?("메시지 암호화에 실패했습니다: \(error.localizedDescription)")
                return false
            }
        } else {
            // 그룹 채팅 (평문)
            let tempMessage = createTempMessage(
                id: tempMessageId,
                messageType: Message.MessageType.text,
                content: content,
                replyTo: replyTo
            )
            
            if let tempMessage = tempMessage {
                messageSendStatus[tempMessageId] = .sending
                onMessageCreated?(tempMessage)
            }
            
            outgoingMessage = WebSocketOutgoingMessage(
                type: "chat_message",
                messageType: "text",
                content: content,
                encryptedContent: nil,
                encryptedSessionKey: nil,
                selfEncryptedSessionKey: nil,
                replyTo: replyTo,
                assetId: nil,
                isTyping: nil,
                messageIds: nil
            )
        }
        
        // WebSocket 연결 확인
        guard wsManager.isConnected else {
            onError?("WebSocket 연결이 끊어져 메시지를 전송할 수 없습니다.")
            return false
        }
        
        guard wsManager.currentRoomId == roomId else {
            onError?("다른 채팅방에 연결되어 있어 메시지를 전송할 수 없습니다.")
            return false
        }
        
        wsManager.sendMessage(outgoingMessage)
        return true
    }
    
    /// 이미지 전송
    func sendImage(_ image: UIImage) async -> Bool {
        #if DEBUG
        print("📸 [MessageSendingHandler] 이미지 전송 시작")
        #endif
        
        let tempMessageId = generateTempMessageId()
        
        do {
            // 1. 이미지 업로드
            let asset = try await fileUploadService.uploadImage(image, folder: "chat")
            
            #if DEBUG
            print("✅ [MessageSendingHandler] 이미지 업로드 성공 - Asset ID: \(asset.id)")
            #endif
            
            // 2. 임시 메시지 생성
            let tempMessage = createTempMessage(
                id: tempMessageId,
                messageType: Message.MessageType.image,
                asset: asset
            )
            
            if let tempMessage = tempMessage {
                messageSendStatus[tempMessageId] = .sending
                onMessageCreated?(tempMessage)
            }
            
            // 3. WebSocket으로 전송
            let outgoingMessage = WebSocketOutgoingMessage(
                type: "chat_message",
                messageType: "image",
                content: nil,
                encryptedContent: nil,
                encryptedSessionKey: nil,
                selfEncryptedSessionKey: nil,
                replyTo: nil,
                assetId: asset.id,
                isTyping: nil,
                messageIds: nil
            )
            
            guard wsManager.isConnected else {
                onError?("WebSocket 연결이 끊어져 이미지를 전송할 수 없습니다.")
                messageSendStatus.removeValue(forKey: tempMessageId)
                return false
            }
            
            wsManager.sendMessage(outgoingMessage)
            
            #if DEBUG
            print("✅ [MessageSendingHandler] 이미지 메시지 전송 완료")
            #endif
            
            return true
            
        } catch {
            #if DEBUG
            print("❌ [MessageSendingHandler] 이미지 전송 실패: \(error)")
            #endif
            
            messageSendStatus.removeValue(forKey: tempMessageId)
            onError?("이미지 전송에 실패했습니다: \(error.localizedDescription)")
            return false
        }
    }
    
    /// 파일 전송
    func sendFile(url: URL) async -> Bool {
        #if DEBUG
        print("📎 [MessageSendingHandler] 파일 전송 시작")
        #endif
        
        let tempMessageId = generateTempMessageId()
        
        do {
            let fileData = try Data(contentsOf: url)
            let fileName = url.lastPathComponent
            let contentType = url.mimeType ?? "application/octet-stream"
            
            #if DEBUG
            print("📄 [MessageSendingHandler] 파일 정보 - 이름: \(fileName), 크기: \(fileData.count) bytes")
            #endif
            
            let asset = try await fileUploadService.uploadFile(
                data: fileData,
                fileName: fileName,
                contentType: contentType,
                folder: "chat"
            )
            
            #if DEBUG
            print("✅ [MessageSendingHandler] 파일 업로드 성공 - Asset ID: \(asset.id)")
            #endif
            
            let tempMessage = createTempMessage(
                id: tempMessageId,
                messageType: Message.MessageType.file,
                asset: asset
            )
            
            if let tempMessage = tempMessage {
                messageSendStatus[tempMessageId] = .sending
                onMessageCreated?(tempMessage)
            }
            
            let outgoingMessage = WebSocketOutgoingMessage(
                type: "chat_message",
                messageType: "file",
                content: nil,
                encryptedContent: nil,
                encryptedSessionKey: nil,
                selfEncryptedSessionKey: nil,
                replyTo: nil,
                assetId: asset.id,
                isTyping: nil,
                messageIds: nil
            )
            
            guard wsManager.isConnected else {
                onError?("WebSocket 연결이 끊어져 파일을 전송할 수 없습니다.")
                messageSendStatus.removeValue(forKey: tempMessageId)
                return false
            }
            
            wsManager.sendMessage(outgoingMessage)
            
            #if DEBUG
            print("✅ [MessageSendingHandler] 파일 메시지 전송 완료")
            #endif
            
            return true
            
        } catch {
            #if DEBUG
            print("❌ [MessageSendingHandler] 파일 전송 실패: \(error)")
            #endif
            
            messageSendStatus.removeValue(forKey: tempMessageId)
            onError?("파일 전송에 실패했습니다: \(error.localizedDescription)")
            return false
        }
    }
    
    /// 타이핑 인디케이터 전송
    func sendTypingIndicator(isTyping: Bool) {
        let message = WebSocketOutgoingMessage(
            type: "typing",
            messageType: nil,
            content: nil,
            encryptedContent: nil,
            encryptedSessionKey: nil,
            selfEncryptedSessionKey: nil,
            replyTo: nil,
            assetId: nil,
            isTyping: isTyping,
            messageIds: nil
        )
        wsManager.sendMessage(message)
    }
    
    /// 메시지 전송 상태 업데이트
    func updateSendStatus(tempId: String, realId: String, status: MessageSendStatus) {
        messageSendStatus[realId] = status
        messageSendStatus.removeValue(forKey: tempId)
    }
    
    /// 임시 메시지 ID로 상태 가져오기
    func getSendStatus(for messageId: String) -> MessageSendStatus? {
        return messageSendStatus[messageId]
    }
    
    /// 메시지 전송 상태 제거
    func removeSendStatus(for messageId: String) {
        messageSendStatus.removeValue(forKey: messageId)
    }
    
    // MARK: - Private Methods
    
    private func generateTempMessageId() -> String {
        return "temp_\(Date().timeIntervalSince1970)_\(UUID().uuidString.prefix(8))"
    }
    
    private func createTempMessage(
        id: String,
        messageType: Message.MessageType,
        content: String? = nil,
        encryptedContent: String? = nil,
        encryptedSessionKey: String? = nil,
        selfEncryptedSessionKey: String? = nil,
        asset: Asset? = nil,
        replyTo: String? = nil
    ) -> Message? {
        guard let currentUserId = CurrentUser.shared.id,
              let currentUserName = CurrentUser.shared.name else {
            return nil
        }
        
        let currentUser = User(
            id: currentUserId,
            name: currentUserName,
            profileImage: CurrentUser.shared.profileImage,
            maskedPhoneNumber: nil,
            createdAt: nil
        )
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = dateFormatter.string(from: Date())
        
        var replyToMessage: ReplyToMessage? = nil
        if let replyToId = replyTo {
            replyToMessage = ReplyToMessage(
                id: replyToId,
                sender: currentUser,
                content: "",
                messageType: Message.MessageType.text
            )
        }
        
        return Message(
            id: id,
            room: roomId,
            sender: currentUser,
            messageType: messageType,
            content: content,
            encryptedContent: encryptedContent,
            encryptedSessionKey: encryptedSessionKey,
            selfEncryptedSessionKey: selfEncryptedSessionKey,
            asset: asset,
            replyTo: replyToMessage,
            isRead: false,
            createdAt: now,
            updatedAt: now
        )
    }
}

