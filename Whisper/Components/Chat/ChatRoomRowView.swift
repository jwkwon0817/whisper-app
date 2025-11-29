//
//  ChatRoomRowView.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import SwiftUI

// MARK: - Chat Room Row Component
struct ChatRoomRowView: View {
    let room: ChatRoom
    
    var body: some View {
        HStack(spacing: 12) {
            ChatRoomAvatarView(room: room)
            ChatRoomInfoView(room: room)
            
            Spacer()
            
            ChatRoomTimeView(room: room)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

struct ChatRoomAvatarView: View {
    let room: ChatRoom
    
    var body: some View {
        Group {
            if let profileImage = getProfileImageURL() {
                AsyncImage(url: profileImage) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    placeholderView
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
            } else {
                placeholderView
            }
        }
    }
    
    private var placeholderView: some View {
        Circle()
            .fill(Color.gray.opacity(0.2))
            .frame(width: 50, height: 50)
            .overlay {
                Image(systemName: room.roomType == .group ? "person.3.fill" : "person.fill")
                    .foregroundColor(.gray)
            }
    }
    
    private func getProfileImageURL() -> URL? {
        if room.roomType == .direct {
            let otherMember = room.members.first { member in
                member.user.id != CurrentUser.shared.id
            }
            if let imageUrl = otherMember?.user.profileImage {
                return URL(string: imageUrl)
            }
        }
        return nil
    }
}

struct ChatRoomInfoView: View {
    let room: ChatRoom
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(room.displayName)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                if room.roomType == .group {
                    Text("(\(room.memberCount))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            if !room.lastMessagePreview.isEmpty {
                Text(room.lastMessagePreview)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct ChatRoomTimeView: View {
    let room: ChatRoom
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if let date = room.updatedAtDate {
                Text(date, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if room.unreadCount > 0 {
                UnreadBadgeView(count: room.unreadCount)
            }
        }
    }
}

struct UnreadBadgeView: View {
    let count: Int
    
    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, count > 99 ? 6 : 8)
            .padding(.vertical, 4)
            .background(Color.blue)
            .clipShape(Capsule())
            .frame(minWidth: 20)
    }
}

