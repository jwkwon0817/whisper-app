//
//  ChatService.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation
import Moya

class ChatService: BaseService<ChatAPI> {
    private let cacheManager = CacheManager.shared
    
    func invalidateMessageCache(for roomId: String) async {
        await cacheManager.remove(keysMatching: "messages_\(roomId)")
    }
    
    func invalidateRoomListCache() async {
        await cacheManager.remove(forKey: CacheKeys.chatRooms())
    }
    
    func fetchChatRooms(useCache: Bool = true) async throws -> [ChatRoom] {
        if useCache, let cached = await cacheManager.get([ChatRoom].self, forKey: CacheKeys.chatRooms()) {
            _Concurrency.Task {
                do {
                    let fresh = try await request(.fetchChatRooms, as: [ChatRoom].self)
                    await cacheManager.set(fresh, forKey: CacheKeys.chatRooms(), ttl: CacheTTL.chatRooms)
                } catch {
                }
            }
            return cached
        }
        
        let rooms = try await request(.fetchChatRooms, as: [ChatRoom].self)
        await cacheManager.set(rooms, forKey: CacheKeys.chatRooms(), ttl: CacheTTL.chatRooms)
        return rooms
    }
    
    func createDirectChat(userId: String) async throws -> DirectChatInvitation {
        return try await request(.createDirectChat(userId: userId), as: DirectChatInvitation.self)
    }
    
    func createGroupChat(name: String, description: String?, memberIds: [String]) async throws -> ChatRoom {
        return try await request(.createGroupChat(name: name, description: description, memberIds: memberIds), as: ChatRoom.self)
    }
    
    func fetchChatRoomDetail(roomId: String) async throws -> ChatRoom {
        return try await request(.fetchChatRoomDetail(roomId: roomId), as: ChatRoom.self)
    }
    
    func fetchMessages(roomId: String, page: Int = 1, pageSize: Int = 50, useCache: Bool = true) async throws -> MessageListResponse {
        let cacheKey = CacheKeys.messages(roomId: roomId, page: page)
        
        if useCache && page == 1, let cached = await cacheManager.get(MessageListResponse.self, forKey: cacheKey) {
            _Concurrency.Task {
                do {
                    let fresh = try await request(.fetchMessages(roomId: roomId, page: page, pageSize: pageSize), as: MessageListResponse.self)
                    await cacheManager.set(fresh, forKey: cacheKey, ttl: CacheTTL.messages)
                } catch {
                }
            }
            return cached
        }
        
        let response = try await request(.fetchMessages(roomId: roomId, page: page, pageSize: pageSize), as: MessageListResponse.self)
        
        if page == 1 {
            await cacheManager.set(response, forKey: cacheKey, ttl: CacheTTL.messages)
        }
        
        return response
    }
    
    func markMessagesAsRead(roomId: String, messageIds: [String]) async throws {
        _ = try await request(.markMessagesAsRead(roomId: roomId, messageIds: messageIds), as: EmptyResponse.self)
    }
    
    func updateMessage(roomId: String, messageId: String, content: String?, encryptedContent: String?, encryptedSessionKey: String? = nil, selfEncryptedSessionKey: String? = nil) async throws -> Message {
        return try await request(.updateMessage(roomId: roomId, messageId: messageId, content: content, encryptedContent: encryptedContent, encryptedSessionKey: encryptedSessionKey, selfEncryptedSessionKey: selfEncryptedSessionKey), as: Message.self)
    }
    
    func deleteMessage(roomId: String, messageId: String) async throws {
        _ = try await request(.deleteMessage(roomId: roomId, messageId: messageId), as: EmptyResponse.self)
    }
    
    func leaveChatRoom(roomId: String) async throws {
        _ = try await request(.leaveChatRoom(roomId: roomId), as: EmptyResponse.self)
    }
    
    func fetchAllChatInvitations(useCache: Bool = true) async throws -> [ChatInvitation] {
        if useCache, let cached = await cacheManager.get([ChatInvitation].self, forKey: CacheKeys.chatInvitations()) {
            _Concurrency.Task {
                do {
                    let response = try await request(.fetchAllChatInvitations, as: ChatInvitationListResponse.self)
                    await cacheManager.set(response.results, forKey: CacheKeys.chatInvitations(), ttl: CacheTTL.chatInvitations)
                } catch {}
            }
            return cached
        }
        
        let response = try await request(.fetchAllChatInvitations, as: ChatInvitationListResponse.self)
        await cacheManager.set(response.results, forKey: CacheKeys.chatInvitations(), ttl: CacheTTL.chatInvitations)
        return response.results
    }
    
    func respondToDirectChatInvitation(invitationId: String, action: String) async throws -> ChatRoom? {
        if action == "accept" {
            return try await request(.respondToDirectChatInvitation(invitationId: invitationId, action: action), as: ChatRoom.self)
        } else {
            _ = try await request(.respondToDirectChatInvitation(invitationId: invitationId, action: action), as: DirectChatInvitation.self)
            return nil
        }
    }
    
    func respondToGroupChatInvitation(invitationId: String, action: String) async throws -> GroupChatInvitation {
        return try await request(.respondToGroupChatInvitation(invitationId: invitationId, action: action), as: GroupChatInvitation.self)
    }
    
    func fetchChatFolders(useCache: Bool = true) async throws -> [ChatFolder] {
        if useCache, let cached = await cacheManager.get([ChatFolder].self, forKey: CacheKeys.chatFolders()) {
            _Concurrency.Task {
                do {
                    let fresh = try await request(.fetchChatFolders, as: [ChatFolder].self)
                    await cacheManager.set(fresh, forKey: CacheKeys.chatFolders(), ttl: CacheTTL.chatFolders)
                } catch {}
            }
            return cached
        }
        
        let folders = try await request(.fetchChatFolders, as: [ChatFolder].self)
        await cacheManager.set(folders, forKey: CacheKeys.chatFolders(), ttl: CacheTTL.chatFolders)
        return folders
    }
    
    func createChatFolder(name: String, color: String = "#000000", icon: String = "folder.fill") async throws -> ChatFolder {
        let result = try await request(.createChatFolder(name: name, color: color, icon: icon), as: ChatFolder.self)
        await cacheManager.remove(forKey: CacheKeys.chatFolders()) // 목록 캐시 무효화
        return result
    }
    
    func deleteChatFolder(folderId: String) async throws {
        _ = try await request(.deleteChatFolder(folderId: folderId), as: EmptyResponse.self)
        await cacheManager.remove(forKey: CacheKeys.chatFolders()) // 목록 캐시 무효화
    }
    
    func addRoomToFolder(folderId: String, roomId: String) async throws {
        _ = try await request(.addRoomToFolder(folderId: folderId, roomId: roomId), as: EmptyResponse.self)
        await cacheManager.remove(forKey: CacheKeys.chatRooms())
        await cacheManager.remove(forKey: CacheKeys.chatFolders())
    }
    
    func removeRoomFromFolder(folderId: String, roomId: String) async throws {
        _ = try await request(.removeRoomFromFolder(folderId: folderId, roomId: roomId), as: EmptyResponse.self)
        await cacheManager.remove(forKey: CacheKeys.chatRooms())
        await cacheManager.remove(forKey: CacheKeys.chatFolders())
    }
}

struct EmptyResponse: Codable {}

