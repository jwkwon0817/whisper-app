//
//  SkeletonView.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import SwiftUI

struct SkeletonView: View {
    @State private var isAnimating = false
    
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.gray.opacity(0.2),
                        Color.gray.opacity(0.4),
                        Color.gray.opacity(0.2)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .opacity(isAnimating ? 0.5 : 1.0)
            .onAppear {
                withAnimation(
                    Animation.linear(duration: 1.0)
                        .repeatForever(autoreverses: false)
                ) {
                    isAnimating = true
                }
            }
    }
}

struct MessageSkeletonView: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                SkeletonView()
                    .frame(width: CGFloat.random(in: 100...200), height: 40)
                    .cornerRadius(16)
                
                HStack(spacing: 4) {
                    SkeletonView()
                        .frame(width: 40, height: 12)
                    SkeletonView()
                        .frame(width: 12, height: 12)
                        .clipShape(Circle())
                }
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

// MARK: - Chat Room Row Skeleton
struct ChatRoomRowSkeletonView: View {
    var body: some View {
        HStack(spacing: 12) {
            SkeletonView()
                .frame(width: 50, height: 50)
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                SkeletonView()
                    .frame(width: 120, height: 16)
                    .cornerRadius(4)
                
                SkeletonView()
                    .frame(width: 180, height: 14)
                    .cornerRadius(4)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                SkeletonView()
                    .frame(width: 50, height: 12)
                    .cornerRadius(4)
                
                SkeletonView()
                    .frame(width: 20, height: 20)
                    .clipShape(Circle())
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Friend Row Skeleton
struct FriendRowSkeletonView: View {
    var body: some View {
        HStack(spacing: 12) {
            SkeletonView()
                .frame(width: 50, height: 50)
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                SkeletonView()
                    .frame(width: 100, height: 16)
                    .cornerRadius(4)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

