//
//  LoginRequest.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation

struct LoginRequest: Codable {
    let phoneNumber: String
    let password: String
    let deviceFingerprint: String?
    
    enum CodingKeys: String, CodingKey {
        case phoneNumber = "phone_number"
        case password
        case deviceFingerprint = "device_fingerprint"
    }
}

