//
//  UseMe.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import SwiftUI

typealias UseMe = UseQuery<User>

extension UseQuery where T == User {
    convenience init(autoFetch: Bool = false) {
        self.init(autoFetch: autoFetch) {
            try await NetworkManager.shared.userService.fetchMe()
        }
    }
}
