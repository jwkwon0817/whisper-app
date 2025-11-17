//
//  FullScreenCoverModifier.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import SwiftUI

/// 플랫폼 독립적인 FullScreenCover Extension
/// iOS에서는 fullScreenCover를 사용하고, macOS에서는 sheet를 사용
extension View {
    func platformFullScreenCover<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        onDismiss: @escaping () -> Void = {},
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        #if os(iOS)
        // iOS에서는 기본 fullScreenCover 사용
        self.fullScreenCover(item: item, onDismiss: onDismiss, content: content)
        #elseif os(macOS)
        // macOS에서는 fullScreenCover가 없으므로 sheet로 대체
        self.sheet(item: item, onDismiss: onDismiss, content: content)
        #else
        self
        #endif
    }
}
