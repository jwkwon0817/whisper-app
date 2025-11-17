//
//  DeleteAccountRequest.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation

struct DeleteAccountRequest: Codable {
    let confirmText: String
    let password: String
    
    enum CodingKeys: String, CodingKey {
        case confirmText = "confirm_text"
        case password
    }
}

