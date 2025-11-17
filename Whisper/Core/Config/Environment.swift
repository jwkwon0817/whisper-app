//
//  Environment.swift
//  Whisper
//
//  Created by  jwkwon0817 on 11/17/25.
//

import Foundation

enum EnvironmentVariables {
    static var baseURL: String {
        if let url = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
           !url.isEmpty,
           !url.contains("$()") {
            // URL 정규화 (끝의 슬래시 제거)
            var normalizedURL = url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            // 프로토콜이 없으면 추가
            if !normalizedURL.hasPrefix("http://") && !normalizedURL.hasPrefix("https://") {
                normalizedURL = "https://" + normalizedURL
            }
            return normalizedURL
        }
        // Fallback URL
        return "http://localhost:8000"
    }
}
