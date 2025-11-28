//
//  DirectChatInvitation.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/24/25.
//

import Foundation

// MARK: - DirectChatInvitation Model
struct DirectChatInvitation: Identifiable, Codable {
    let id: String
    let roomType: String
    let inviter: User
    let invitee: User
    let members: [User]
    let status: InvitationStatus
    let createdAt: String
    let updatedAt: String
    
    enum InvitationStatus: String, Codable {
        case pending = "pending"
        case accepted = "accepted"
        case rejected = "rejected"
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case roomType = "room_type"
        case inviter
        case invitee
        case members
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - ChatInvitation (통합 모델)
struct ChatInvitation: Identifiable, Codable {
    let id: String
    let type: InvitationType
    let inviter: User
    let invitee: User
    let room: ChatRoom?  // 1:1 채팅은 room이 없음
    let status: InvitationStatus
    let createdAt: String
    let updatedAt: String
    
    enum InvitationType: String, Codable {
        case direct = "direct"
        case group = "group"
    }
    
    enum InvitationStatus: String, Codable {
        case pending = "pending"
        case accepted = "accepted"
        case rejected = "rejected"
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case type
        case inviter
        case invitee
        case room
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Invitation Response Request
struct InvitationResponseRequest: Codable {
    let action: String  // "accept" or "reject"
}
