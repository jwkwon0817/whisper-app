//
//  TypingIndicatorView.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import SwiftUI

struct TypingIndicatorView: View {
    let typingUsers: [User]
    
    var body: some View {
        Group {
            if !typingUsers.isEmpty {
                HStack(spacing: 12) {
                    if typingUsers.count == 1 {
                        if let profileImageUrl = typingUsers.first?.profileImage,
                           let url = URL(string: profileImageUrl) {
                            AsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Circle()
                                    .fill(Color.gray.opacity(0.2))
                                    .overlay {
                                        Image(systemName: "person.fill")
                                            .foregroundColor(.gray)
                                    }
                            }
                            .frame(width: 24, height: 24)
                            .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 24, height: 24)
                                .overlay {
                                    Image(systemName: "person.fill")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                        }
                        
                        Text(typingUsers.first?.name ?? "")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("님이 입력 중")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ZStack(alignment: .leading) {
                            ForEach(Array(typingUsers.prefix(3).enumerated()), id: \.element.id) { index, user in
                                if let profileImageUrl = user.profileImage,
                                   let url = URL(string: profileImageUrl) {
                                    AsyncImage(url: url) { image in
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        Circle()
                                            .fill(Color.gray.opacity(0.2))
                                            .overlay {
                                                Image(systemName: "person.fill")
                                                    .foregroundColor(.gray)
                                            }
                                    }
                                    .frame(width: 24, height: 24)
                                    .clipShape(Circle())
                                    .overlay {
                                        Circle()
                                            .stroke(Color(.systemBackground), lineWidth: 2)
                                    }
                                    .offset(x: CGFloat(index) * 16)
                                } else {
                                    Circle()
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(width: 24, height: 24)
                                        .overlay {
                                            Image(systemName: "person.fill")
                                                .font(.caption2)
                                                .foregroundColor(.gray)
                                        }
                                        .overlay {
                                            Circle()
                                                .stroke(Color(.systemBackground), lineWidth: 2)
                                        }
                                        .offset(x: CGFloat(index) * 16)
                                }
                            }
                        }
                        .frame(width: CGFloat(min(typingUsers.count, 3)) * 16 + 8, height: 24)
                        
                        Text("여러 명이 입력 중")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    TypingDotsView()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemBackground))
            }
        }
    }
}

struct TypingDotsView: View {
    @State private var animationPhase = 0
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 6, height: 6)
                    .opacity(animationPhase == index ? 1.0 : 0.3)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever()) {
                animationPhase = (animationPhase + 1) % 3
            }
        }
    }
}

