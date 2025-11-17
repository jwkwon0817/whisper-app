//
//  ChatService.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation
import Moya

class ChatService: BaseService<ChatAPI> {
    // MARK: - 채팅방 목록 조회
    func fetchChatRooms() async throws -> [ChatRoom] {
        return try await request(.fetchChatRooms, as: [ChatRoom].self)
    }
    
    // MARK: - 1:1 채팅 생성
    func createDirectChat(userId: String) async throws -> ChatRoom {
        return try await request(.createDirectChat(userId: userId), as: ChatRoom.self)
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
    func fetchMessages(roomId: String, page: Int = 1, pageSize: Int = 50) async throws -> MessageListResponse {
        return try await request(.fetchMessages(roomId: roomId, page: page, pageSize: pageSize), as: MessageListResponse.self)
    }
    
    // MARK: - 메시지 읽음 처리
    func markMessagesAsRead(roomId: String, messageIds: [String]) async throws {
        _ = try await request(.markMessagesAsRead(roomId: roomId, messageIds: messageIds), as: EmptyResponse.self)
    }
    
    // MARK: - 채팅방 나가기
    func leaveChatRoom(roomId: String) async throws {
        _ = try await request(.leaveChatRoom(roomId: roomId), as: EmptyResponse.self)
    }
    
    // MARK: - 채팅방 정보 수정
    func updateChatRoom(roomId: String, name: String?, description: String?) async throws -> ChatRoom {
        return try await request(.updateChatRoom(roomId: roomId, name: name, description: description), as: ChatRoom.self)
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
    
    // MARK: - 받은 그룹챗 초대 목록 조회
    func fetchGroupChatInvitations() async throws -> [GroupChatInvitation] {
        return try await request(.fetchGroupChatInvitations, as: [GroupChatInvitation].self)
    }
    
    // MARK: - 그룹챗 초대 수락/거절
    func respondToGroupChatInvitation(invitationId: String, action: String) async throws -> GroupChatInvitation {
        return try await request(.respondToGroupChatInvitation(invitationId: invitationId, action: action), as: GroupChatInvitation.self)
    }
    
    // MARK: - 폴더 목록 조회
    func fetchChatFolders() async throws -> [ChatFolder] {
        return try await request(.fetchChatFolders, as: [ChatFolder].self)
    }
    
    // MARK: - 폴더 생성
    func createChatFolder(name: String, color: String = "#000000") async throws -> ChatFolder {
        return try await request(.createChatFolder(name: name, color: color), as: ChatFolder.self)
    }
    
    // MARK: - 폴더 수정
    func updateChatFolder(folderId: String, name: String?, color: String?) async throws -> ChatFolder {
        return try await request(.updateChatFolder(folderId: folderId, name: name, color: color), as: ChatFolder.self)
    }
    
    // MARK: - 폴더 삭제
    func deleteChatFolder(folderId: String) async throws {
        _ = try await request(.deleteChatFolder(folderId: folderId), as: EmptyResponse.self)
    }
    
    // MARK: - 폴더에 채팅방 추가
    func addRoomToFolder(folderId: String, roomId: String) async throws {
        _ = try await request(.addRoomToFolder(folderId: folderId, roomId: roomId), as: EmptyResponse.self)
    }
    
    // MARK: - 폴더에서 채팅방 제거
    func removeRoomFromFolder(folderId: String, roomId: String) async throws {
        _ = try await request(.removeRoomFromFolder(folderId: folderId, roomId: roomId), as: EmptyResponse.self)
    }
}

// MARK: - Empty Response
struct EmptyResponse: Codable {}

