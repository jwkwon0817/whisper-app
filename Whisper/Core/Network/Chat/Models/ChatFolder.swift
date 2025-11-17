//
//  ChatFolder.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation

// MARK: - ChatFolder Model
struct ChatFolder: Identifiable, Codable {
    let id: String
    let name: String
    let color: String
    let order: Int
    let roomCount: Int
    let createdAt: String
    let updatedAt: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case color
        case order
        case roomCount = "room_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - ChatFolderRoom Model
struct ChatFolderRoom: Identifiable, Codable {
    let id: String
    let folder: String
    let room: ChatRoom
    let order: Int
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case folder
        case room
        case order
        case createdAt = "created_at"
    }
}

