//
//  LoginResponse.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation

struct LoginResponse: Codable {
    let access: String
    let refresh: String
    let deviceRegistered: Bool?
    let deviceId: String?
    
    enum CodingKeys: String, CodingKey {
        case access
        case refresh
        case deviceRegistered = "device_registered"
        case deviceId = "device_id"
    }
}

