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
    // MARK: - Published Properties
    @Published var room: ChatRoom?
    @Published var messages: [Message] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var typingUsers: [User] = []
    @Published var onlineUsers: Set<String> = []
    @Published var isDecrypting = false // 복호화 중인지 여부
    @Published var isSending = false // 메시지 전송 중인지 여부
    
    // MARK: - Dependencies
    private let roomId: String
    private let apiService = NetworkManager.shared.chatService
    private let wsManager = ChatWebSocketManager.shared
    private let cryptoManager = E2EECryptoManager.shared
    private let fileUploadService = NetworkManager.shared.fileUploadService
    private let decryptedCache = DecryptedMessageCache.shared
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    private var currentPage = 1
    private var hasMoreMessages = true
    private var typingTimer: Timer?
    private var decryptedMessages: [String: String] = [:] // messageId -> decryptedContent (메모리 캐시)
    private var sentMessageContents: [String: String] = [:] // encryptedContent -> originalContent (내가 보낸 메시지 추적)
    private var isDisconnected = false
    private var publicKeyCache: [String: String] = [:] // userId -> publicKey 캐시
    private var decryptingMessageIds: Set<String> = [] // 현재 복호화 시도 중인 메시지 ID
    private var messageSendStatus: [String: MessageSendStatus] = [:] // messageId -> 전송 상태
    
    enum MessageSendStatus {
        case sending
        case sent
        case failed(Error)
    }
    
    // UserDefaults 키 (내가 보낸 메시지의 원본 내용 저장용)
    private var sentMessagesStorageKey: String {
        "sent_messages_\(roomId)"
    }
    
    init(roomId: String) {
        self.roomId = roomId
        #if DEBUG
        print("✨ [ChatRoomViewModel] init - Room ID: \(roomId)")
        #endif
        
        // 캐시된 복호화 메시지 로드
        Task {
            await loadCachedDecryptedMessages()
        }
    }
    
    /// 디스크에 저장된 복호화 메시지 로드
    private func loadCachedDecryptedMessages() async {
        let cached = await decryptedCache.getAll(roomId: roomId)
        if !cached.isEmpty {
            decryptedMessages = cached
            #if DEBUG
            print("📦 [ChatRoomViewModel] 캐시된 복호화 메시지 로드 완료 - 개수: \(cached.count)")
            #endif
        }
    }
    
    /// 복호화된 메시지를 메모리 및 디스크에 저장
    private func saveDecryptedMessage(messageId: String, content: String) {
        decryptedMessages[messageId] = content
        
        // 디스크에도 저장 (비동기)
        Task {
            await decryptedCache.save(roomId: roomId, messageId: messageId, decryptedContent: content)
        }
    }
    
    deinit {
        #if DEBUG
        print("🗑️ [ChatRoomViewModel] deinit")
        #endif
    }
    
    // MARK: - 초기화

    func loadRoom() async {
        #if DEBUG
        print("🔄 [ChatRoomViewModel] loadRoom 시작 - Room ID: \(roomId)")
        #endif
        
        isLoading = true
        errorMessage = nil
        isDisconnected = false // 재진입 시 연결 상태 초기화
        
        // WebSocket 구독 설정 (최초 1회만)
        if cancellables.isEmpty {
            setupWebSocketSubscriptions()
        } else {
            #if DEBUG
            print("ℹ️ [ChatRoomViewModel] 이미 WebSocket 구독 중")
            #endif
        }
        
        do {
            // 채팅방 정보 로드
            room = try await apiService.fetchChatRoomDetail(roomId: roomId)
            #if DEBUG
            print("✅ [ChatRoomViewModel] 채팅방 정보 로드 완료: \(String(describing: room?.name)), Type: \(String(describing: room?.roomType))")
            #endif
            
            // 1:1 채팅인 경우 상대방의 공개키 미리 가져오기 (백그라운드)
            if room?.roomType == .direct {
                Task {
                    await preloadRecipientPublicKey()
                }
            }
            
            // 메시지 로드 (캐시 사용하되 최신 데이터로 업데이트)
            await loadMessages(page: 1, useCache: true)
            
            // 백그라운드에서 최신 메시지 가져오기 (캐시 무관)
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1초 대기
                await loadMessages(page: 1, useCache: false)
            }
            
            // WebSocket 연결
            if let accessToken = KeychainHelper.getItem(forAccount: "accessToken") {
                // 이미 다른 방에 연결되어 있으면 먼저 연결 해제
                if wsManager.currentRoomId != nil && wsManager.currentRoomId != roomId {
                    #if DEBUG
                    print("🔄 [ChatRoomViewModel] 다른 방에 연결되어 있어 기존 연결 해제")
                    #endif
                    wsManager.disconnect()
                    // 연결 해제 후 잠시 대기
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5초
                }
                
                // WebSocket 연결
                wsManager.connect(roomId: roomId, accessToken: accessToken)
                
                #if DEBUG
                print("✅ [ChatRoomViewModel] WebSocket 연결 요청 완료 - Room ID: \(roomId)")
                #endif
            } else {
                #if DEBUG
                print("⚠️ [ChatRoomViewModel] AccessToken이 없어 WebSocket 연결 실패")
                #endif
                errorMessage = "인증 토큰이 없어 실시간 메시지를 받을 수 없습니다."
            }
            
            // 비밀번호 확인
            if KeychainHelper.getItem(forAccount: "user_password") != nil {
                #if DEBUG
                print("✅ [ChatRoomViewModel] Keychain에 비밀번호 존재함")
                #endif
            } else {
                #if DEBUG
                print("⚠️ [ChatRoomViewModel] Keychain에 비밀번호가 없음! 복호화 불가능")
                #endif
            }
            
        } catch {
            #if DEBUG
            print("❌ [ChatRoomViewModel] loadRoom 실패: \(error)")
            #endif
            errorMessage = error.localizedDescription
            showError = true
        }
        
        isLoading = false
    }
    
    // MARK: - 메시지 로드

    func loadMessages(page: Int = 1, useCache: Bool = true) async {
        #if DEBUG
        print("🔄 [ChatRoomViewModel] loadMessages 시작 - Page: \(page), useCache: \(useCache)")
        #endif
        
        // 첫 페이지 로드 시에만 로딩 표시
        if page == 1 {
            // 캐시가 있으면 즉시 표시하기 위해 isLoading을 false로 시작
            if useCache && !messages.isEmpty {
                isLoading = false
                #if DEBUG
                print("📦 [ChatRoomViewModel] 기존 메시지 표시 중 - 개수: \(messages.count)")
                #endif
            } else {
            isLoading = true
            }
        } else {
            isLoadingMore = true
        }
        
        do {
            let response = try await apiService.fetchMessages(roomId: roomId, page: page, pageSize: 50, useCache: useCache)
            
            #if DEBUG
            print("📨 [ChatRoomViewModel] API 응답 수신 - 메시지 개수: \(response.results.count)")
            #endif
            
            // 즉시 메시지 UI 업데이트 (복호화는 백그라운드에서)
            if page == 1 {
                messages = response.results
            } else {
                // 위에 메시지 추가 (무한 스크롤)
                messages.insert(contentsOf: response.results, at: 0)
            }
            
            currentPage = page
            hasMoreMessages = response.hasNext
            
            // 로딩 상태 즉시 종료 (복호화는 백그라운드에서 진행)
            isLoading = false
            isLoadingMore = false
            
            #if DEBUG
            print("✅ [ChatRoomViewModel] 메시지 UI 업데이트 완료 - 개수: \(response.results.count)")
            #endif
            
            // 백그라운드에서 복호화 진행 (1:1 채팅만)
            if let room = room, room.roomType == .direct {
                // 첫 페이지 로드 시에는 모든 메시지 복호화 (동기적으로)
                if page == 1 {
                    await decryptMessages()
                    #if DEBUG
                    print("🔐 [ChatRoomViewModel] 초기 복호화 완료")
                    #endif
                } else {
                    // 추가 페이지는 새로 로드된 메시지만 복호화 (백그라운드)
                    Task {
                        await preloadDecryption(messages: response.results)
                        #if DEBUG
                        print("🔐 [ChatRoomViewModel] 백그라운드 복호화 완료")
                        #endif
                    }
                }
            }
            
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        isLoading = false
        isLoadingMore = false
        }
        
        isDecrypting = false
    }
    
    // MARK: - 더 많은 메시지 로드

    func loadMoreMessages() async {
        guard hasMoreMessages, !isLoadingMore else { return }
        await loadMessages(page: currentPage + 1, useCache: false) // 추가 페이지는 캐시 사용 안 함
    }
    
    // MARK: - 메시지 전송

    func sendMessage(content: String, replyTo: String? = nil) async {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        // 이미 전송 중이면 중복 전송 방지
        guard !isSending else {
            #if DEBUG
            print("⚠️ [ChatRoomViewModel] 이미 메시지 전송 중이므로 중복 전송 방지")
            #endif
            return
        }
        
        isSending = true
        defer { isSending = false }
        
        let outgoingMessage: WebSocketOutgoingMessage
        
        if room?.roomType == .direct {
            // 1:1 채팅: 암호화 필요
            // CurrentUser.shared.id가 nil인 경우 사용자 정보 다시 로드 시도
            if CurrentUser.shared.id == nil {
                do {
                    let user = try await NetworkManager.shared.userService.fetchMe()
                    CurrentUser.shared.update(user: user)
                } catch {
                    errorMessage = "사용자 정보를 가져올 수 없습니다."
                    showError = true
                    return
                }
            }
            
            guard let currentUserId = CurrentUser.shared.id else {
                errorMessage = "사용자 정보를 가져올 수 없습니다."
                showError = true
                return
            }
            
            guard let otherMember = room?.members.first(where: { $0.user.id != currentUserId }) else {
                errorMessage = "상대방 정보를 찾을 수 없습니다."
                showError = true
                return
            }
            
            // 캐시에서 공개키 확인, 없으면 API 호출
            let publicKeyPEM: String
            if let cachedKey = publicKeyCache[otherMember.user.id] {
                publicKeyPEM = cachedKey
                #if DEBUG
                print("✅ [ChatRoomViewModel] 캐시에서 공개키 사용: \(otherMember.user.id)")
                #endif
            } else {
                do {
                    publicKeyPEM = try await fetchUserPublicKey(userId: otherMember.user.id)
                    publicKeyCache[otherMember.user.id] = publicKeyPEM
                    #if DEBUG
                    print("✅ [ChatRoomViewModel] 공개키 가져오기 및 캐싱 완료: \(otherMember.user.id)")
                    #endif
                } catch {
                    errorMessage = "상대방의 공개키를 가져올 수 없습니다: \(error.localizedDescription)"
                    showError = true
                    return
                }
            }
            
            // 내 공개키 가져오기 (양방향 암호화용)
            let selfPublicKeyPEM: String?
            if let cachedSelfKey = publicKeyCache[currentUserId] {
                selfPublicKeyPEM = cachedSelfKey
                #if DEBUG
                print("✅ [ChatRoomViewModel] 캐시에서 내 공개키 사용")
                #endif
            } else {
                do {
                    let selfKey = try await fetchUserPublicKey(userId: currentUserId)
                    publicKeyCache[currentUserId] = selfKey
                    selfPublicKeyPEM = selfKey
                    #if DEBUG
                    print("✅ [ChatRoomViewModel] 내 공개키 가져오기 및 캐싱 완료")
                    #endif
                } catch {
                    #if DEBUG
                    print("⚠️ [ChatRoomViewModel] 내 공개키 가져오기 실패 - 양방향 암호화 스킵: \(error)")
                    #endif
                    selfPublicKeyPEM = nil
                }
            }
            
            do {
                // 하이브리드 암호화 사용 (RSA + AES) - 양방향 암호화
                let encryptionResult = try await cryptoManager.encryptMessageHybrid(
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
                
                // 내가 보낸 메시지의 원본 내용을 암호화된 내용을 키로 저장
                // 서버에서 받은 메시지의 encryptedContent와 매칭하여 사용
                sentMessageContents[encryptionResult.encryptedContent] = content
                
                // 임시 메시지 ID 생성 (타임스탬프 기반)
                let tempMessageId = "temp_\(Date().timeIntervalSince1970)_\(UUID().uuidString.prefix(8))"
                
                // CurrentUser에서 User 생성 및 임시 메시지 추가
                if let currentUserId = CurrentUser.shared.id,
                   let currentUserName = CurrentUser.shared.name {
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
                    
                    // 임시 메시지 생성 및 로컬에 추가
                    let tempMessage = Message(
                        id: tempMessageId,
                        room: roomId,
                        sender: currentUser,
                        messageType: .text,
                        content: nil,
                        encryptedContent: encryptionResult.encryptedContent,
                        encryptedSessionKey: encryptionResult.encryptedSessionKey,
                        selfEncryptedSessionKey: encryptionResult.selfEncryptedSessionKey,
                        asset: nil,
                        replyTo: replyTo != nil ? ReplyToMessage(id: replyTo!, sender: currentUser, content: "", messageType: .text) : nil,
                        isRead: false,
                        createdAt: now,
                        updatedAt: now
                    )
                    
                    // 메시지 목록에 추가 (낙관적 업데이트)
                    messages.append(tempMessage)
                    
                    // 전송 상태 추적
                    messageSendStatus[tempMessageId] = .sending
                    
                    // 복호화된 내용을 즉시 저장 (내가 보낸 메시지는 원본 내용 사용)
                    saveDecryptedMessage(messageId: tempMessageId, content: content)
                    
                    // UserDefaults에도 저장 (앱 재시작 후에도 복원 가능하도록)
                    saveSentMessageContent(messageId: tempMessageId, content: content)
                    
                    #if DEBUG
                    print("💾 [ChatRoomViewModel] 임시 메시지 생성 및 복호화된 내용 저장 완료")
                    print("   임시 메시지 ID: \(tempMessageId)")
                    print("   복호화된 내용: \(content.prefix(30))...")
                    #endif
                } else {
                    #if DEBUG
                    print("⚠️ [ChatRoomViewModel] CurrentUser 정보가 불완전하여 임시 메시지 생성 실패")
                    #endif
                    // 임시 메시지 없이 진행
                }
                
                #if DEBUG
                print("💾 [ChatRoomViewModel] 하이브리드 암호화 완료")
                print("   원본 메시지: \(content)")
                print("   encryptedContent 길이: \(encryptionResult.encryptedContent.count)")
                print("   encryptedSessionKey 길이: \(encryptionResult.encryptedSessionKey.count)")
                print("   encryptedContent 앞부분: \(encryptionResult.encryptedContent.prefix(50))...")
                print("   encryptedSessionKey 앞부분: \(encryptionResult.encryptedSessionKey.prefix(50))...")
                print("   상대방 ID: \(otherMember.user.id)")
                print("   상대방 공개키 사용 여부: ✅")
                #endif
            } catch {
                errorMessage = "메시지 암호화에 실패했습니다: \(error.localizedDescription)"
                showError = true
                return
            }
        } else {
            // 그룹 채팅: 평문
            // 임시 메시지 ID 생성
            let tempMessageId = "temp_\(Date().timeIntervalSince1970)_\(UUID().uuidString.prefix(8))"
            
            // 임시 메시지 생성 (낙관적 업데이트)
            if let currentUserId = CurrentUser.shared.id,
               let currentUserName = CurrentUser.shared.name {
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
                
                let tempMessage = Message(
                    id: tempMessageId,
                    room: roomId,
                    sender: currentUser,
                    messageType: .text,
                    content: content,
                    encryptedContent: nil,
                    encryptedSessionKey: nil,
                    selfEncryptedSessionKey: nil,
                    asset: nil,
                    replyTo: replyTo != nil ? ReplyToMessage(id: replyTo!, sender: currentUser, content: "", messageType: .text) : nil,
                    isRead: false,
                    createdAt: now,
                    updatedAt: now
                )
                
                // 메시지 목록에 즉시 추가 (낙관적 업데이트)
                messages.append(tempMessage)
                messageSendStatus[tempMessageId] = .sending
                
                #if DEBUG
                print("💬 [ChatRoomViewModel] 그룹 채팅 임시 메시지 생성 - ID: \(tempMessageId)")
                #endif
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
        
        #if DEBUG
        print("📤 [ChatRoomViewModel] WebSocket으로 메시지 전송 시도")
        print("   WebSocket 연결 상태: \(wsManager.isConnected)")
        print("   현재 Room ID: \(wsManager.currentRoomId ?? "nil")")
        print("   타겟 Room ID: \(roomId)")
        print("   메시지 타입: \(outgoingMessage.type)")
        #endif
        
        // WebSocket 연결 상태 확인
        guard wsManager.isConnected else {
            #if DEBUG
            print("❌ [ChatRoomViewModel] WebSocket이 연결되지 않아 메시지 전송 실패")
            #endif
            errorMessage = "WebSocket 연결이 끊어져 메시지를 전송할 수 없습니다."
            showError = true
            return
        }
        
        // 현재 방과 WebSocket 연결 방이 일치하는지 확인
        guard wsManager.currentRoomId == roomId else {
            #if DEBUG
            print("❌ [ChatRoomViewModel] 다른 방에 연결되어 있어 메시지 전송 실패")
            print("   현재 연결된 Room: \(wsManager.currentRoomId ?? "nil"), 타겟 Room: \(roomId)")
            #endif
            errorMessage = "다른 채팅방에 연결되어 있어 메시지를 전송할 수 없습니다."
            showError = true
            return
        }
        
        wsManager.sendMessage(outgoingMessage)
        
        // 메시지 캐시 무효화 (백그라운드)
        Task {
            await apiService.invalidateMessageCache(for: roomId)
        }
    }
    
    // MARK: - 타이핑 인디케이터 전송

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
    
    private var unreadMessageIds: Set<String> = [] // 아직 읽지 않은 메시지 ID 추적
    private var readReceiptTask: Task<Void, Never>? // 읽음 처리 디바운싱용
    
    func onMessageAppear(_ message: Message) {
        // 내가 보낸 메시지거나 이미 읽은 메시지는 스킵
        guard !message.isFromCurrentUser && !message.isRead else { return }
        
        // 아직 읽지 않은 메시지로 추가
        unreadMessageIds.insert(message.id)
        
        // 디바운싱: 0.5초 후에 일괄 처리
        readReceiptTask?.cancel()
        readReceiptTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5초
            
            guard !Task.isCancelled, !unreadMessageIds.isEmpty else { return }
            
            let idsToMark = Array(unreadMessageIds)
            unreadMessageIds.removeAll()
            
            await markMessagesAsRead(messageIds: idsToMark)
        }
    }

    func markMessagesAsRead(messageIds: [String]) async {
        // 낙관적 업데이트: 즉시 UI 업데이트
        var updatedMessages: [Message] = []
        for i in 0..<messages.count {
            if messageIds.contains(messages[i].id) && !messages[i].isRead {
                messages[i] = messages[i].withReadStatus(true)
                updatedMessages.append(messages[i])
            }
        }
        
        #if DEBUG
        if !updatedMessages.isEmpty {
            print("✅ [ChatRoomViewModel] 즉시 읽음 처리 (낙관적 업데이트) - 개수: \(updatedMessages.count)")
        }
        #endif
        
        // WebSocket이 연결되어 있으면 즉시 전송
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
                messageIds: messageIds
            )
            wsManager.sendMessage(message)
        }
            
        // API 호출 (WebSocket 연결 여부와 관계없이 항상 호출)
        // 채팅방을 나간 후에도 읽음 처리가 서버에 반영되도록
        Task {
            do {
                try await apiService.markMessagesAsRead(roomId: roomId, messageIds: messageIds)
                
                #if DEBUG
                print("✅ [ChatRoomViewModel] 읽음 처리 API 호출 성공")
                #endif
        } catch {
                #if DEBUG
                print("❌ [ChatRoomViewModel] 읽음 처리 API 호출 실패: \(error)")
                #endif
            }
        }
    }
    
    // MARK: - 채팅방 나가기

    func leaveRoom() async -> Bool {
        do {
            // API 호출
            try await apiService.leaveChatRoom(roomId: roomId)
            
            // WebSocket 연결 해제
            disconnect()
            
            #if DEBUG
            print("✅ [ChatRoomViewModel] 채팅방 나가기 성공 - Room ID: \(roomId)")
            #endif
            
            return true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            
            #if DEBUG
            print("❌ [ChatRoomViewModel] 채팅방 나가기 실패: \(error)")
            #endif
            
            return false
        }
    }
    
    // MARK: - 연결 해제
    
    func disconnect() {
        guard !isDisconnected else { return }
        isDisconnected = true
        
        #if DEBUG
        print("🔌 [ChatRoomViewModel] disconnect 호출됨")
        #endif
        
        // 구독 취소
        cancellables.removeAll()
        
        // 타이머 정리
        typingTimer?.invalidate()
        typingTimer = nil
        
        // WebSocket 연결 해제
        if wsManager.currentRoomId == roomId {
            wsManager.disconnect()
        }
    }
    
    // MARK: - WebSocket 구독 설정

    private func setupWebSocketSubscriptions() {
        #if DEBUG
        print("📡 [ChatRoomViewModel] setupWebSocketSubscriptions 시작")
        #endif
        
        // 웹소켓 연결 상태 모니터링
        wsManager.$isConnected
            .sink { [weak self] isConnected in
                Task { @MainActor in
                    #if DEBUG
                    print("🔌 [ChatRoomViewModel] WebSocket 연결 상태 변경: \(isConnected ? "연결됨" : "연결 끊김")")
                    #endif
                    if !isConnected, let self = self, !self.isDisconnected {
                        // 연결이 끊겼을 때 자동 재연결 시도
                        if let accessToken = KeychainHelper.getItem(forAccount: "accessToken") {
                            #if DEBUG
                            print("🔄 [ChatRoomViewModel] WebSocket 재연결 시도")
                            #endif
                            self.wsManager.connect(roomId: self.roomId, accessToken: accessToken)
                        }
                    }
                }
            }
            .store(in: &cancellables)
        
        // 메시지 수신
        wsManager.receivedMessage
            .sink { [weak self] incomingMessage in
                #if DEBUG
                print("📨 [ChatRoomViewModel] Sink 수신 - Type: \(incomingMessage.type)")
                print("   Current Room ID: \(self?.roomId ?? "nil")")
                print("   WebSocket Room ID: \(self?.wsManager.currentRoomId ?? "nil")")
                print("   isDisconnected: \(self?.isDisconnected ?? true)")
                #endif
                
                Task { @MainActor in
                    guard let self = self else { return }
                    
                    // 연결이 끊어진 상태면 무시하지 않음 (재연결 시 메시지 수신 가능)
                    // 하지만 명시적으로 disconnect()가 호출된 경우는 무시
                    guard !self.isDisconnected else {
                        #if DEBUG
                        print("⚠️ [ChatRoomViewModel] 연결이 끊어진 상태라 메시지 무시")
                        #endif
                        return
                    }
                    
                    // 현재 방과 WebSocket 연결 방이 일치하는지 확인
                    guard self.wsManager.currentRoomId == self.roomId else {
                        #if DEBUG
                        print("⚠️ [ChatRoomViewModel] 다른 방의 메시지 무시 - Current: \(self.roomId), WS: \(self.wsManager.currentRoomId ?? "nil")")
                        #endif
                        return
                    }
                    
                    #if DEBUG
                    print("📨 [ChatRoomViewModel] WebSocket 메시지 처리 Task 진입 - Type: \(incomingMessage.type)")
                    #endif
                    if let message = incomingMessage.message {
                        #if DEBUG
                        print("📨 [ChatRoomViewModel] 메시지 처리 시작 - ID: \(message.id), Sender: \(message.sender.name), Room: \(message.room)")
                        #endif
                        // 메시지의 방 ID도 확인 (포함 관계 검사로 변경)
                        guard message.room.contains(self.roomId) else {
                            #if DEBUG
                            print("⚠️ [ChatRoomViewModel] 다른 방의 메시지 무시 - Message Room: \(message.room), Current Room: \(self.roomId)")
                            #endif
                            return
                        }
                        await self.handleNewMessage(message)
                    } else {
                        #if DEBUG
                        print("⚠️ [ChatRoomViewModel] 메시지가 nil입니다")
                        #endif
                    }
                }
            }
            .store(in: &cancellables)
        
        // 타이핑 인디케이터
        wsManager.typingIndicator
            .sink { [weak self] user, isTyping in
                Task { @MainActor in
                    guard let self = self else { return }
                    // 자신의 타이핑 인디케이터는 표시하지 않음
                    guard let currentUserId = CurrentUser.shared.id,
                          user.id != currentUserId else { return }
                    
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
                    // 읽음 상태 업데이트: 해당 메시지들의 isRead를 true로 업데이트
                    // 자신이 보낸 메시지만 읽음 상태 업데이트 (상대방이 읽었을 때)
                    guard let currentUserId = CurrentUser.shared.id else { return }
                    
                    var updatedMessages = self.messages
                    var hasUpdate = false
                    
                    for (index, message) in updatedMessages.enumerated() {
                        if messageIds.contains(message.id) && message.sender.id == currentUserId && !message.isRead {
                            // 자신이 보낸 메시지이고 상대방이 읽었을 때 읽음 상태 업데이트
                            updatedMessages[index] = message.withReadStatus(true)
                            hasUpdate = true
                            #if DEBUG
                            print("✅ [ChatRoomViewModel] 읽음 확인 수신 - User \(userId) read message: \(message.id)")
                            #endif
                        }
                    }
                    
                    if hasUpdate {
                        self.messages = updatedMessages
                    }
                }
            }
            .store(in: &cancellables)
        
        // 메시지 수정
        wsManager.messageUpdate
            .sink { [weak self] updatedMessage in
                Task { @MainActor in
                    guard let self = self else { return }
                    
                    #if DEBUG
                    print("✏️ [ChatRoomViewModel] 메시지 수정 이벤트 수신 - Message ID: \(updatedMessage.id)")
                    print("   isFromCurrentUser: \(updatedMessage.isFromCurrentUser)")
                    #endif
                    
                    // 메시지 목록에서 해당 메시지 찾아서 업데이트
                    if let index = self.messages.firstIndex(where: { $0.id == updatedMessage.id }) {
                        self.messages[index] = updatedMessage
                        
                        // 1:1 채팅이고 암호화된 메시지인 경우, 복호화된 내용도 업데이트
                        if self.room?.roomType == .direct, let encryptedContent = updatedMessage.encryptedContent {
                            // 기존 캐시 삭제
                            self.decryptedMessages.removeValue(forKey: updatedMessage.id)
                            await self.decryptedCache.remove(roomId: self.roomId, messageId: updatedMessage.id)
                            
                            // 올바른 키로 재복호화
                            if updatedMessage.isFromCurrentUser {
                                // 내가 수정한 메시지 - selfEncryptedSessionKey 사용
                                if let selfEncryptedSessionKey = updatedMessage.selfEncryptedSessionKey {
                                    await self.decryptMessage(
                                        messageId: updatedMessage.id,
                                        encryptedContent: encryptedContent,
                                        encryptedSessionKey: selfEncryptedSessionKey,
                                        isSelfKey: true
                                    )
                                    
                                    #if DEBUG
                                    print("✅ [ChatRoomViewModel] 내가 수정한 메시지 복호화 완료")
                                    #endif
                                }
                            } else {
                                // 상대방이 수정한 메시지 - encryptedSessionKey 사용
                                if let encryptedSessionKey = updatedMessage.encryptedSessionKey {
                                    await self.decryptMessage(
                                        messageId: updatedMessage.id,
                                        encryptedContent: encryptedContent,
                                        encryptedSessionKey: encryptedSessionKey,
                                        isSelfKey: false
                                    )
                                    
                                    #if DEBUG
                                    print("✅ [ChatRoomViewModel] 상대방이 수정한 메시지 복호화 완료")
                                    #endif
                                }
                            }
                        }
                        
                        #if DEBUG
                        print("✅ [ChatRoomViewModel] 메시지 수정 완료")
                        #endif
                    }
                }
            }
            .store(in: &cancellables)
        
        // 메시지 삭제
        wsManager.messageDelete
            .sink { [weak self] messageId in
                Task { @MainActor in
                    guard let self = self else { return }
                    
                    #if DEBUG
                    print("🗑️ [ChatRoomViewModel] 메시지 삭제 이벤트 수신 - Message ID: \(messageId)")
                    #endif
                    
                    // 메시지 목록에서 해당 메시지 삭제
                    self.messages.removeAll { $0.id == messageId }
                    
                    // 캐시에서도 삭제
                    self.decryptedMessages.removeValue(forKey: messageId)
                    Task {
                        await self.decryptedCache.remove(roomId: self.roomId, messageId: messageId)
                    }
                    
                    #if DEBUG
                    print("✅ [ChatRoomViewModel] 메시지 삭제 완료")
                    #endif
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

    private func handleNewMessage(_ message: Message) async {
        #if DEBUG
        print("🔄 [ChatRoomViewModel] handleNewMessage 시작 - ID: \(message.id), isFromCurrentUser: \(message.isFromCurrentUser)")
        print("   현재 메시지 개수: \(messages.count)")
        print("   Room ID: \(message.room), Current Room ID: \(roomId)")
        print("   isDisconnected: \(isDisconnected)")
        #endif
        
        // 연결이 끊어진 상태면 무시하지 않음 (재연결 시 메시지 수신 가능)
        // 하지만 명시적으로 disconnect()가 호출된 경우는 무시
        guard !isDisconnected else {
            #if DEBUG
            print("⚠️ [ChatRoomViewModel] 연결이 끊어진 상태라 메시지 무시: \(message.id)")
            #endif
            return
        }
        
        // 임시 메시지 찾기 (내가 보낸 메시지인 경우)
        if message.isFromCurrentUser {
            var tempMessageIndex: Int? = nil
            var tempMessageId: String? = nil
            
            // 1. encryptedContent로 매칭 (텍스트 메시지)
            if let encryptedContent = message.encryptedContent {
                tempMessageIndex = messages.firstIndex(where: { 
                    $0.id.hasPrefix("temp_") && $0.encryptedContent == encryptedContent 
                })
                if let index = tempMessageIndex {
                    tempMessageId = messages[index].id
                }
            }
            // 2. asset.id로 매칭 (이미지/파일 메시지)
            else if let asset = message.asset {
                tempMessageIndex = messages.firstIndex(where: { 
                    $0.id.hasPrefix("temp_") && $0.asset?.id == asset.id
                })
                if let index = tempMessageIndex {
                    tempMessageId = messages[index].id
                }
            }
            
            // 임시 메시지를 실제 메시지로 교체
            if let index = tempMessageIndex, let tempId = tempMessageId {
                let tempMessageId = tempId
                
                // 복호화된 내용이 있으면 새 메시지 ID로 이동 (텍스트 메시지만)
                if let decryptedContent = decryptedMessages[tempMessageId] {
                    saveDecryptedMessage(messageId: message.id, content: decryptedContent)
                    decryptedMessages.removeValue(forKey: tempMessageId)
                    
                    // 임시 메시지 캐시 삭제
                    Task {
                        await decryptedCache.save(roomId: roomId, messageId: tempMessageId, decryptedContent: "")
                    }
                }
                
                // 임시 메시지 제거하고 실제 메시지로 교체
                messages.remove(at: index)
                messageSendStatus[message.id] = .sent
                messageSendStatus.removeValue(forKey: tempMessageId)
                
                #if DEBUG
                print("✅ [ChatRoomViewModel] 임시 메시지를 실제 메시지로 교체: \(tempMessageId) -> \(message.id)")
                print("   메시지 타입: \(message.messageType.rawValue)")
                if let asset = message.asset {
                    print("   Asset URL: \(asset.url)")
                }
                #endif
            }
        }
        
        // 중복 방지
        if messages.contains(where: { $0.id == message.id }) {
            #if DEBUG
            print("⚠️ [ChatRoomViewModel] 중복 메시지 무시: \(message.id)")
            #endif
            return
        }
        
        // 1:1 채팅인 경우 메시지 추가 전에 미리 복호화 (아직 복호화되지 않은 경우만)
        if room?.roomType == .direct, let encryptedContent = message.encryptedContent {
            // 이미 복호화되어 있으면 스킵
            if decryptedMessages[message.id] == nil {
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
                        saveSentMessageContent(messageId: message.id, content: originalContent)
                        sentMessageContents.removeValue(forKey: encryptedContent)
                    } else if let savedContent = loadSentMessageContent(messageId: message.id) {
                        saveDecryptedMessage(messageId: message.id, content: savedContent)
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
        
        // 메시지 추가
        messages.append(message)
        #if DEBUG
        print("✅ [ChatRoomViewModel] 메시지 추가 완료 - 총 개수: \(messages.count)")
        #endif
        
        // 읽음 확인 전송 (자신이 보낸 메시지가 아닌 경우)
        if !message.isFromCurrentUser {
            Task {
                await markMessagesAsRead(messageIds: [message.id])
            }
        }
    }
    
    // MARK: - 메시지 수정 및 삭제
    
    func deleteMessage(_ message: Message) {
        let messageId = message.id
        
        // 낙관적 업데이트: 리스트에서 제거
        // 원래 목록 백업 (롤백용)
        let originalMessages = messages
        
        withAnimation {
            messages.removeAll { $0.id == messageId }
        }
        
        Task {
            do {
                try await apiService.deleteMessage(roomId: roomId, messageId: messageId)
                
                // 메시지 캐시 무효화
                await apiService.invalidateMessageCache(for: roomId)
                
                #if DEBUG
                print("✅ [ChatRoomViewModel] 메시지 삭제 성공: \(messageId)")
                #endif
            } catch {
                #if DEBUG
                print("❌ [ChatRoomViewModel] 메시지 삭제 실패: \(error)")
                #endif
                // 실패 시 롤백
                await MainActor.run {
                    withAnimation {
                        messages = originalMessages
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
                    // 1:1 채팅: 새로운 암호화 생성 (상대방과 나 모두를 위해)
                    guard let currentUserId = CurrentUser.shared.id else {
                        throw NSError(domain: "Whisper", code: -1, userInfo: [NSLocalizedDescriptionKey: "사용자 정보를 찾을 수 없습니다."])
                    }
                    
                    guard let otherMember = room?.members.first(where: { $0.user.id != currentUserId }) else {
                        throw NSError(domain: "Whisper", code: -1, userInfo: [NSLocalizedDescriptionKey: "상대방 정보를 찾을 수 없습니다."])
                    }
                    
                    // 상대방 공개키 가져오기
                    let recipientPublicKeyPEM: String
                    if let cachedKey = publicKeyCache[otherMember.user.id] {
                        recipientPublicKeyPEM = cachedKey
                    } else {
                        recipientPublicKeyPEM = try await fetchUserPublicKey(userId: otherMember.user.id)
                        publicKeyCache[otherMember.user.id] = recipientPublicKeyPEM
                    }
                    
                    // 내 공개키 가져오기
                    let selfPublicKeyPEM: String?
                    if let cachedSelfKey = publicKeyCache[currentUserId] {
                        selfPublicKeyPEM = cachedSelfKey
                    } else {
                        do {
                            let selfKey = try await fetchUserPublicKey(userId: currentUserId)
                            publicKeyCache[currentUserId] = selfKey
                            selfPublicKeyPEM = selfKey
                        } catch {
                            #if DEBUG
                            print("⚠️ [ChatRoomViewModel] 내 공개키 가져오기 실패: \(error)")
                            #endif
                            selfPublicKeyPEM = nil
                        }
                    }
                    
                    // 하이브리드 암호화로 새로 암호화
                    let encryptionResult = try await cryptoManager.encryptMessageHybrid(
                        newContent,
                        recipientPublicKeyPEM: recipientPublicKeyPEM,
                        selfPublicKeyPEM: selfPublicKeyPEM
                    )
                    
                    updatedEncryptedContent = encryptionResult.encryptedContent
                    updatedEncryptedSessionKey = encryptionResult.encryptedSessionKey
                    updatedSelfEncryptedSessionKey = encryptionResult.selfEncryptedSessionKey
                    
                    #if DEBUG
                    print("✏️ [ChatRoomViewModel] 메시지 수정 - 새 암호화 생성 완료")
                    print("   encryptedContent 길이: \(encryptionResult.encryptedContent.count)")
                    print("   encryptedSessionKey 존재: \(encryptionResult.encryptedSessionKey != nil)")
                    print("   selfEncryptedSessionKey 존재: \(encryptionResult.selfEncryptedSessionKey != nil)")
                    #endif
                    
                } else {
                    // 그룹 채팅: 평문 전송
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
                
                // 로컬 업데이트
                await MainActor.run {
                    if let index = messages.firstIndex(where: { $0.id == messageId }) {
                        messages[index] = updatedMessage
                        // 복호화된 내용 캐시도 업데이트 (1:1인 경우)
                        if room?.roomType == .direct {
                            saveDecryptedMessage(messageId: messageId, content: newContent)
                            // 원본 내용 저장소도 업데이트
                            saveSentMessageContent(messageId: messageId, content: newContent)
                        }
                    }
                }
                
                #if DEBUG
                print("✅ [ChatRoomViewModel] 메시지 수정 성공: \(messageId)")
                #endif
                
            } catch {
                #if DEBUG
                print("❌ [ChatRoomViewModel] 메시지 수정 실패: \(error)")
                #endif
                await MainActor.run {
                    errorMessage = "메시지 수정에 실패했습니다: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }
    
    // MARK: - 메시지 복호화
    
    private func preloadDecryption(messages: [Message]) async {
        #if DEBUG
        print("🔄 [ChatRoomViewModel] 메시지 프리로드 복호화 시작 - 개수: \(messages.count)")
        #endif
        
        // 먼저 로컬 저장소에서 복원 가능한 메시지들 빠르게 처리 (MainActor에서)
        for message in messages {
            // 이미 복호화된 내용이 있으면 스킵
            if decryptedMessages[message.id] != nil { continue }
            
            if let encryptedContent = message.encryptedContent {
                if message.isFromCurrentUser {
                    // 내가 보낸 메시지: 로컬 저장소에서 원본 찾기 (빠른 경로)
                    if message.selfEncryptedSessionKey == nil {
                        if let originalContent = sentMessageContents[encryptedContent] {
                            saveDecryptedMessage(messageId: message.id, content: originalContent)
                            saveSentMessageContent(messageId: message.id, content: originalContent)
                        } else if let savedContent = loadSentMessageContent(messageId: message.id) {
                            saveDecryptedMessage(messageId: message.id, content: savedContent)
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
                // selfEncryptedSessionKey가 있어야 복호화 가능
                return message.selfEncryptedSessionKey != nil
            } else {
                // 상대방 메시지는 항상 복호화 시도
                return true
            }
        }
        
        #if DEBUG
        print("🔐 [ChatRoomViewModel] 복호화 필요한 메시지: \(messagesToDecrypt.count)개")
        #endif
        
        guard !messagesToDecrypt.isEmpty else {
            #if DEBUG
            print("✅ [ChatRoomViewModel] 복호화할 메시지 없음, 완료")
            #endif
            return
        }
        
        // TaskGroup을 사용하여 병렬로 복호화 수행
        // 동시에 너무 많은 작업이 실행되지 않도록 배치 처리
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
                            // 내가 보낸 메시지 (selfEncryptedSessionKey 사용)
                            if let selfEncryptedSessionKey = message.selfEncryptedSessionKey {
                                await self.decryptMessage(
                                    messageId: message.id,
                                    encryptedContent: encryptedContent,
                                    encryptedSessionKey: selfEncryptedSessionKey,
                                    isSelfKey: true
                                )
                            }
                        } else {
                            // 상대방이 보낸 메시지
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
        print("✅ [ChatRoomViewModel] 메시지 프리로드 복호화 완료")
        #endif
    }

    private func decryptMessages() async {
        #if DEBUG
        print("🔄 [ChatRoomViewModel] decryptMessages 시작")
        print("   Room Type: \(String(describing: room?.roomType))")
        print("   Messages Count: \(messages.count)")
        print("   이미 복호화 중: \(isDecrypting)")
        #endif
        
        // 이미 복호화 중이면 스킵 (중복 실행 방지)
        guard !isDecrypting else {
            #if DEBUG
            print("⚠️ [ChatRoomViewModel] 이미 복호화 중이므로 스킵")
            #endif
            return
        }
        
        guard room?.roomType == .direct else {
            #if DEBUG
            print("⚠️ [ChatRoomViewModel] 1:1 채팅방이 아니어서 복호화 스킵")
            #endif
            return
        }
        
        isDecrypting = true
        
        for message in messages {
            if let encryptedContent = message.encryptedContent {
                // 이미 복호화되었거나 복호화 중인 메시지는 스킵
                if decryptedMessages[message.id] == nil && !decryptingMessageIds.contains(message.id) {
                    #if DEBUG
                    print("🔍 [ChatRoomViewModel] 메시지 복호화 시도: \(message.id)")
                    print("   isFromCurrentUser: \(message.isFromCurrentUser)")
                    print("   encryptedSessionKey 존재: \(message.encryptedSessionKey != nil)")
                    print("   selfEncryptedSessionKey 존재: \(message.selfEncryptedSessionKey != nil)")
                    #endif
                    
                    if message.isFromCurrentUser {
                        // 내가 보낸 메시지 처리
                        // 1순위: selfEncryptedSessionKey가 있으면 내 개인키로 복호화 시도 (양방향 암호화)
                        if let selfEncryptedSessionKey = message.selfEncryptedSessionKey {
                            #if DEBUG
                            print("🔄 [ChatRoomViewModel] 로드된 메시지에서 내가 보낸 메시지 - 양방향 암호화 복호화 시도: \(message.id)")
                            #endif
                            await decryptMessage(
                                messageId: message.id,
                                encryptedContent: encryptedContent,
                                encryptedSessionKey: selfEncryptedSessionKey,
                                isSelfKey: true
                            )
                        }
                        // 2순위: sentMessageContents에서 찾기 (전송 시 저장한 원본)
                        else if let originalContent = sentMessageContents[encryptedContent] {
                            saveDecryptedMessage(messageId: message.id, content: originalContent)
                            // UserDefaults에도 저장
                            saveSentMessageContent(messageId: message.id, content: originalContent)
                            #if DEBUG
                            print("✅ [ChatRoomViewModel] 로드된 메시지에서 내가 보낸 메시지 원본 내용 매칭: \(message.id)")
                            #endif
                        }
                        // 3순위: UserDefaults에서 찾기
                        else if let savedContent = loadSentMessageContent(messageId: message.id) {
                            saveDecryptedMessage(messageId: message.id, content: savedContent)
                            #if DEBUG
                            print("✅ [ChatRoomViewModel] UserDefaults에서 로드된 메시지의 원본 내용 복원: \(message.id)")
                            print("   원본 내용: \(savedContent.prefix(30))...")
                            #endif
                        } else {
                            // 원본을 찾을 수 없음
                            #if DEBUG
                            print("⚠️ [ChatRoomViewModel] 로드된 메시지에서 내가 보낸 메시지 원본 내용을 찾을 수 없음: \(message.id)")
                            print("   selfEncryptedSessionKey 존재: \(message.selfEncryptedSessionKey != nil)")
                            print("   이는 앱 재시작 후 로드된 메시지이거나 이전 세션에서 보낸 메시지일 수 있습니다.")
                            #endif
                            // 내가 보낸 메시지는 복호화할 수 없으므로 "[암호화된 메시지]" 표시
                        }
                    } else {
                        // 상대방이 보낸 메시지: 내 개인키로 복호화 가능
                        #if DEBUG
                        print("🔄 [ChatRoomViewModel] 상대방 메시지 복호화 호출: \(message.id)")
                        #endif
                        await decryptMessage(
                            messageId: message.id,
                            encryptedContent: encryptedContent,
                            encryptedSessionKey: message.encryptedSessionKey,
                            isSelfKey: false
                        )
                    }
                } else {
                    // 이미 복호화됨
                    // print("ℹ️ [ChatRoomViewModel] 이미 복호화된 메시지: \(message.id)")
                }
            } else {
                // 암호화된 콘텐츠 없음
                // print("ℹ️ [ChatRoomViewModel] 암호화된 콘텐츠 없음: \(message.id)")
            }
        }
        
        isDecrypting = false
        
        #if DEBUG
        print("✅ [ChatRoomViewModel] decryptMessages 완료")
        #endif
    }
    
    // MARK: - 개별 메시지 복호화

    private func decryptMessage(messageId: String, encryptedContent: String, encryptedSessionKey: String?, isSelfKey: Bool = false) async {
        // 중복 시도 방지 (이미 진행 중이면 스킵)
        // 단, getDisplayContent에서 호출할 때는 이미 set에 추가하고 호출하므로 체크하지 않음
        // 여기서는 완료 후 제거만 담당
        
        // Keychain에서 비밀번호 가져오기 (MainActor에서 수행)
        guard let password = KeychainHelper.getItem(forAccount: "user_password") else {
            #if DEBUG
            print("⚠️ [ChatRoomViewModel] 비밀번호를 찾을 수 없어 메시지 복호화 실패")
            #endif
            decryptingMessageIds.remove(messageId)
            
            // 사용자에게 알림 표시 (중복 표시 방지)
            if errorMessage == nil {
                errorMessage = "보안 비밀번호를 찾을 수 없습니다. 다시 로그인해주세요."
                showError = true
            }
            return
        }
        
        // 복호화를 백그라운드 스레드에서 수행하여 UI 끊김 방지
        // cryptoManager 캡처 (불변 참조이므로 안전)
        let cryptoManager = self.cryptoManager
        
        let result: String? = await Task.detached(priority: .userInitiated) {
            do {
                let decryptedContent: String
                
                if isSelfKey, let key = encryptedSessionKey {
                    // 내 공개키로 암호화된 세션 키를 사용하여 복호화 (양방향 암호화)
                    decryptedContent = try await cryptoManager.decryptMessageHybridWithSelfKey(
                        encryptedContent,
                        selfEncryptedSessionKey: key,
                        password: password
                    )
                } else {
                    // 메시지 복호화 (하이브리드 또는 기존 방식 자동 감지)
                    decryptedContent = try await cryptoManager.decryptMessage(
                        encryptedContent,
                        encryptedSessionKey: encryptedSessionKey,
                        password: password
                    )
                }
                
                #if DEBUG
                if encryptedSessionKey != nil {
                    print("✅ [ChatRoomViewModel] 하이브리드 복호화 성공: \(messageId) (SelfKey: \(isSelfKey))")
                } else {
                    print("✅ [ChatRoomViewModel] 기존 RSA-OAEP 복호화 성공: \(messageId)")
                }
                #endif
                
                return decryptedContent
            } catch {
                #if DEBUG
                print("❌ [ChatRoomViewModel] 메시지 복호화 실패: \(error)")
                #endif
                // 복호화 실패 시에도 "[암호화된 메시지]" 표시를 위해 빈 문자열 저장하지 않음
                return nil
            }
        }.value
        
        // UI 업데이트는 MainActor에서 (이미 @MainActor 클래스이므로 자동으로 MainActor에서 실행)
        decryptingMessageIds.remove(messageId)
        
        if let decryptedContent = result {
            saveDecryptedMessage(messageId: messageId, content: decryptedContent)
            #if DEBUG
            print("✅ [ChatRoomViewModel] 메시지 복호화 완료 및 저장: \(messageId)")
            #endif
        }
    }
    
    // MARK: - 메시지 표시 내용 가져오기

    func getDisplayContent(for message: Message) -> String {
        // 복호화된 내용이 있으면 반환
        if let decrypted = decryptedMessages[message.id] {
            return decrypted
        }
        
        // 복호화된 내용이 없으면 원본 메시지의 displayContent 반환
        // (그룹 채팅의 경우 content가 있으면 그대로 반환, 1:1 채팅의 경우 "[암호화된 메시지]" 반환)
        if message.encryptedContent != nil {
            // 아직 복호화되지 않았고, 복호화 시도 중이 아니면 복호화 시작 (Lazy Decryption)
            if !decryptingMessageIds.contains(message.id) {
                decryptingMessageIds.insert(message.id)
                #if DEBUG
                print("🔄 [getDisplayContent] Lazy Decryption 시작: \(message.id)")
                #endif
                
                Task {
                    if message.isFromCurrentUser {
                        // 내가 보낸 메시지
                        if let selfEncryptedSessionKey = message.selfEncryptedSessionKey {
                            await decryptMessage(
                                messageId: message.id,
                                encryptedContent: message.encryptedContent!,
                                encryptedSessionKey: selfEncryptedSessionKey,
                                isSelfKey: true
                            )
                        } else {
                            // selfEncryptedSessionKey가 없으면 복호화 불가 (이전 버전 호환성 등)
                            // 로컬 저장소에서 원본 찾기 시도
                            if let originalContent = sentMessageContents[message.encryptedContent!] {
                                saveDecryptedMessage(messageId: message.id, content: originalContent)
                            } else if let savedContent = loadSentMessageContent(messageId: message.id) {
                                saveDecryptedMessage(messageId: message.id, content: savedContent)
                            } else {
                                #if DEBUG
                                print("⚠️ [ChatRoomViewModel] 내가 보낸 메시지 복호화 불가 (키 없음): \(message.id)")
                                #endif
                                // 잘못된 키(encryptedSessionKey)로 시도하지 않음
                            }
                        }
                    } else {
                        // 상대방이 보낸 메시지
                        await decryptMessage(
                            messageId: message.id,
                            encryptedContent: message.encryptedContent!,
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
    
    // MARK: - 복호화 재시도 (수동)
    func retryDecryption() async {
        #if DEBUG
        print("🔄 [ChatRoomViewModel] 수동 복호화 재시도")
        #endif
        decryptingMessageIds.removeAll()
        await decryptMessages()
    }
    
    // MARK: - 사용자 공개키 가져오기

    private func fetchUserPublicKey(userId: String) async throws -> String {
        return try await NetworkManager.shared.userService.getUserPublicKey(userId: userId)
    }
    
    // MARK: - 수신자 공개키 미리 로드
    
    private func preloadRecipientPublicKey() async {
        guard let currentUserId = CurrentUser.shared.id,
              let otherMember = room?.members.first(where: { $0.user.id != currentUserId }) else {
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
            print("✅ [ChatRoomViewModel] 수신자 공개키 미리 로드 완료: \(otherMember.user.id)")
            #endif
        } catch {
            #if DEBUG
            print("⚠️ [ChatRoomViewModel] 수신자 공개키 미리 로드 실패: \(error)")
            #endif
            // 실패해도 계속 진행 (메시지 전송 시 다시 시도)
        }
    }
    
    // MARK: - 이미지 전송
    
    func sendImage(_ image: UIImage) async {
        #if DEBUG
        print("📸 [ChatRoomViewModel] 이미지 전송 시작")
        #endif
        
        // 임시 메시지 ID 생성
        let tempMessageId = "temp_\(Date().timeIntervalSince1970)_\(UUID().uuidString.prefix(8))"
        
        do {
            // 1. 이미지 업로드
            let asset = try await fileUploadService.uploadImage(image, folder: "chat")
            
            #if DEBUG
            print("✅ [ChatRoomViewModel] 이미지 업로드 성공 - Asset ID: \(asset.id)")
            #endif
            
            // 2. 임시 메시지 생성 (낙관적 업데이트)
            if let currentUserId = CurrentUser.shared.id,
               let currentUserName = CurrentUser.shared.name {
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
                
                let tempMessage = Message(
                    id: tempMessageId,
                    room: roomId,
                    sender: currentUser,
                    messageType: .image,
                    content: nil,
                    encryptedContent: nil,
                    encryptedSessionKey: nil,
                    selfEncryptedSessionKey: nil,
                    asset: asset,
                    replyTo: nil,
                    isRead: false,
                    createdAt: now,
                    updatedAt: now
                )
                
                // 메시지 목록에 즉시 추가
                messages.append(tempMessage)
                messageSendStatus[tempMessageId] = .sending
                
                #if DEBUG
                print("💬 [ChatRoomViewModel] 임시 이미지 메시지 생성 - ID: \(tempMessageId)")
                #endif
            }
            
            // 3. WebSocket으로 이미지 메시지 전송
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
            
            #if DEBUG
            print("📦 [ChatRoomViewModel] WebSocket 메시지 생성 완료")
            print("   type: \(outgoingMessage.type)")
            print("   messageType: \(outgoingMessage.messageType ?? "nil")")
            print("   assetId: \(outgoingMessage.assetId ?? "nil")")
            print("   Asset ID 원본: \(asset.id)")
            print("   Asset URL: \(asset.url)")
            #endif
            
            // WebSocket 연결 확인
            guard wsManager.isConnected else {
                #if DEBUG
                print("❌ [ChatRoomViewModel] WebSocket이 연결되지 않아 이미지 전송 실패")
                #endif
                errorMessage = "WebSocket 연결이 끊어져 이미지를 전송할 수 없습니다."
                showError = true
                
                // 임시 메시지 제거
                messages.removeAll { $0.id == tempMessageId }
                messageSendStatus.removeValue(forKey: tempMessageId)
                return
            }
            
            wsManager.sendMessage(outgoingMessage)
            
            // 메시지 캐시 무효화 (백그라운드)
            Task {
                await apiService.invalidateMessageCache(for: roomId)
            }
            
            #if DEBUG
            print("✅ [ChatRoomViewModel] 이미지 메시지 전송 완료")
            #endif
            
        } catch {
            #if DEBUG
            print("❌ [ChatRoomViewModel] 이미지 전송 실패: \(error)")
            #endif
            
            // 임시 메시지 제거
            messages.removeAll { $0.id == tempMessageId }
            messageSendStatus.removeValue(forKey: tempMessageId)
            
            errorMessage = "이미지 전송에 실패했습니다: \(error.localizedDescription)"
            showError = true
        }
    }
    
    // MARK: - 파일 전송
    
    func sendFile(url: URL) async {
        #if DEBUG
        print("📎 [ChatRoomViewModel] 파일 전송 시작")
        #endif
        
        // 임시 메시지 ID 생성
        let tempMessageId = "temp_\(Date().timeIntervalSince1970)_\(UUID().uuidString.prefix(8))"
        
        do {
            // 1. 파일 데이터 읽기
            let fileData = try Data(contentsOf: url)
            let fileName = url.lastPathComponent
            let contentType = url.mimeType ?? "application/octet-stream"
            
            #if DEBUG
            print("📄 [ChatRoomViewModel] 파일 정보 - 이름: \(fileName), 크기: \(fileData.count) bytes")
            #endif
            
            // 2. 파일 업로드
            let asset = try await fileUploadService.uploadFile(
                data: fileData,
                fileName: fileName,
                contentType: contentType,
                folder: "chat"
            )
            
            #if DEBUG
            print("✅ [ChatRoomViewModel] 파일 업로드 성공 - Asset ID: \(asset.id)")
            #endif
            
            // 3. 임시 메시지 생성 (낙관적 업데이트)
            if let currentUserId = CurrentUser.shared.id,
               let currentUserName = CurrentUser.shared.name {
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
                
                let tempMessage = Message(
                    id: tempMessageId,
                    room: roomId,
                    sender: currentUser,
                    messageType: .file,
                    content: nil,
                    encryptedContent: nil,
                    encryptedSessionKey: nil,
                    selfEncryptedSessionKey: nil,
                    asset: asset,
                    replyTo: nil,
                    isRead: false,
                    createdAt: now,
                    updatedAt: now
                )
                
                // 메시지 목록에 즉시 추가
                messages.append(tempMessage)
                messageSendStatus[tempMessageId] = .sending
                
                #if DEBUG
                print("💬 [ChatRoomViewModel] 임시 파일 메시지 생성 - ID: \(tempMessageId)")
                #endif
            }
            
            // 4. WebSocket으로 파일 메시지 전송
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
            
            // WebSocket 연결 확인
            guard wsManager.isConnected else {
                #if DEBUG
                print("❌ [ChatRoomViewModel] WebSocket이 연결되지 않아 파일 전송 실패")
                #endif
                errorMessage = "WebSocket 연결이 끊어져 파일을 전송할 수 없습니다."
                showError = true
                
                // 임시 메시지 제거
                messages.removeAll { $0.id == tempMessageId }
                messageSendStatus.removeValue(forKey: tempMessageId)
                return
            }
            
            wsManager.sendMessage(outgoingMessage)
            
            // 메시지 캐시 무효화 (백그라운드)
            Task {
                await apiService.invalidateMessageCache(for: roomId)
            }
            
            #if DEBUG
            print("✅ [ChatRoomViewModel] 파일 메시지 전송 완료")
            #endif
            
        } catch {
            #if DEBUG
            print("❌ [ChatRoomViewModel] 파일 전송 실패: \(error)")
            #endif
            
            // 임시 메시지 제거
            messages.removeAll { $0.id == tempMessageId }
            messageSendStatus.removeValue(forKey: tempMessageId)
            
            errorMessage = "파일 전송에 실패했습니다: \(error.localizedDescription)"
            showError = true
        }
    }
    
    // MARK: - 로컬 저장소 헬퍼 메서드
    
    private func saveSentMessageContent(messageId: String, content: String) {
        var savedMessages = UserDefaults.standard.dictionary(forKey: sentMessagesStorageKey) as? [String: String] ?? [:]
        savedMessages[messageId] = content
        UserDefaults.standard.set(savedMessages, forKey: sentMessagesStorageKey)
    }
    
    private func loadSentMessageContent(messageId: String) -> String? {
        let savedMessages = UserDefaults.standard.dictionary(forKey: sentMessagesStorageKey) as? [String: String] ?? [:]
        return savedMessages[messageId]
    }
}
