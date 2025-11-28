//
//  Friend.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation

struct Friend: Identifiable, Codable, Hashable {
    let id: String
    let requester: User
    let receiver: User
    let status: FriendStatus
    let createdAt: String
    let updatedAt: String
    
    enum FriendStatus: String, Codable {
        case pending = "pending"
        case accepted = "accepted"
        case rejected = "rejected"
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case requester
        case receiver
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    var isRequester: Bool {
        guard let currentUserId = CurrentUser.shared.id else { return false }
        return requester.id == currentUserId
    }
    
    var otherUser: User {
        isRequester ? receiver : requester
    }
}

