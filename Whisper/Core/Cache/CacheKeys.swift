//
//  CacheKeys.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/24/25.
//

import Foundation

// MARK: - Cache Keys
/// 캐시 키를 관리하는 구조체
struct CacheKeys {
    // 채팅방 관련
    static func chatRooms() -> String { "chat_rooms" }
    static func chatRoom(roomId: String) -> String { "chat_room_\(roomId)" }
    static func messages(roomId: String, page: Int) -> String { "messages_\(roomId)_page_\(page)" }
    
    // 폴더 관련
    static func chatFolders() -> String { "chat_folders" }
    
    // 초대 관련
    static func chatInvitations() -> String { "chat_invitations" }
    
    // 사용자 관련
    static func user(userId: String) -> String { "user_\(userId)" }
    static func currentUser() -> String { "current_user" }
    
    // 친구 관련
    static func friends() -> String { "friends" }
    static func friendRequests() -> String { "friend_requests" }
}

// MARK: - Cache TTL
/// 캐시 TTL (Time To Live) 상수
struct CacheTTL {
    static let chatRooms: TimeInterval = 60 // 1분
    static let chatRoom: TimeInterval = 300 // 5분
    static let messages: TimeInterval = 300 // 5분
    static let chatFolders: TimeInterval = 300 // 5분
    static let chatInvitations: TimeInterval = 60 // 1분
    static let user: TimeInterval = 600 // 10분
    static let friends: TimeInterval = 300 // 5분
    static let friendRequests: TimeInterval = 60 // 1분
}

