//
//  AuthTokenPlugin.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation
import Moya

struct AuthTokenPlugin: PluginType {
    func prepare(_ request: URLRequest, target: TargetType) -> URLRequest {
        var request = request
        
        // 로그인, 회원가입, 인증 코드 관련 요청에는 토큰 불필요
        if let authAPI = target as? AuthAPI {
            switch authAPI {
            case .login, .register, .sendVerificationCode, .verifyCode, .refresh:
                return request // 토큰 없이 요청
            case .logout:
                // logout은 명시적으로 토큰을 추가하므로 여기서는 추가하지 않음
                return request
            }
        }
        
        // 나머지 요청에는 토큰 추가
        if let token = KeychainHelper.getItem(forAccount: "accessToken") {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            #if DEBUG
            if let url = request.url {
                print("🔑 [AuthTokenPlugin] 토큰 추가 - URL: \(url.path)")
                print("   토큰 길이: \(token.count)")
                print("   토큰 앞부분: \(token.prefix(20))...")
            }
            #endif
        } else {
            #if DEBUG
            if let url = request.url {
                print("⚠️ [AuthTokenPlugin] 토큰 없음 - URL: \(url.path)")
            }
            #endif
        }
        
        return request
    }
}

