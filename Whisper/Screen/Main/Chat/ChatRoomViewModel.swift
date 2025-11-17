//
//  ChatRoomViewModel.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Combine
import SwiftUI

// MARK: - ChatRoom ViewModel

@MainActor
class ChatRoomViewModel: ObservableObject {
    @Published var room: ChatRoom?
    @Published var messages: [Message] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var errorMessage: String?
    @Published var showError = false
    
    @Published var typingUsers: [User] = []
    @Published var onlineUsers: Set<String> = []
    
    private let roomId: String
    private let apiService = NetworkManager.shared.chatService
    private let wsManager = ChatWebSocketManager.shared
    private let cryptoManager = E2EECryptoManager.shared
    private let fileUploadService = NetworkManager.shared.fileUploadService
    
    private var cancellables = Set<AnyCancellable>()
    private var currentPage = 1
    private var hasMoreMessages = true
    private var typingTimer: Timer?
    
    // 복호화된 메시지 내용을 저장하는 딕셔너리
    private var decryptedMessages: [String: String] = [:]
    
    init(roomId: String) {
        self.roomId = roomId
        setupWebSocketSubscriptions()
    }
    
    // MARK: - 초기화

    func loadRoom() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // 채팅방 정보 로드
            room = try await apiService.fetchChatRoomDetail(roomId: roomId)
            
            // 메시지 로드
            await loadMessages()
            
