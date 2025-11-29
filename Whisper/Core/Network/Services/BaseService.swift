//
//  BaseService.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation
import Moya

actor TokenRefreshManager {
    private var isRefreshing = false
    private var refreshContinuations: [CheckedContinuation<RefreshResponse, Error>] = []
    
    func refreshIfNeeded(
        authService: AuthService
    ) async throws -> RefreshResponse {
        if isRefreshing {
            return try await withCheckedThrowingContinuation { continuation in
                refreshContinuations.append(continuation)
            }
        }
        
        isRefreshing = true
        
        do {
            let response = try await authService.refresh()
            let continuations = refreshContinuations
            
            refreshContinuations.removeAll()
            isRefreshing = false
            for continuation in continuations {
                continuation.resume(returning: response)
            }
            
            return response
        } catch {
            let continuations = refreshContinuations
            refreshContinuations.removeAll()
            isRefreshing = false
            for continuation in continuations {
                continuation.resume(throwing: TokenError.refreshFailed)
            }
            
            throw TokenError.refreshFailed
        }
    }
}

class BaseService<Target: TargetType> {
    let provider: MoyaProvider<Target>
    let authService: AuthService
    let decoder: JSONDecoder
    
    private let refreshManager = TokenRefreshManager()
    
    init(provider: MoyaProvider<Target>, authService: AuthService, decoder: JSONDecoder) {
        self.provider = provider
        self.authService = authService
        self.decoder = decoder
    }
    
    @MainActor
    private func performAutoLogout() async {
        KeychainHelper.removeItem(forAccount: "accessToken")
        KeychainHelper.removeItem(forAccount: "refreshToken")
        KeychainHelper.removeItem(forAccount: "user_password")
        E2EEKeyManager.shared.deleteEncryptedPrivateKey()
        CurrentUser.shared.clear()
        
        await CacheManager.shared.clearAll()
        
        ChatWebSocketManager.shared.disconnect()
        NotificationWebSocketManager.shared.disconnect()
        
        NotificationCenter.default.post(name: .userDidLogout, object: nil)
    }
    
    func request<T: Decodable>(_ target: Target, as type: T.Type) async throws -> T {
        return try await request(target, as: type, isRetry: false)
    }
    
    private func request<T: Decodable>(_ target: Target, as type: T.Type, isRetry: Bool) async throws -> T {
        do {
            return try await performRequest(target, as: type)
        } catch {
            if let moyaError = error as? MoyaError {
                var isUnauthorized = false
                var errorResponse: Response?
                
                if let response = moyaError.response, response.statusCode == 401 {
                    isUnauthorized = true
                    errorResponse = response
                }
                
                if isUnauthorized, let response = errorResponse {
                    if isRetry {
                        throw TokenError.refreshFailed
                    }
                    
                    if isRefreshRequest(target) {
                        throw TokenError.refreshFailed
                    }
                    
                    guard let refreshToken = KeychainHelper.getItem(forAccount: "refreshToken") else {
                        await performAutoLogout()
                        throw TokenError.refreshFailed
                    }
                    
                    do {
                        let refreshResponse = try await refreshManager.refreshIfNeeded(authService: authService)
                        
                        try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000) // 0.1초
                        
                        let retryResult = try await request(target, as: type, isRetry: true)
                        
                        return retryResult
                    } catch {
                        await performAutoLogout()
                        throw TokenError.refreshFailed
                    }
                } else {
                    throw moyaError
                }
            } else {
                throw error
            }
        }
    }
    
    private func isRefreshRequest(_ target: Target) -> Bool {
        if let authAPI = target as? AuthAPI {
            if case .refresh = authAPI {
                return true
            }
        }
        return false
    }
    
    private func performRequest<T: Decodable>(_ target: Target, as type: T.Type) async throws -> T {
        return try await withCheckedThrowingContinuation { continuation in
            provider.request(target) { result in
                switch result {
                case .success(let response):
                    if response.statusCode == 401 {
                        let moyaError = MoyaError.statusCode(response)
                        continuation.resume(throwing: moyaError)
                        return
                    }
                    
                    if response.data.isEmpty {
                        if type == EmptyResponse.self {
                            let emptyResponse = EmptyResponse()
                            continuation.resume(returning: emptyResponse as! T)
                            return
                        } else {
                            continuation.resume(throwing: NSError(domain: "BaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "서버가 빈 응답을 반환했습니다."]))
                            return
                        }
                    }
                    
                    do {
                        let decoded = try self.decoder.decode(type, from: response.data)
                        continuation.resume(returning: decoded)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
