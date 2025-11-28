//
//  AuthService.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation
import Moya

class AuthService {
    private let provider: MoyaProvider<AuthAPI>
    private let decoder: JSONDecoder
    
    init(provider: MoyaProvider<AuthAPI>, decoder: JSONDecoder) {
        self.provider = provider
        self.decoder = decoder
    }
    
    func login(phoneNumber: String, password: String, deviceFingerprint: String? = nil) async throws -> LoginResponse {
        return try await withCheckedThrowingContinuation { continuation in
            provider.request(.login(phoneNumber: phoneNumber, password: password, deviceFingerprint: deviceFingerprint)) { result in
                switch result {
                case .success(let response):
                    do {
                        let loginResponse = try self.decoder.decode(LoginResponse.self, from: response.data)
                        
                        KeychainHelper.setItem(token: loginResponse.access, forAccount: "accessToken")
                        KeychainHelper.setItem(token: loginResponse.refresh, forAccount: "refreshToken")
                        // 비밀번호 저장 (복호화용)
                        KeychainHelper.setItem(token: password, forAccount: "user_password")
                        continuation.resume(returning: loginResponse)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func logout() async throws {
        guard let refreshToken = KeychainHelper.getItem(forAccount: "refreshToken") else {
            clearTokens()
            return
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            provider.request(.logout(refreshToken: refreshToken)) { result in
                self.clearTokens()
                
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func refresh() async throws -> RefreshResponse {
        guard let refreshToken = KeychainHelper.getItem(forAccount: "refreshToken") else {
            #if DEBUG
            print("❌ [AuthService] refreshToken이 Keychain에 없음")
            #endif
            throw TokenError.refreshFailed
        }
        
        #if DEBUG
        print("\n" + String(repeating: "-", count: 80))
        print("🔄 [AuthService] 토큰 갱신 요청 시작")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📍 refreshToken 길이: \(refreshToken.count)")
        print("📍 refreshToken 앞부분: \(refreshToken.prefix(20))...")
        #endif
        
        return try await withCheckedThrowingContinuation { continuation in
            provider.request(.refresh(refreshToken: refreshToken)) { result in
                switch result {
                case .success(let response):
                    #if DEBUG
                    print("✅ [AuthService] 토큰 갱신 응답 수신")
                    print("   상태 코드: \(response.statusCode)")
                    print("   응답 데이터 길이: \(response.data.count)")
                    #endif
                    
                    do {
                        let refreshResponse = try self.decoder.decode(RefreshResponse.self, from: response.data)
                        
                        // 새 토큰 저장
                        let accessTokenSaved = KeychainHelper.setItem(token: refreshResponse.access, forAccount: "accessToken")
                        let refreshTokenSaved = KeychainHelper.setItem(token: refreshResponse.refresh, forAccount: "refreshToken")
                        
                        #if DEBUG
                        print("✅ [AuthService] 토큰 갱신 성공")
                        print("   새 accessToken 저장: \(accessTokenSaved ? "성공" : "실패")")
                        print("   새 refreshToken 저장: \(refreshTokenSaved ? "성공" : "실패")")
                        print("   새 accessToken 길이: \(refreshResponse.access.count)")
                        print("   새 refreshToken 길이: \(refreshResponse.refresh.count)")
                        print(String(repeating: "-", count: 80) + "\n")
                        #endif
                        
                        continuation.resume(returning: refreshResponse)
                    } catch {
                        #if DEBUG
                        print("❌ [AuthService] 토큰 갱신 응답 디코딩 실패: \(error)")
                        if let jsonString = String(data: response.data, encoding: .utf8) {
                            print("   응답 데이터: \(jsonString)")
                        }
                        print(String(repeating: "-", count: 80) + "\n")
                        #endif
                        continuation.resume(throwing: error)
                    }
                case .failure(let error):
                    #if DEBUG
                    print("❌ [AuthService] 토큰 갱신 요청 실패: \(error)")
                    if case .statusCode(let response) = error {
                        print("   상태 코드: \(response.statusCode)")
                        if let dataString = String(data: response.data, encoding: .utf8) {
                            print("   응답 데이터: \(dataString)")
                        }
                    } else if case .underlying(let nsError, _) = error {
                        print("   네트워크 에러: \(nsError.localizedDescription)")
                    }
                    print(String(repeating: "-", count: 80) + "\n")
                    #endif
                    self.clearTokens()
                    continuation.resume(throwing: TokenError.refreshFailed)
                }
            }
        }
    }
    
    func sendVerificationCode(phoneNumber: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            provider.request(.sendVerificationCode(phoneNumber: phoneNumber)) { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func verifyCode(phoneNumber: String, code: String) async throws -> VerifyCodeResponse {
        return try await withCheckedThrowingContinuation { continuation in
            provider.request(.verifyCode(phoneNumber: phoneNumber, code: code)) { result in
                switch result {
                case .success(let response):
                    do {
                        let verifyResponse = try self.decoder.decode(VerifyCodeResponse.self, from: response.data)
                        continuation.resume(returning: verifyResponse)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func register(
        phoneNumber: String,
        password: String,
        name: String,
        verifiedToken: String,
        profileImage: Data?,
        publicKey: String,
        encryptedPrivateKey: String,
        deviceName: String,
        deviceFingerprint: String
    ) async throws -> LoginResponse {
        return try await withCheckedThrowingContinuation { continuation in
            provider.request(.register(
                phoneNumber: phoneNumber,
                password: password,
                name: name,
                verifiedToken: verifiedToken,
                profileImage: profileImage,
                publicKey: publicKey,
                encryptedPrivateKey: encryptedPrivateKey,
                deviceName: deviceName,
                deviceFingerprint: deviceFingerprint
            )) { result in
                switch result {
                case .success(let response):
                    do {
                        let loginResponse = try self.decoder.decode(LoginResponse.self, from: response.data)
                        
                        // 토큰 저장
                        KeychainHelper.setItem(token: loginResponse.access, forAccount: "accessToken")
                        KeychainHelper.setItem(token: loginResponse.refresh, forAccount: "refreshToken")
                        // 비밀번호 저장 (복호화용)
                        KeychainHelper.setItem(token: password, forAccount: "user_password")
                        
                        continuation.resume(returning: loginResponse)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func clearTokens() {
        KeychainHelper.removeItem(forAccount: "accessToken")
        KeychainHelper.removeItem(forAccount: "refreshToken")
        KeychainHelper.removeItem(forAccount: "user_password")
        E2EEKeyManager.shared.deleteEncryptedPrivateKey()
        CurrentUser.shared.clear()
    }
}

