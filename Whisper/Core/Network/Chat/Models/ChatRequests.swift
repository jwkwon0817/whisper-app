//
//  ChatRequests.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation

// MARK: - Create Direct Chat Request
struct CreateDirectChatRequest: Codable {
    let userId: String
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
    }
}

// MARK: - Create Group Chat Request
struct CreateGroupChatRequest: Codable {
    let name: String
    let description: String?
    let memberIds: [String]
    
    enum CodingKeys: String, CodingKey {
        case name
        case description
        case memberIds = "member_ids"
    }
}

// MARK: - Mark Messages Read Request
struct MarkMessagesReadRequest: Codable {
    let messageIds: [String]
    
    enum CodingKeys: String, CodingKey {
        case messageIds = "message_ids"
    }
}

// MARK: - Message List Response
struct MessageListResponse: Codable {
    let results: [Message]
    let page: Int
    let pageSize: Int
    let total: Int
    
    enum CodingKeys: String, CodingKey {
        case results
        case page
        case pageSize = "page_size"
        case total
    }
}

