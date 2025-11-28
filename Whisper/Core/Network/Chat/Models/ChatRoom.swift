//
//  ChatRoom.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation

struct ChatRoom: Identifiable, Codable {
    let id: String
    let roomType: RoomType
    let name: String?
    let description: String?
    let createdBy: User?
    let members: [ChatRoomMember]
    let memberCount: Int
    let lastMessage: Message?
    let folderIds: [String]
    let unreadCount: Int
    let createdAt: String
    let updatedAt: String
    
    enum RoomType: String, Codable {
        case direct = "direct"
        case group = "group"
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case roomType = "room_type"
        case name
        case description
        case createdBy = "created_by"
        case members
        case memberCount = "member_count"
        case lastMessage = "last_message"
        case folderIds = "folder_ids"
        case unreadCount = "unread_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    var displayName: String {
        if roomType == .direct {
            if let currentUserId = CurrentUser.shared.id,
               let otherMember = members.first(where: { $0.user.id != currentUserId }) {
                return otherMember.user.name
            }
            if let firstMember = members.first {
                return firstMember.user.name
            }
        }
        return name ?? "채팅방"
    }
    
    var lastMessagePreview: String {
        guard let message = lastMessage else { return "" }
        switch message.messageType {
        case .text:
            return message.content ?? "[암호화된 메시지]"
        case .image:
            return "📷 사진"
        case .file:
            return "📎 파일"
        case .system:
            return message.content ?? ""
        }
    }
    
    var updatedAtDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: updatedAt) ?? formatter.date(from: updatedAt.replacingOccurrences(of: "\\.\\d+", with: "", options: .regularExpression))
    }
}

struct ChatRoomMember: Identifiable, Codable {
    let id: String
    let user: User
    let role: MemberRole
    let nickname: String?
    let joinedAt: String
    let lastReadAt: String?
    
    enum MemberRole: String, Codable {
        case owner = "owner"
        case admin = "admin"
        case member = "member"
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case user
        case role
        case nickname
        case joinedAt = "joined_at"
        case lastReadAt = "last_read_at"
    }
}

