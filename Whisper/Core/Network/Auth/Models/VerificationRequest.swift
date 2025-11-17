//
//  VerificationRequest.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation

struct SendVerificationCodeRequest: Codable {
    let phoneNumber: String
    
    enum CodingKeys: String, CodingKey {
        case phoneNumber = "phone_number"
    }
}

struct VerifyCodeRequest: Codable {
    let phoneNumber: String
    let code: String
    
    enum CodingKeys: String, CodingKey {
        case phoneNumber = "phone_number"
        case code
    }
}

struct VerifyCodeResponse: Codable {
    let verifiedToken: String
    
    enum CodingKeys: String, CodingKey {
        case verifiedToken = "verified_token"
    }
}

struct RegisterRequest: Codable {
    let phoneNumber: String
    let password: String
    let name: String
    let publicKey: String
    
    enum CodingKeys: String, CodingKey {
        case phoneNumber = "phone_number"
        case password
        case name
        case publicKey = "public_key"
    }
}

