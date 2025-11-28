//
//  FriendService.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation
import Moya

class FriendService: BaseService<FriendAPI> {
    private let cacheManager = CacheManager.shared
    
    // MARK: - 친구 요청 보내기
    func sendFriendRequest(phoneNumber: String) async throws {
        _ = try await request(.sendFriendRequest(phoneNumber: phoneNumber), as: EmptyResponse.self)
        // 친구 요청 목록 캐시 무효화
        await cacheManager.remove(forKey: CacheKeys.friendRequests())
    }
    
    // MARK: - 친구 목록 조회
    func fetchFriends(useCache: Bool = true) async throws -> [Friend] {
        if useCache, let cached = await cacheManager.get([Friend].self, forKey: CacheKeys.friends()) {
            _Concurrency.Task {
                do {
                    let fresh = try await request(.fetchFriends, as: [Friend].self)
                    await cacheManager.set(fresh, forKey: CacheKeys.friends(), ttl: CacheTTL.friends)
                } catch {}
            }
            return cached
        }
        
        let friends = try await request(.fetchFriends, as: [Friend].self)
        await cacheManager.set(friends, forKey: CacheKeys.friends(), ttl: CacheTTL.friends)
        return friends
    }
    
    // MARK: - 받은 친구 요청 목록 조회
    func fetchReceivedFriendRequests(useCache: Bool = true) async throws -> [Friend] {
        if useCache, let cached = await cacheManager.get([Friend].self, forKey: CacheKeys.friendRequests()) {
            _Concurrency.Task {
                do {
                    let fresh = try await request(.fetchReceivedFriendRequests, as: [Friend].self)
                    await cacheManager.set(fresh, forKey: CacheKeys.friendRequests(), ttl: CacheTTL.friendRequests)
                } catch {}
            }
            return cached
        }
        
        let requests = try await request(.fetchReceivedFriendRequests, as: [Friend].self)
        await cacheManager.set(requests, forKey: CacheKeys.friendRequests(), ttl: CacheTTL.friendRequests)
        return requests
    }
    
    // MARK: - 친구 요청 수락/거절
    func respondToFriendRequest(friendId: String, action: String) async throws -> Friend {
        let result = try await request(.respondToFriendRequest(friendId: friendId, action: action), as: Friend.self)
        // 관련 캐시 무효화
        await cacheManager.remove(forKey: CacheKeys.friends())
        await cacheManager.remove(forKey: CacheKeys.friendRequests())
        return result
    }
    
    // MARK: - 친구 삭제
    func deleteFriend(friendId: String) async throws {
        _ = try await request(.deleteFriend(friendId: friendId), as: EmptyResponse.self)
        // 친구 목록 캐시 무효화
        await cacheManager.remove(forKey: CacheKeys.friends())
    }
}

