//
//  CurrentUser.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation
import Combine

// MARK: - Current User Singleton
class CurrentUser: ObservableObject {
    static let shared = CurrentUser()
    
    @Published var id: String?
    @Published var name: String?
    @Published var profileImage: String?
    
    private init() {}
    
    func update(user: User) {
        self.id = user.id
        self.name = user.name
        self.profileImage = user.profileImage
    }
    
    func clear() {
        self.id = nil
        self.name = nil
        self.profileImage = nil
    }
}

