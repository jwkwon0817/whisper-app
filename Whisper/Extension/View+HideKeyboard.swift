//
//  View+HideKeyboard.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import SwiftUI

extension View {
    func hideKeyboardOnTap() -> some View {
        self.simultaneousGesture(
            TapGesture().onEnded { _ in
                PlatformApplication.shared.resignFirstResponder()
            }
        )
    }
}

func hideKeyboard() {
    PlatformApplication.shared.resignFirstResponder()
}

