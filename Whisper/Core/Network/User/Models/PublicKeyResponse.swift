//
//  PublicKeyResponse.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation

struct PublicKeyResponse: Codable {
    let publicKey: String
    
    enum CodingKeys: String, CodingKey {
        case publicKey = "public_key"
    }
}

