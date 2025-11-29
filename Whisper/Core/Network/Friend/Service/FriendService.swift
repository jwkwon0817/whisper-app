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
    
    func sendFriendRequest(phoneNumber: String) async throws {
        _ = try await request(.sendFriendRequest(phoneNumber: phoneNumber), as: EmptyResponse.self)
        await cacheManager.remove(forKey: CacheKeys.friendRequests())
    }
    
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
    
    func respondToFriendRequest(friendId: String, action: String) async throws {
        // 백엔드에서 FriendSerializer를 반환하지만, 앱에서는 응답을 사용하지 않으므로 EmptyResponse로 처리
        _ = try await request(.respondToFriendRequest(friendId: friendId, action: action), as: EmptyResponse.self)
        await cacheManager.remove(forKey: CacheKeys.friends())
        await cacheManager.remove(forKey: CacheKeys.friendRequests())
    }
    
    func deleteFriend(friendId: String) async throws {
        _ = try await request(.deleteFriend(friendId: friendId), as: EmptyResponse.self)
        await cacheManager.remove(forKey: CacheKeys.friends())
    }
}

