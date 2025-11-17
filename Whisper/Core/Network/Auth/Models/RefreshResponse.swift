//
//  RefreshResponse.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation

struct RefreshResponse: Codable {
    let access: String
    let refresh: String
}

