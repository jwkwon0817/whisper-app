//
//  UserAPI.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation
import Moya
internal import Alamofire

enum AuthAPI {
    case login(phoneNumber: String, password: String, deviceFingerprint: String?)
    case logout(refreshToken: String)
    case refresh(refreshToken: String)
    case sendVerificationCode(phoneNumber: String)
    case verifyCode(phoneNumber: String, code: String)
    case register(phoneNumber: String, password: String, name: String, verifiedToken: String, profileImage: Data?, publicKey: String, encryptedPrivateKey: String, deviceName: String, deviceFingerprint: String)
}

extension AuthAPI: TargetType {
    var baseURL: URL {
        return URL(string: EnvironmentVariables.baseURL)!
    }
    
    var path: String {
        switch self {
        case .login:
            return "/api/auth/login/"
        case .logout:
            return "/api/auth/logout/"
        case .refresh:
            return "/api/auth/refresh/"
        case .sendVerificationCode:
            return "/api/auth/send-verification-code/"
        case .verifyCode:
            return "/api/auth/verify-phone/"
        case .register:
            return "/api/auth/register/"
        }
    }
    
    var method: Moya.Method {
        switch self {
        case .login, .logout, .refresh, .sendVerificationCode, .verifyCode, .register:
            return .post
        }
    }
    
    var task: Task {
        switch self {
        case .login(let phoneNumber, let password, let deviceFingerprint):
            let request = LoginRequest(phoneNumber: phoneNumber, password: password, deviceFingerprint: deviceFingerprint)
            return .requestJSONEncodable(request)
        case .logout(let refreshToken):
            return .requestParameters(parameters: ["refresh": refreshToken], encoding: JSONEncoding.default)
        case .refresh(let refreshToken):
            return .requestParameters(parameters: ["refresh": refreshToken], encoding: JSONEncoding.default)
        case .sendVerificationCode(let phoneNumber):
            let request = SendVerificationCodeRequest(phoneNumber: phoneNumber)
            return .requestJSONEncodable(request)
        case .verifyCode(let phoneNumber, let code):
            let request = VerifyCodeRequest(phoneNumber: phoneNumber, code: code)
            return .requestJSONEncodable(request)
        case .register(let phoneNumber, let password, let name, let verifiedToken, let profileImage, let publicKey, let encryptedPrivateKey, let deviceName, let deviceFingerprint):
            var formData: [Moya.MultipartFormData] = []
            
            formData.append(Moya.MultipartFormData(provider: .data(phoneNumber.data(using: .utf8)!), name: "phone_number"))
            formData.append(Moya.MultipartFormData(provider: .data(password.data(using: .utf8)!), name: "password"))
            formData.append(Moya.MultipartFormData(provider: .data(name.data(using: .utf8)!), name: "name"))
            formData.append(Moya.MultipartFormData(provider: .data(verifiedToken.data(using: .utf8)!), name: "verified_token"))
            
            if let profileImage = profileImage {
                formData.append(Moya.MultipartFormData(provider: .data(profileImage), name: "profile_image", fileName: "profile.jpg", mimeType: "image/jpeg"))
            }
            
            if !publicKey.isEmpty {
                formData.append(Moya.MultipartFormData(provider: .data(publicKey.data(using: .utf8)!), name: "public_key"))
            }
            formData.append(Moya.MultipartFormData(provider: .data(encryptedPrivateKey.data(using: .utf8)!), name: "encrypted_private_key"))
            formData.append(Moya.MultipartFormData(provider: .data(deviceName.data(using: .utf8)!), name: "device_name"))
            formData.append(Moya.MultipartFormData(provider: .data(deviceFingerprint.data(using: .utf8)!), name: "device_fingerprint"))
            
            return .uploadMultipart(formData)
        }
    }
    
    var headers: [String: String]? {
        var headers: [String: String] = [:]
        
        switch self {
        case .register:
            break
        case .logout:
            headers["Content-Type"] = "application/json"
            if let token = KeychainHelper.getItem(forAccount: "accessToken") {
                headers["Authorization"] = "Bearer \(token)"
            }
        case .login, .refresh, .sendVerificationCode, .verifyCode:
            headers["Content-Type"] = "application/json"
        }
        
        return headers.isEmpty ? nil : headers
    }
    
    var validationType: ValidationType {
        return .successCodes
    }
}
