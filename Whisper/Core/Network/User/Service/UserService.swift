//
//  UserService.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation
import Moya

class UserService: BaseService<UserAPI> {
    private let cacheManager = CacheManager.shared
    
    private var isRefreshingMe = false
    
    func fetchMe(useCache: Bool = true) async throws -> User {
        if useCache, let cached = await cacheManager.get(User.self, forKey: CacheKeys.currentUser()) {
            if !isRefreshingMe {
                isRefreshingMe = true
                _Concurrency.Task { [weak self] in
                    defer {
                        _Concurrency.Task { @MainActor [weak self] in
                            self?.isRefreshingMe = false
                        }
                    }
                    
                    do {
                        let fresh = try await self?.request(.me, as: User.self)
                        if let fresh = fresh {
                            await self?.cacheManager.set(fresh, forKey: CacheKeys.currentUser(), ttl: CacheTTL.user)
                        }
                    } catch {
                    }
                }
            }
            return cached
        }
        
        let user = try await request(.me, as: User.self)
        await cacheManager.set(user, forKey: CacheKeys.currentUser(), ttl: CacheTTL.user)
        return user
    }
    
    func deleteAccount(confirmText: String, password: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            provider.request(.delete(confirmText: confirmText, password: password)) { result in
                switch result {
                case .success:
                    KeychainHelper.removeItem(forAccount: "accessToken")
                    KeychainHelper.removeItem(forAccount: "refreshToken")
                    KeychainHelper.removeItem(forAccount: "user_password")
                    E2EEKeyManager.shared.deleteEncryptedPrivateKey()
                    CurrentUser.shared.clear()
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func getUserPublicKey(userId: String) async throws -> String {
        let response = try await request(.getUserPublicKey(userId: userId), as: PublicKeyResponse.self)
        return response.publicKey
    }
}

