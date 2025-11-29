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
        guard let httpRequest = request.request else { return }
        
        let url = httpRequest.url?.absoluteString ?? "Unknown URL"
        let method = httpRequest.httpMethod ?? "Unknown"
        
        print("\n[REQUEST] \(method) \(url)")
        
        if let headers = httpRequest.allHTTPHeaderFields, !headers.isEmpty {
            print("Headers:")
            for (key, value) in headers.sorted(by: { $0.key < $1.key }) {
                if key == "Authorization" {
                    let tokenPreview = String(value.prefix(20)) + "..."
                    print("  \(key): \(tokenPreview)")
                } else {
                    print("  \(key): \(value)")
                }
            }
        }
        
        if let httpBody = httpRequest.httpBody {
            if let bodyString = String(data: httpBody, encoding: .utf8) {
                let maskedBody = maskSensitiveData(bodyString)
                print("Body:")
                print(maskedBody)
            } else {
                print("Body: [Binary Data - \(httpBody.count) bytes]")
            }
        } else if let httpBodyStream = httpRequest.httpBodyStream {
            print("Body: [Stream Data]")
        }
        
        print("")
    }
    
    func didReceive(_ result: Result<Response, MoyaError>, target: TargetType) {
        switch result {
        case .success(let response):
            let url = response.request?.url?.absoluteString ?? "Unknown URL"
            let statusCode = response.statusCode
            
            let statusPrefix = statusCode >= 200 && statusCode < 300 ? "SUCCESS" : "ERROR"
            print("[RESPONSE] \(statusPrefix) \(statusCode) \(url)")
            
            if let headers = response.response?.allHeaderFields as? [String: Any], !headers.isEmpty {
                print("Headers:")
                for (key, value) in headers.sorted(by: { "\($0.key)" < "\($1.key)" }) {
                    print("  \(key): \(value)")
                }
            }
            
            if !response.data.isEmpty {
                if let responseString = String(data: response.data, encoding: .utf8) {
                    let maskedResponse = maskSensitiveData(responseString)
                    print("Body:")
                    print(maskedResponse)
                } else {
                    print("Body: [Binary Data - \(response.data.count) bytes]")
                }
            } else {
                print("Body: [Empty]")
            }
            
            print("")
            
        case .failure(let error):
            let url = error.response?.request?.url?.absoluteString ?? target.baseURL.appendingPathComponent(target.path).absoluteString
            
            print("[RESPONSE] FAILED \(url)")
            print("Error: \(error.localizedDescription)")
            
            if let response = error.response {
                print("Status Code: \(response.statusCode)")
                
                if !response.data.isEmpty {
                    if let errorString = String(data: response.data, encoding: .utf8) {
                        print("Error Response:")
                        print(errorString)
                    }
                }
            }
            
            switch error {
            case .statusCode(let response):
                print("Type: Status Code Error (\(response.statusCode))")
            case .underlying(let underlyingError, _):
                print("Type: Underlying Error")
                print("Details: \(underlyingError.localizedDescription)")
            case .requestMapping(let message):
                print("Type: Request Mapping Error")
                print("Details: \(message)")
            case .parameterEncoding(let error):
                print("Type: Parameter Encoding Error")
                print("Details: \(error.localizedDescription)")
            case .imageMapping(let response):
                print("Type: Image Mapping Error")
                print("Status Code: \(response.statusCode)")
            case .jsonMapping(let response):
                print("Type: JSON Mapping Error")
                print("Status Code: \(response.statusCode)")
            case .stringMapping(let response):
                print("Type: String Mapping Error")
                print("Status Code: \(response.statusCode)")
            case .objectMapping(let error, let response):
                print("Type: Object Mapping Error")
                print("Error: \(error)")
                print("Status Code: \(response.statusCode)")
            case .encodableMapping(let error):
                print("Type: Encodable Mapping Error")
                print("Error: \(error)")
            @unknown default:
                print("Type: Unknown Error")
            }
            
            print("")
        }
    }
    
    private func maskSensitiveData(_ text: String) -> String {
        var masked = text
        
        masked = masked.replacingOccurrences(
            of: #""password"\s*:\s*"[^"]*""#,
            with: #""password":"***"#,
            options: .regularExpression
        )
        
        masked = masked.replacingOccurrences(
            of: #""(access|refresh)"\s*:\s*"[^"]*""#,
            with: #""$1":"***"#,
            options: .regularExpression
        )
        
        masked = masked.replacingOccurrences(
            of: #""encrypted_private_key"\s*:\s*"[^"]*""#,
            with: #""encrypted_private_key":"***"#,
            options: .regularExpression
        )
        
        masked = masked.replacingOccurrences(
            of: #""encrypted_content"\s*:\s*"([^"]{0,20})[^"]*""#,
            with: #""encrypted_content":"$1..."#,
            options: .regularExpression
        )
        
        return masked
    }
}

