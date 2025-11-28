//
//  Message.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation

// MARK: - Message Model
struct Message: Identifiable, Codable, Equatable {
    let id: String
    let room: String
    let sender: User
    let messageType: MessageType
    let content: String?  // 그룹 채팅용 평문
    let encryptedContent: String?  // 1:1 채팅용 암호화된 내용 (AES 암호화된 메시지)
    let encryptedSessionKey: String?  // 1:1 채팅용 암호화된 세션 키 (RSA 암호화된 AES 키) - 상대방 공개키로 암호화
    let selfEncryptedSessionKey: String?  // 1:1 채팅용 암호화된 세션 키 (RSA 암호화된 AES 키) - 내 공개키로 암호화 (양방향 복호화용)
    let asset: Asset?
    let replyTo: ReplyToMessage?
    let isRead: Bool
    let createdAt: String
    let updatedAt: String
    
    // MARK: - Equatable
    // 뷰 리렌더링 최적화를 위한 Equatable 구현
    // 메시지 내용이 변경되지 않았다면 뷰를 다시 그리지 않음
    static func == (lhs: Message, rhs: Message) -> Bool {
        lhs.id == rhs.id &&
        lhs.isRead == rhs.isRead &&
        lhs.content == rhs.content &&
        lhs.encryptedContent == rhs.encryptedContent &&
        lhs.updatedAt == rhs.updatedAt
    }
    
    enum MessageType: String, Codable {
        case text = "text"
        case image = "image"
        case file = "file"
        case system = "system"
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case room
        case sender
        case messageType = "message_type"
        case content
        case encryptedContent = "encrypted_content"
        case encryptedSessionKey = "encrypted_session_key"
        case selfEncryptedSessionKey = "self_encrypted_session_key"
        case asset
        case replyTo = "reply_to"
        case isRead = "is_read"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    // 현재 사용자가 보낸 메시지인지 확인
    var isFromCurrentUser: Bool {
        guard let currentUserId = CurrentUser.shared.id else { return false }
        return sender.id == currentUserId
    }
    
    // 표시할 메시지 내용 (복호화 필요 시 처리)
    // 주의: 이 메서드는 ViewModel의 getDisplayContent를 통해 사용되어야 함
    // 직접 사용하면 "[암호화된 메시지]"가 반환될 수 있음
    var displayContent: String {
        if let content = content, !content.isEmpty {
            return content
        }
        if encryptedContent != nil {
            return "[암호화된 메시지]"  // ViewModel.getDisplayContent를 통해 복호화된 내용이 제공됨
        }
        return ""
    }
    
    // 하이브리드 암호화 방식인지 확인 (encrypted_session_key가 있으면 하이브리드)
    var isHybridEncrypted: Bool {
        return encryptedSessionKey != nil
    }
    
    // 기존 RSA-OAEP 방식인지 확인 (encrypted_content는 있지만 encrypted_session_key가 없으면 기존 방식)
    var isLegacyEncrypted: Bool {
        return encryptedContent != nil && encryptedSessionKey == nil
    }
    
    var createdAtDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: createdAt) ?? formatter.date(from: createdAt.replacingOccurrences(of: "\\.\\d+", with: "", options: .regularExpression))
    }
    
    // 읽음 상태를 업데이트한 새 메시지 인스턴스 생성
    func withReadStatus(_ isRead: Bool) -> Message {
        Message(
            id: self.id,
            room: self.room,
            sender: self.sender,
            messageType: self.messageType,
            content: self.content,
            encryptedContent: self.encryptedContent,
            encryptedSessionKey: self.encryptedSessionKey,
            selfEncryptedSessionKey: self.selfEncryptedSessionKey,
            asset: self.asset,
            replyTo: self.replyTo,
            isRead: isRead,
            createdAt: self.createdAt,
            updatedAt: self.updatedAt
        )
    }
}

// MARK: - ReplyToMessage Model
struct ReplyToMessage: Codable, Equatable {
    let id: String
    let sender: User
    let content: String
    let messageType: Message.MessageType
    
    enum CodingKeys: String, CodingKey {
        case id
        case sender
        case content
        case messageType = "message_type"
    }
    
    static func == (lhs: ReplyToMessage, rhs: ReplyToMessage) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Asset Model
struct Asset: Identifiable, Codable, Equatable {
    let id: String
    let url: String
    let fileName: String?
    let fileSize: Int?
    let contentType: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case url
        case fileName = "file_name"
        case fileSize = "file_size"
        case contentType = "content_type"
    }
    
    static func == (lhs: Asset, rhs: Asset) -> Bool {
        lhs.id == rhs.id
    }
}
