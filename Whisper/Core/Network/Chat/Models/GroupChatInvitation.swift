//
//  GroupChatInvitation.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation

// MARK: - GroupChatInvitation Model
struct GroupChatInvitation: Identifiable, Codable {
    let id: String
    let room: ChatRoom
    let inviter: User
    let invitee: User
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
        case room
        case inviter
        case invitee
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

