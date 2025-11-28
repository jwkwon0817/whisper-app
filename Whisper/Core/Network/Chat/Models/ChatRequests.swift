//
//  ChatRequests.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation

struct CreateDirectChatRequest: Codable {
    let userId: String
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
    }
}

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

struct MarkMessagesReadRequest: Codable {
    let messageIds: [String]
    
    enum CodingKeys: String, CodingKey {
        case messageIds = "message_ids"
    }
}

struct MessageListResponse: Codable {
    let results: [Message]
    let page: Int
    let pageSize: Int
    let total: Int
    let hasNext: Bool
    
    enum CodingKeys: String, CodingKey {
        case results
        case page
        case pageSize = "page_size"
        case total
        case hasNext = "has_next"
    }
}

