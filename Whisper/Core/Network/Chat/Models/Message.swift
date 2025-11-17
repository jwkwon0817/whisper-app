//
//  Message.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation

// MARK: - Message Model
struct Message: Identifiable, Codable {
    let id: String
    let room: String
    let sender: User
    let messageType: MessageType
    let content: String?  // 그룹 채팅용 평문
    let encryptedContent: String?  // 1:1 채팅용 암호화된 내용
    let asset: Asset?
    let replyTo: ReplyToMessage?
    let isRead: Bool
    let createdAt: String
    let updatedAt: String
    
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
    var displayContent: String {
        if let content = content, !content.isEmpty {
            return content
        }
        if encryptedContent != nil {
            return "[암호화된 메시지]"  // 클라이언트에서 복호화 필요
        }
        return ""
    }
    
    var createdAtDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: createdAt) ?? formatter.date(from: createdAt.replacingOccurrences(of: "\\.\\d+", with: "", options: .regularExpression))
    }
}

// MARK: - ReplyToMessage Model
struct ReplyToMessage: Codable {
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
}

// MARK: - Asset Model
struct Asset: Identifiable, Codable {
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
}

