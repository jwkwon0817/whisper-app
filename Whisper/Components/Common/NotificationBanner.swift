//
//  NotificationBanner.swift
//  Whisper
//
//  Created by Cursor on 11/28/25.
//

import SwiftUI

struct NotificationBanner: View {
    let title: String
    let message: String
    let onDismiss: () -> Void
    let onTap: () -> Void
    
    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "bubble.left.fill")
                        .foregroundColor(.blue)
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Text("지금")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
            )
            .padding(.horizontal)
            .padding(.top, geometry.safeAreaInsets.top + 8) // Safe area + 8pt 여유
        }
        .frame(height: 90) // 배너 높이 고정
        .onTapGesture {
            onTap()
        }
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onEnded { value in
                    if value.translation.height < -10 {
                        onDismiss()
                    }
                }
        )
    }
}

#Preview {
    ZStack(alignment: .top) {
        Color.gray.ignoresSafeArea()
        NotificationBanner(
            title: "알림",
            message: "새로운 메시지가 도착했습니다.",
            onDismiss: {},
            onTap: {}
        )
    }
}

