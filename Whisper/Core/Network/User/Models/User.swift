//
//  User.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation

struct User: Codable {
    let id: String
    let name: String
    let profileImage: String?
    let maskedPhoneNumber: String?
    let createdAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case profileImage = "profile_image"
        case maskedPhoneNumber = "masked_phone_number"
        case createdAt = "created_at"
    }
}

