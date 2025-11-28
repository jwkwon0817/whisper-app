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
    
    // 백그라운드 갱신 중복 방지를 위한 플래그
    private var isRefreshingMe = false
    
    func fetchMe(useCache: Bool = true) async throws -> User {
        if useCache, let cached = await cacheManager.get(User.self, forKey: CacheKeys.currentUser()) {
            // 백그라운드 갱신이 이미 진행 중이면 추가 갱신 안 함
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
                        // 백그라운드 갱신 실패는 무시
                        #if DEBUG
                        print("⚠️ [UserService] /me 백그라운드 갱신 실패: \(error)")
                        #endif
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
                    // 성공 시 모든 데이터 삭제
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

