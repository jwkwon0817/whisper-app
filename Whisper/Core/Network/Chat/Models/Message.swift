//
//  Message.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation

struct Message: Identifiable, Codable, Equatable {
    let id: String
    let room: String
    let sender: User
    let messageType: MessageType
    let content: String?
    let encryptedContent: String?
    let encryptedSessionKey: String?
    let selfEncryptedSessionKey: String?
    let asset: Asset?
    let replyTo: ReplyToMessage?
    let isRead: Bool
    let createdAt: String
    let updatedAt: String
    
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
    
    var isFromCurrentUser: Bool {
        guard let currentUserId = CurrentUser.shared.id else { return false }
        return sender.id == currentUserId
    }
    
    var displayContent: String {
        if let content = content, !content.isEmpty {
            return content
        }
        if encryptedContent != nil {
            return "[암호화된 메시지]"
        }
        return ""
    }
    
    var isHybridEncrypted: Bool {
        return encryptedSessionKey != nil
    }
    
    var isLegacyEncrypted: Bool {
        return encryptedContent != nil && encryptedSessionKey == nil
    }
    
    var createdAtDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: createdAt) ?? formatter.date(from: createdAt.replacingOccurrences(of: "\\.\\d+", with: "", options: .regularExpression))
    }
    
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
