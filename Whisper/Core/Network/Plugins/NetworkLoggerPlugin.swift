//
//  NetworkLoggerPlugin.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation
import Moya

struct NetworkLoggerPlugin: PluginType {
    func willSend(_ request: RequestType, target: TargetType) {
        #if DEBUG
        guard let httpRequest = request.request else {
            print("⚠️ [NetworkLogger] 요청 객체가 nil입니다")
            return
        }
        
        let url = httpRequest.url?.absoluteString ?? "Unknown URL"
        let method = httpRequest.httpMethod ?? "Unknown"
        
        print("\n" + String(repeating: "=", count: 80))
        print("📤 [NetworkLogger] API 요청 시작")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📍 URL: \(url)")
        print("🔧 Method: \(method)")
        
        // 헤더 출력
        if let headers = httpRequest.allHTTPHeaderFields, !headers.isEmpty {
            print("📋 Headers:")
            for (key, value) in headers.sorted(by: { $0.key < $1.key }) {
                // Authorization 토큰은 일부만 표시
                if key == "Authorization" {
                    let tokenPreview = String(value.prefix(20)) + "..."
                    print("   \(key): \(tokenPreview)")
                } else {
                    print("   \(key): \(value)")
                }
            }
        }
        
        // Body 출력
        if let httpBody = httpRequest.httpBody {
            if let bodyString = String(data: httpBody, encoding: .utf8) {
                // 민감한 정보 마스킹
                let maskedBody = maskSensitiveData(bodyString)
                print("📦 Body:")
                print(maskedBody)
            } else {
                print("📦 Body: [Binary Data - \(httpBody.count) bytes]")
            }
        } else if let httpBodyStream = httpRequest.httpBodyStream {
            print("📦 Body: [Stream Data]")
        }
        
        print(String(repeating: "=", count: 80) + "\n")
        #endif
    }
    
    func didReceive(_ result: Result<Response, MoyaError>, target: TargetType) {
        #if DEBUG
        switch result {
        case .success(let response):
            let url = response.request?.url?.absoluteString ?? "Unknown URL"
            let statusCode = response.statusCode
            
            print("\n" + String(repeating: "=", count: 80))
            print("📥 [NetworkLogger] API 응답 수신")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("📍 URL: \(url)")
            print("✅ Status Code: \(statusCode)")
            
            // 응답 헤더 출력
            if let headers = response.response?.allHeaderFields as? [String: Any], !headers.isEmpty {
                print("📋 Response Headers:")
                for (key, value) in headers.sorted(by: { "\($0.key)" < "\($1.key)" }) {
                    print("   \(key): \(value)")
                }
            }
            
            // 응답 Body 출력
            if !response.data.isEmpty {
                if let responseString = String(data: response.data, encoding: .utf8) {
                    // 민감한 정보 마스킹
                    let maskedResponse = maskSensitiveData(responseString)
                    print("📦 Response Body:")
                    print(maskedResponse)
                } else {
                    print("📦 Response Body: [Binary Data - \(response.data.count) bytes]")
                }
            } else {
                print("📦 Response Body: [Empty]")
            }
            
            // 응답 시간 계산 (대략적)
            if let requestDate = response.request?.value(forHTTPHeaderField: "X-Request-Date") {
                print("⏱️ Request Date: \(requestDate)")
            }
            
            print(String(repeating: "=", count: 80) + "\n")
            
        case .failure(let error):
            let url = error.response?.request?.url?.absoluteString ?? "Unknown URL"
            
            print("\n" + String(repeating: "=", count: 80))
            print("❌ [NetworkLogger] API 요청 실패")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("📍 URL: \(url)")
            print("🔴 Error: \(error.localizedDescription)")
            
            if let response = error.response {
                print("📊 Status Code: \(response.statusCode)")
                
                if !response.data.isEmpty {
                    if let errorString = String(data: response.data, encoding: .utf8) {
                        print("📦 Error Response:")
                        print(errorString)
                    }
                }
            }
            
            switch error {
            case .statusCode(let response):
                print("   Type: Status Code Error (\(response.statusCode))")
            case .underlying(let underlyingError, _):
                print("   Type: Underlying Error")
                print("   Details: \(underlyingError.localizedDescription)")
            case .requestMapping(let message):
                print("   Type: Request Mapping Error")
                print("   Details: \(message)")
            case .parameterEncoding(let error):
                print("   Type: Parameter Encoding Error")
                print("   Details: \(error.localizedDescription)")
            case .imageMapping(let response):
                print("   Type: Image Mapping Error")
                print("   Status Code: \(response.statusCode)")
            case .jsonMapping(let response):
                print("   Type: JSON Mapping Error")
                print("   Status Code: \(response.statusCode)")
            case .stringMapping(let response):
                print("   Type: String Mapping Error")
                print("   Status Code: \(response.statusCode)")
            case .objectMapping(let error, let response):
                print("   Type: Object Mapping Error")
                print("   Error: \(error)")
                print("   Status Code: \(response.statusCode)")
            case .encodableMapping(let error):
                print("   Type: Encodable Mapping Error")
                print("   Error: \(error)")
            @unknown default:
                print("   Type: Unknown Error")
            }
            
            print(String(repeating: "=", count: 80) + "\n")
        }
        #endif
    }
    
    // MARK: - 민감한 정보 마스킹
    
    private func maskSensitiveData(_ text: String) -> String {
        var masked = text
        
        // 패스워드 마스킹
        masked = masked.replacingOccurrences(
            of: #""password"\s*:\s*"[^"]*""#,
            with: #""password":"***"#,
            options: .regularExpression
        )
        
        // accessToken, refreshToken 마스킹
        masked = masked.replacingOccurrences(
            of: #""(access|refresh)"\s*:\s*"[^"]*""#,
            with: #""$1":"***"#,
            options: .regularExpression
        )
        
        // encrypted_private_key 마스킹
        masked = masked.replacingOccurrences(
            of: #""encrypted_private_key"\s*:\s*"[^"]*""#,
            with: #""encrypted_private_key":"***"#,
            options: .regularExpression
        )
        
        // encrypted_content 마스킹 (일부만 표시)
        masked = masked.replacingOccurrences(
            of: #""encrypted_content"\s*:\s*"([^"]{0,20})[^"]*""#,
            with: #""encrypted_content":"$1..."#,
            options: .regularExpression
        )
        
        return masked
    }
}

