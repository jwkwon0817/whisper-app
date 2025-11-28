//
//  BaseService.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation
import Moya

// 토큰 갱신 동기화를 위한 Actor
actor TokenRefreshManager {
    private var isRefreshing = false
    private var refreshContinuations: [CheckedContinuation<RefreshResponse, Error>] = []
    
    func refreshIfNeeded(
        authService: AuthService
    ) async throws -> RefreshResponse {
        // 이미 갱신 중이면 대기
        if isRefreshing {
            #if DEBUG
            print("⏳ [TokenRefreshManager] 이미 갱신 중 - 대기")
            #endif
            return try await withCheckedThrowingContinuation { continuation in
                refreshContinuations.append(continuation)
            }
        }
        
        #if DEBUG
        print("🔄 [TokenRefreshManager] 새 토큰 갱신 시작")
        print("   refreshToken 존재 여부: \(KeychainHelper.getItem(forAccount: "refreshToken") != nil)")
        #endif
        
        isRefreshing = true
        
        do {
            let response = try await authService.refresh()
            #if DEBUG
            print("✅ [TokenRefreshManager] 토큰 갱신 성공")
            #endif
            
            // 대기 중인 모든 continuation에 성공 결과 전달
            let continuations = refreshContinuations
            refreshContinuations.removeAll()
            isRefreshing = false
            for continuation in continuations {
                continuation.resume(returning: response)
            }
            
            return response
        } catch {
            #if DEBUG
            print("❌ [TokenRefreshManager] 토큰 갱신 실패: \(error)")
            #endif
            
            // 대기 중인 모든 continuation에 실패 결과 전달
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
    
    // 토큰 갱신 동기화를 위한 Actor
    private let refreshManager = TokenRefreshManager()
    
    init(provider: MoyaProvider<Target>, authService: AuthService, decoder: JSONDecoder) {
        self.provider = provider
        self.authService = authService
        self.decoder = decoder
    }
    
    /// 토큰 만료 시 자동 로그아웃 처리
    @MainActor
    private func performAutoLogout() async {
        #if DEBUG
        print("🚪 [BaseService] 자동 로그아웃 처리 시작")
        #endif
        
        // 모든 토큰 및 사용자 데이터 삭제
        KeychainHelper.removeItem(forAccount: "accessToken")
        KeychainHelper.removeItem(forAccount: "refreshToken")
        KeychainHelper.removeItem(forAccount: "user_password")
        E2EEKeyManager.shared.deleteEncryptedPrivateKey()
        CurrentUser.shared.clear()
        
        // 캐시 삭제
        await CacheManager.shared.clearAll()
        
        // WebSocket 연결 해제
        ChatWebSocketManager.shared.disconnect()
        NotificationWebSocketManager.shared.disconnect()
        
        #if DEBUG
        print("✅ [BaseService] 자동 로그아웃 완료 - 로그인 화면으로 이동 필요")
        #endif
        
        // NotificationCenter를 통해 로그인 화면으로 이동 알림
        NotificationCenter.default.post(name: .userDidLogout, object: nil)
    }
    
    func request<T: Decodable>(_ target: Target, as type: T.Type) async throws -> T {
        return try await request(target, as: type, isRetry: false)
    }
    
    private func request<T: Decodable>(_ target: Target, as type: T.Type, isRetry: Bool) async throws -> T {
        do {
            return try await performRequest(target, as: type)
        } catch {
            // MoyaError 처리
            if let moyaError = error as? MoyaError {
                // 401 상태 코드 확인 (statusCode case 또는 response case)
                var isUnauthorized = false
                var errorResponse: Response?
                
                if let response = moyaError.response, response.statusCode == 401 {
                    isUnauthorized = true
                    errorResponse = response
                }
                
                if isUnauthorized, let response = errorResponse {
                    // 재시도 중인데 또 401이 발생하면 무한 루프 방지
                    if isRetry {
                        #if DEBUG
                        print("\n" + String(repeating: "=", count: 80))
                        print("❌ [BaseService] 재시도 후에도 401 발생 - 토큰 갱신 실패")
                        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                        print("📍 요청 URL: \(target.baseURL.appendingPathComponent(target.path))")
                        print(String(repeating: "=", count: 80) + "\n")
                        #endif
                        throw TokenError.refreshFailed
                    }
                    
                    #if DEBUG
                    print("\n" + String(repeating: "=", count: 80))
                    print("🔐 [BaseService] 401 Unauthorized 감지 - 토큰 갱신 시도")
                    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    print("📍 요청 URL: \(target.baseURL.appendingPathComponent(target.path))")
                    print("📍 요청 메서드: \(String(describing: target.method))")
                    #endif
                    
                    // 토큰 갱신 API 자체가 401을 반환하는 경우 무한 루프 방지
                    if isRefreshRequest(target) {
                        #if DEBUG
                        print("❌ [BaseService] 토큰 갱신 API가 401을 반환 - 갱신 실패")
                        print("   refreshToken이 만료되었거나 유효하지 않음")
                        print(String(repeating: "=", count: 80) + "\n")
                        #endif
                        throw TokenError.refreshFailed
                    }
                    
                    // refreshToken 확인
                    guard let refreshToken = KeychainHelper.getItem(forAccount: "refreshToken") else {
                        #if DEBUG
                        print("❌ [BaseService] refreshToken이 Keychain에 없음 - 자동 로그아웃")
                        print(String(repeating: "=", count: 80) + "\n")
                        #endif
                        
                        // 자동 로그아웃 처리
                        await performAutoLogout()
                        throw TokenError.refreshFailed
                    }
                    
                    #if DEBUG
                    print("✅ [BaseService] refreshToken 확인됨 (길이: \(refreshToken.count))")
                    #endif
                    
                    // 토큰 갱신 시도
                    do {
                        #if DEBUG
                        print("🔄 [BaseService] refreshManager.refreshIfNeeded 호출 시작")
                        #endif
                        
                        let refreshResponse = try await refreshManager.refreshIfNeeded(authService: authService)
                        
                        #if DEBUG
                        print("✅ [BaseService] 토큰 갱신 성공 - 원래 요청 재시도")
                        let newAccessToken = KeychainHelper.getItem(forAccount: "accessToken")
                        print("   새 accessToken 존재 여부: \(newAccessToken != nil)")
                        if let token = newAccessToken {
                            print("   새 accessToken 길이: \(token.count)")
                            print("   새 accessToken 앞부분: \(token.prefix(20))...")
                        }
                        print("   재시도 시작...")
                        print(String(repeating: "=", count: 80) + "\n")
                        #endif
                        
                        // 토큰 갱신 후 재시도 (isRetry 플래그를 true로 설정)
                        // 잠시 대기하여 토큰이 Keychain에 완전히 저장되도록 함
                        try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000) // 0.1초
                        
                        let retryResult = try await request(target, as: type, isRetry: true)
                        
                        #if DEBUG
                        print("✅ [BaseService] 재시도 성공")
                        #endif
                        
                        return retryResult
                    } catch {
                        #if DEBUG
                        print("❌ [BaseService] 토큰 갱신 또는 재시도 실패: \(error)")
                        print("   에러 설명: \(error.localizedDescription)")
                        if let refreshError = error as? TokenError {
                            print("   TokenError: \(refreshError)")
                        } else if let moyaError = error as? MoyaError {
                            print("   MoyaError 감지")
                            if case .statusCode(let response) = moyaError {
                                print("   Status Code: \(response.statusCode)")
                            }
                        } else {
                            print("   에러 타입: \(error)")
                        }
                        print(String(repeating: "=", count: 80) + "\n")
                        #endif
                        
                        // 자동 로그아웃 처리
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
    
    // 토큰 갱신 요청인지 확인
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
                    // 401 에러 체크 (성공 응답이지만 상태 코드가 401인 경우)
                    if response.statusCode == 401 {
                        #if DEBUG
                        print("⚠️ [BaseService] performRequest에서 401 상태 코드 감지")
                        #endif
                        let moyaError = MoyaError.statusCode(response)
                        continuation.resume(throwing: moyaError)
                        return
                    }
                    
                    // 빈 응답 처리 (EmptyResponse인 경우)
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
                        // 디코딩 오류 상세 정보 출력 (디버깅용)
                        #if DEBUG
                        if let jsonString = String(data: response.data, encoding: .utf8) {
                            print("디코딩 실패 - 응답 데이터: \(jsonString)")
                        }
                        print("디코딩 오류: \(error)")
                        #endif
                        continuation.resume(throwing: error)
                    }
                case .failure(let error):
                    #if DEBUG
                    if let response = error.response {
                        print("❌ [BaseService] performRequest 실패 - Status Code: \(response.statusCode)")
                        if response.statusCode == 401 {
                            print("   401 에러 감지됨 - 토큰 리프레시 필요")
                        }
                    }
                    #endif
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
