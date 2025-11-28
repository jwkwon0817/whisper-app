//
//  CacheKeys.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/24/25.
//

import Foundation

struct CacheKeys {
    static func chatRooms() -> String { "chat_rooms" }
    static func chatRoom(roomId: String) -> String { "chat_room_\(roomId)" }
    static func messages(roomId: String, page: Int) -> String { "messages_\(roomId)_page_\(page)" }
    
    static func chatFolders() -> String { "chat_folders" }
    
    static func chatInvitations() -> String { "chat_invitations" }
    
    static func user(userId: String) -> String { "user_\(userId)" }
    static func currentUser() -> String { "current_user" }
    
    static func friends() -> String { "friends" }
    static func friendRequests() -> String { "friend_requests" }
}

struct CacheTTL {
    static let chatRooms: TimeInterval = 60
    static let chatRoom: TimeInterval = 300
    static let messages: TimeInterval = 300
    static let chatFolders: TimeInterval = 300
    static let chatInvitations: TimeInterval = 60
    static let user: TimeInterval = 600
    static let friends: TimeInterval = 60
    static let friendRequests: TimeInterval = 60
}