            // WebSocket 연결
            if let accessToken = KeychainHelper.getItem(forAccount: "accessToken") {
                wsManager.connect(roomId: roomId, accessToken: accessToken)
            }
            
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        
        isLoading = false
    }
    
    // MARK: - 메시지 로드

    func loadMessages(page: Int = 1) async {
        if page == 1 {
            isLoading = true
        } else {
            isLoadingMore = true
        }
        
        do {
            let response = try await apiService.fetchMessages(roomId: roomId, page: page, pageSize: 50)
            
            if page == 1 {
                messages = response.results
            } else {
                messages.insert(contentsOf: response.results, at: 0)
            }
            
            currentPage = page
            hasMoreMessages = response.results.count == 50
            
            // 1:1 채팅인 경우 메시지 복호화
            if room?.roomType == .direct {
                await decryptMessages()
            }
            
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        
        isLoading = false
        isLoadingMore = false
    }
    
    // MARK: - 더 많은 메시지 로드

    func loadMoreMessages() async {
        guard hasMoreMessages, !isLoadingMore else { return }
        await loadMessages(page: currentPage + 1)
    }
    
    // MARK: - 메시지 전송

    func sendMessage(content: String, replyTo: String? = nil) async {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let outgoingMessage: WebSocketOutgoingMessage
        
        if room?.roomType == .direct {
            // 1:1 채팅: 암호화 필요
            guard let otherMember = room?.members.first(where: { $0.user.id != CurrentUser.shared.id }),
                  let publicKeyPEM = try? await fetchUserPublicKey(userId: otherMember.user.id)
            else {
                errorMessage = "상대방의 공개키를 가져올 수 없습니다."
                showError = true
                return
            }
            
            do {
                let encryptedContent = try await cryptoManager.encryptMessage(content, recipientPublicKeyPEM: publicKeyPEM)
                outgoingMessage = WebSocketOutgoingMessage(
                    type: "chat_message",
                    messageType: "text",
                    content: nil,
                    encryptedContent: encryptedContent,
                    replyTo: replyTo,
                    assetId: nil,
                    isTyping: nil,
                    messageIds: nil
                )
            } catch {
                errorMessage = "메시지 암호화에 실패했습니다: \(error.localizedDescription)"
                showError = true
                return
            }
        } else {
            // 그룹 채팅: 평문
            outgoingMessage = WebSocketOutgoingMessage(
                type: "chat_message",
                messageType: "text",
                content: content,
                encryptedContent: nil,
                replyTo: replyTo,
                assetId: nil,
                isTyping: nil,
                messageIds: nil
            )
        }
        
        wsManager.sendMessage(outgoingMessage)
    }
    
    // MARK: - 타이핑 인디케이터 전송

    func sendTypingIndicator(isTyping: Bool) {
        let message = WebSocketOutgoingMessage(
            type: "typing",
            messageType: nil,
            content: nil,
            encryptedContent: nil,
            replyTo: nil,
            assetId: nil,
            isTyping: isTyping,
            messageIds: nil
        )
        wsManager.sendMessage(message)
        
        // 3초 후 자동으로 타이핑 중단
        if isTyping {
            typingTimer?.invalidate()
            typingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.sendTypingIndicator(isTyping: false)
                }
            }
        }
    }
    
    // MARK: - 읽음 확인 전송

    func markMessagesAsRead(messageIds: [String]) async {
        do {
            try await apiService.markMessagesAsRead(roomId: roomId, messageIds: messageIds)
            
            // WebSocket으로도 읽음 확인 전송
            let message = WebSocketOutgoingMessage(
                type: "read_receipt",
                messageType: nil,
                content: nil,
                encryptedContent: nil,
                replyTo: nil,
                assetId: nil,
                isTyping: nil,
                messageIds: messageIds
            )
            wsManager.sendMessage(message)
            
        } catch {
            print("Failed to mark messages as read: \(error)")
        }
    }
    
    // MARK: - 채팅방 나가기

    func leaveRoom() async {
        do {
            try await apiService.leaveChatRoom(roomId: roomId)
            wsManager.disconnect()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    // MARK: - WebSocket 구독 설정

    private func setupWebSocketSubscriptions() {
        // 메시지 수신
        wsManager.receivedMessage
            .sink { [weak self] incomingMessage in
                Task { @MainActor in
                    if let message = incomingMessage.message {
                        self?.handleNewMessage(message)
                    }
                }
            }
            .store(in: &cancellables)
        
        // 타이핑 인디케이터
        wsManager.typingIndicator
            .sink { [weak self] user, isTyping in
                Task { @MainActor in
                    guard let self = self else { return }
                    if isTyping {
                        if !self.typingUsers.contains(where: { $0.id == user.id }) {
                            self.typingUsers.append(user)
                        }
                    } else {
                        self.typingUsers.removeAll { $0.id == user.id }
                    }
                }
            }
            .store(in: &cancellables)
        
        // 읽음 확인
        wsManager.readReceipt
            .sink { [weak self] userId, messageIds in
                Task { @MainActor in
                    guard let self = self else { return }
                    // 읽음 상태 업데이트는 서버에서 처리되므로 여기서는 로그만
                    print("User \(userId) read messages: \(messageIds)")
                }
            }
            .store(in: &cancellables)
        
        // 사용자 상태
        wsManager.userStatus
            .sink { [weak self] userId, status in
                Task { @MainActor in
                    guard let self = self else { return }
                    if status == "online" {
                        self.onlineUsers.insert(userId)
                    } else {
                        self.onlineUsers.remove(userId)
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - 새 메시지 처리

    private func handleNewMessage(_ message: Message) {
        // 중복 방지
        if messages.contains(where: { $0.id == message.id }) {
            return
        }
        
        messages.append(message)
        
        // 1:1 채팅인 경우 복호화
        if room?.roomType == .direct,
           let encryptedContent = message.encryptedContent,
           !message.isFromCurrentUser
        {
            Task {
                await decryptMessage(messageId: message.id, encryptedContent: encryptedContent)
            }
        }
        
        // 읽음 확인 전송 (자신이 보낸 메시지가 아닌 경우)
        if !message.isFromCurrentUser {
            Task {
                await markMessagesAsRead(messageIds: [message.id])
            }
        }
    }
    
    // MARK: - 메시지 복호화

    private func decryptMessages() async {
        guard room?.roomType == .direct else { return }
        
        for message in messages {
            if let encryptedContent = message.encryptedContent,
               !message.isFromCurrentUser,
               decryptedMessages[message.id] == nil
            {
                await decryptMessage(messageId: message.id, encryptedContent: encryptedContent)
            }
        }
    }
    
    // MARK: - 개별 메시지 복호화

    private func decryptMessage(messageId: String, encryptedContent: String) async {
        // 비밀번호는 로그인 시에만 사용하고, 복호화는 메모리에서만 수행
        // 실제로는 사용자가 로그인할 때 비밀번호를 입력받아 개인키를 복호화하고,
        // 이후에는 메모리에 개인키를 보관하는 방식이 더 안전함
        // 현재는 E2EEKeyManager가 암호화된 개인키를 Keychain에 저장하고 있으므로,
        // 복호화를 위해서는 사용자 비밀번호가 필요함
        
        // TODO: 비밀번호를 안전하게 관리하는 방법 구현 필요
        // 옵션 1: 로그인 시 비밀번호를 Keychain에 저장 (보안 위험)
        // 옵션 2: 로그인 시 개인키를 복호화하여 메모리에만 보관 (권장)
        // 옵션 3: 사용자에게 비밀번호를 다시 입력받기 (UX 저하)
        
        // 현재는 복호화 기능을 사용하지 않음
        // 실제 구현 시에는 로그인 시 개인키를 복호화하여 메모리에 보관하고,
        // 여기서는 메모리의 개인키를 사용하여 복호화해야 함
    }
    
    // MARK: - 메시지 표시 내용 가져오기

    func getDisplayContent(for message: Message) -> String {
        if let decrypted = decryptedMessages[message.id] {
            return decrypted
        }
        return message.displayContent
    }
    
    // MARK: - 사용자 공개키 가져오기

    private func fetchUserPublicKey(userId: String) async throws -> String {
        return try await NetworkManager.shared.userService.getUserPublicKey(userId: userId)
    }
    
    // MARK: - 이미지 전송

    func sendImage(_ image: UIImage) async {
        do {
            // 이미지 업로드
            let asset = try await fileUploadService.uploadImage(image, folder: "chat")
            
            // WebSocket으로 메시지 전송
            let outgoingMessage = WebSocketOutgoingMessage(
                type: "chat_message",
                messageType: "image",
                content: "이미지를 보냈습니다.",
                encryptedContent: nil,
                replyTo: nil,
                assetId: asset.id,
                isTyping: nil,
                messageIds: nil
            )
            
            wsManager.sendMessage(outgoingMessage)
            
        } catch {
            errorMessage = "이미지 업로드 실패: \(error.localizedDescription)"
            showError = true
        }
    }
    
    // MARK: - 파일 전송

    func sendFile(_ fileData: Data, fileName: String, contentType: String) async {
        do {
            // 파일 업로드
            let asset = try await fileUploadService.uploadFile(
                data: fileData,
                fileName: fileName,
                contentType: contentType,
                folder: "chat"
            )
            
            // WebSocket으로 메시지 전송
            let outgoingMessage = WebSocketOutgoingMessage(
                type: "chat_message",
                messageType: "file",
                content: "파일을 보냈습니다.",
                encryptedContent: nil,
                replyTo: nil,
                assetId: asset.id,
                isTyping: nil,
                messageIds: nil
            )
            
            wsManager.sendMessage(outgoingMessage)
            
        } catch {
            errorMessage = "파일 업로드 실패: \(error.localizedDescription)"
            showError = true
        }
    }
    
    deinit {
        Task { @MainActor in
            wsManager.disconnect()
        }
        typingTimer?.invalidate()
    }
}
