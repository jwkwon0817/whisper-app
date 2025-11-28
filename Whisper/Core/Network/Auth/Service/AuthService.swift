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
            throw TokenError.refreshFailed
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            provider.request(.refresh(refreshToken: refreshToken)) { result in
                switch result {
                case .success(let response):
                    do {
                        let refreshResponse = try self.decoder.decode(RefreshResponse.self, from: response.data)
                        
                        let accessTokenSaved = KeychainHelper.setItem(token: refreshResponse.access, forAccount: "accessToken")
                        let refreshTokenSaved = KeychainHelper.setItem(token: refreshResponse.refresh, forAccount: "refreshToken")
                        
                        continuation.resume(returning: refreshResponse)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                case .failure(let error):
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

