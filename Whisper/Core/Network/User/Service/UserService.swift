//
//  UserService.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation
import Moya

class UserService: BaseService<UserAPI> {
    func fetchMe() async throws -> User {
        return try await request(.me, as: User.self)
    }
    
    func deleteAccount(confirmText: String, password: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            provider.request(.delete(confirmText: confirmText, password: password)) { result in
                switch result {
                case .success:
                    // 성공 시 모든 데이터 삭제
                    KeychainHelper.removeItem(forAccount: "accessToken")
                    KeychainHelper.removeItem(forAccount: "refreshToken")
                    E2EEKeyManager.shared.deleteEncryptedPrivateKey()
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

