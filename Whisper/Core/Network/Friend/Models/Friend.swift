//
//  Friend.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation

// MARK: - Friend Model
struct Friend: Identifiable, Codable {
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
    
    // 현재 사용자가 요청자인지 확인
    var isRequester: Bool {
        guard let currentUserId = CurrentUser.shared.id else { return false }
        return requester.id == currentUserId
    }
    
    // 상대방 사용자 반환
    var otherUser: User {
        isRequester ? receiver : requester
    }
}

