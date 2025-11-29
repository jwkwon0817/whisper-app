//
//  Friend.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation

struct Friend: Identifiable, Codable, Hashable {
    let id: String
    let user: User
    
    enum CodingKeys: String, CodingKey {
        case id
        case user
    }
}

typealias FriendRequest = Friend

