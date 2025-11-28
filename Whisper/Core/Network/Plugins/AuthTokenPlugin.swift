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
        
        if let authAPI = target as? AuthAPI {
            switch authAPI {
            case .login, .register, .sendVerificationCode, .verifyCode, .refresh:
                return request
            case .logout:
                return request
            }
        }
        
        if let token = KeychainHelper.getItem(forAccount: "accessToken") {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
        } 
        
        return request
    }
}

