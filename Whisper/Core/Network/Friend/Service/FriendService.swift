//
//  FriendService.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation
import Moya

class FriendService: BaseService<FriendAPI> {
    // MARK: - 친구 요청 보내기
    func sendFriendRequest(phoneNumber: String) async throws {
        // 서버가 Friend 객체를 반환할 수도 있고, 빈 응답을 반환할 수도 있음
        // 일단 EmptyResponse로 처리하고, 필요시 Friend로 변경 가능
        _ = try await request(.sendFriendRequest(phoneNumber: phoneNumber), as: EmptyResponse.self)
    }
    
    // MARK: - 친구 목록 조회
    func fetchFriends() async throws -> [Friend] {
        return try await request(.fetchFriends, as: [Friend].self)
    }
    
    // MARK: - 받은 친구 요청 목록 조회
    func fetchReceivedFriendRequests() async throws -> [Friend] {
        return try await request(.fetchReceivedFriendRequests, as: [Friend].self)
    }
    
    // MARK: - 친구 요청 수락/거절
    func respondToFriendRequest(friendId: String, action: String) async throws -> Friend {
        return try await request(.respondToFriendRequest(friendId: friendId, action: action), as: Friend.self)
    }
    
    // MARK: - 친구 삭제
    func deleteFriend(friendId: String) async throws {
        _ = try await request(.deleteFriend(friendId: friendId), as: EmptyResponse.self)
    }
}

