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
            var normalizedURL = url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !normalizedURL.hasPrefix("http://") && !normalizedURL.hasPrefix("https://") {
                normalizedURL = "https://" + normalizedURL
            }
            return normalizedURL
        }
        return "http://localhost:8000"
    }
}
