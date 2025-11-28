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
    private let optimisticManager = OptimisticUpdateManager.shared
    
    // MARK: - 캐시 관리
    
    /// 특정 채팅방의 메시지 캐시 무효화
    func invalidateMessageCache(for roomId: String) async {
        await cacheManager.remove(keysMatching: "messages_\(roomId)")
    }
    
    /// 채팅방 목록 캐시 무효화
    func invalidateRoomListCache() async {
        await cacheManager.remove(forKey: CacheKeys.chatRooms())
    }
    
    // MARK: - 채팅방 목록 조회
    func fetchChatRooms(useCache: Bool = true) async throws -> [ChatRoom] {
        // 캐시에서 먼저 확인
        if useCache, let cached = await cacheManager.get([ChatRoom].self, forKey: CacheKeys.chatRooms()) {
            // 백그라운드에서 최신 데이터 가져오기
            _Concurrency.Task {
                do {
                    let fresh = try await request(.fetchChatRooms, as: [ChatRoom].self)
                    await cacheManager.set(fresh, forKey: CacheKeys.chatRooms(), ttl: CacheTTL.chatRooms)
                } catch {
                    // 캐시 업데이트 실패는 무시 (이미 캐시된 데이터가 있음)
                }
            }
            return cached
        }
        
        // 캐시가 없거나 사용하지 않는 경우 API 호출
        let rooms = try await request(.fetchChatRooms, as: [ChatRoom].self)
        await cacheManager.set(rooms, forKey: CacheKeys.chatRooms(), ttl: CacheTTL.chatRooms)
        return rooms
    }
    
    // MARK: - 1:1 채팅 생성
    func createDirectChat(userId: String) async throws -> DirectChatInvitation {
        return try await request(.createDirectChat(userId: userId), as: DirectChatInvitation.self)
    }
    
    // MARK: - 그룹 채팅 생성
    func createGroupChat(name: String, description: String?, memberIds: [String]) async throws -> ChatRoom {
        return try await request(.createGroupChat(name: name, description: description, memberIds: memberIds), as: ChatRoom.self)
    }
    
    // MARK: - 채팅방 상세 조회
    func fetchChatRoomDetail(roomId: String) async throws -> ChatRoom {
        return try await request(.fetchChatRoomDetail(roomId: roomId), as: ChatRoom.self)
    }
    
    // MARK: - 메시지 목록 조회
    func fetchMessages(roomId: String, page: Int = 1, pageSize: Int = 50, useCache: Bool = true) async throws -> MessageListResponse {
        let cacheKey = CacheKeys.messages(roomId: roomId, page: page)
        
        // 첫 페이지만 캐싱 (이전 페이지는 무한 스크롤이므로 캐싱하지 않음)
        if useCache && page == 1, let cached = await cacheManager.get(MessageListResponse.self, forKey: cacheKey) {
            // 백그라운드에서 최신 데이터 가져오기
            _Concurrency.Task {
                do {
                    let fresh = try await request(.fetchMessages(roomId: roomId, page: page, pageSize: pageSize), as: MessageListResponse.self)
                    await cacheManager.set(fresh, forKey: cacheKey, ttl: CacheTTL.messages)
                } catch {
                    // 캐시 업데이트 실패는 무시
                }
            }
            return cached
        }
        
        let response = try await request(.fetchMessages(roomId: roomId, page: page, pageSize: pageSize), as: MessageListResponse.self)
        
        // 첫 페이지만 캐싱
        if page == 1 {
            await cacheManager.set(response, forKey: cacheKey, ttl: CacheTTL.messages)
        }
        
        return response
    }
    
    // MARK: - 메시지 읽음 처리
    func markMessagesAsRead(roomId: String, messageIds: [String]) async throws {
        _ = try await request(.markMessagesAsRead(roomId: roomId, messageIds: messageIds), as: EmptyResponse.self)
    }
    
    // MARK: - 메시지 수정
    func updateMessage(roomId: String, messageId: String, content: String?, encryptedContent: String?, encryptedSessionKey: String? = nil, selfEncryptedSessionKey: String? = nil) async throws -> Message {
        return try await request(.updateMessage(roomId: roomId, messageId: messageId, content: content, encryptedContent: encryptedContent, encryptedSessionKey: encryptedSessionKey, selfEncryptedSessionKey: selfEncryptedSessionKey), as: Message.self)
    }
    
    // MARK: - 메시지 삭제
    func deleteMessage(roomId: String, messageId: String) async throws {
        _ = try await request(.deleteMessage(roomId: roomId, messageId: messageId), as: EmptyResponse.self)
    }
    
    // MARK: - 채팅방 나가기
    func leaveChatRoom(roomId: String) async throws {
        _ = try await request(.leaveChatRoom(roomId: roomId), as: EmptyResponse.self)
    }
    
    // MARK: - 채팅방 정보 수정
    func updateChatRoom(roomId: String, name: String?, description: String?) async throws -> ChatRoom {
        let result = try await request(.updateChatRoom(roomId: roomId, name: name, description: description), as: ChatRoom.self)
        
        // 캐시 업데이트
        await cacheManager.set(result, forKey: CacheKeys.chatRoom(roomId: roomId), ttl: CacheTTL.chatRoom)
        await cacheManager.remove(forKey: CacheKeys.chatRooms()) // 목록 캐시 무효화
        
        return result
    }
    
    // MARK: - 채팅방 멤버 추가
    func addChatRoomMembers(roomId: String, userIds: [String]) async throws {
        _ = try await request(.addChatRoomMembers(roomId: roomId, userIds: userIds), as: EmptyResponse.self)
    }
    
    // MARK: - 채팅방 멤버 제거
    func removeChatRoomMember(roomId: String, userId: String) async throws {
        _ = try await request(.removeChatRoomMember(roomId: roomId, userId: userId), as: EmptyResponse.self)
    }
    
    // MARK: - 그룹챗 초대 보내기
    func sendGroupChatInvitation(roomId: String, userId: String) async throws -> GroupChatInvitation {
        return try await request(.sendGroupChatInvitation(roomId: roomId, userId: userId), as: GroupChatInvitation.self)
    }
    
    // MARK: - 받은 모든 채팅 초대 목록 조회 (1:1 + 그룹)
    func fetchAllChatInvitations(useCache: Bool = true) async throws -> [ChatInvitation] {
        if useCache, let cached = await cacheManager.get([ChatInvitation].self, forKey: CacheKeys.chatInvitations()) {
            _Concurrency.Task {
                do {
                    let fresh = try await request(.fetchAllChatInvitations, as: [ChatInvitation].self)
                    await cacheManager.set(fresh, forKey: CacheKeys.chatInvitations(), ttl: CacheTTL.chatInvitations)
                } catch {}
            }
            return cached
        }
        
        let invitations = try await request(.fetchAllChatInvitations, as: [ChatInvitation].self)
        await cacheManager.set(invitations, forKey: CacheKeys.chatInvitations(), ttl: CacheTTL.chatInvitations)
        return invitations
    }
    
    // MARK: - 받은 1:1 채팅 초대 목록 조회
    func fetchDirectChatInvitations() async throws -> [DirectChatInvitation] {
        return try await request(.fetchDirectChatInvitations, as: [DirectChatInvitation].self)
    }
    
    // MARK: - 받은 그룹챗 초대 목록 조회
    func fetchGroupChatInvitations() async throws -> [GroupChatInvitation] {
        return try await request(.fetchGroupChatInvitations, as: [GroupChatInvitation].self)
    }
    
    // MARK: - 1:1 채팅 초대 수락/거절
    func respondToDirectChatInvitation(invitationId: String, action: String) async throws -> ChatRoom? {
        if action == "accept" {
            return try await request(.respondToDirectChatInvitation(invitationId: invitationId, action: action), as: ChatRoom.self)
        } else {
            _ = try await request(.respondToDirectChatInvitation(invitationId: invitationId, action: action), as: DirectChatInvitation.self)
            return nil
        }
    }
    
    // MARK: - 그룹챗 초대 수락/거절
    func respondToGroupChatInvitation(invitationId: String, action: String) async throws -> GroupChatInvitation {
        return try await request(.respondToGroupChatInvitation(invitationId: invitationId, action: action), as: GroupChatInvitation.self)
    }
    
    // MARK: - 폴더 목록 조회
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
    
    // MARK: - 폴더 생성
    func createChatFolder(name: String, color: String = "#000000", icon: String = "folder.fill") async throws -> ChatFolder {
        let result = try await request(.createChatFolder(name: name, color: color, icon: icon), as: ChatFolder.self)
        await cacheManager.remove(forKey: CacheKeys.chatFolders()) // 목록 캐시 무효화
        return result
    }
    
    // MARK: - 폴더 수정
    func updateChatFolder(folderId: String, name: String?, color: String?, icon: String?) async throws -> ChatFolder {
        let result = try await request(.updateChatFolder(folderId: folderId, name: name, color: color, icon: icon), as: ChatFolder.self)
        await cacheManager.remove(forKey: CacheKeys.chatFolders()) // 목록 캐시 무효화
        return result
    }
    
    // MARK: - 폴더 삭제
    func deleteChatFolder(folderId: String) async throws {
        _ = try await request(.deleteChatFolder(folderId: folderId), as: EmptyResponse.self)
        await cacheManager.remove(forKey: CacheKeys.chatFolders()) // 목록 캐시 무효화
    }
    
    // MARK: - 폴더에 채팅방 추가
    func addRoomToFolder(folderId: String, roomId: String) async throws {
        _ = try await request(.addRoomToFolder(folderId: folderId, roomId: roomId), as: EmptyResponse.self)
        // 관련 캐시 무효화
        await cacheManager.remove(forKey: CacheKeys.chatRooms())
        await cacheManager.remove(forKey: CacheKeys.chatFolders())
    }
    
    // MARK: - 폴더에서 채팅방 제거
    func removeRoomFromFolder(folderId: String, roomId: String) async throws {
        _ = try await request(.removeRoomFromFolder(folderId: folderId, roomId: roomId), as: EmptyResponse.self)
        // 관련 캐시 무효화
        await cacheManager.remove(forKey: CacheKeys.chatRooms())
        await cacheManager.remove(forKey: CacheKeys.chatFolders())
    }
}

// MARK: - Empty Response
struct EmptyResponse: Codable {}

