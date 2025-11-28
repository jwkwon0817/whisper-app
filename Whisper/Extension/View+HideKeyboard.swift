//
//  View+HideKeyboard.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import SwiftUI

extension View {
    func hideKeyboardOnTap() -> some View {
        let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        
        if isPreview {
            return AnyView(self)
        }
        
        return AnyView(
            self.onTapGesture {
                PlatformApplication.shared.resignFirstResponder()
            }
        )
    }
}

func hideKeyboard() {
    PlatformApplication.shared.resignFirstResponder()
}

