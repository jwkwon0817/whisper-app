//
//  ChatRoomListView.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import SwiftUI

// MARK: - Chat Room List View
struct ChatRoomListView: View {
    @StateObject private var viewModel = ChatRoomListViewModel()
    
    var body: some View {
        NavigationView {
            List {
                ForEach(viewModel.rooms) { room in
                    NavigationLink(destination: ChatRoomView(roomId: room.id)) {
                        ChatRoomRowView(room: room)
                    }
                }
            }
            .navigationTitle("채팅")
            .refreshable {
                await viewModel.refresh()
            }
            .task {
                await viewModel.loadRooms()
            }
            .alert("오류", isPresented: $viewModel.showError) {
                Button("확인", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage ?? "알 수 없는 오류가 발생했습니다.")
            }
        }
    }
}

// MARK: - Chat Room Row View
struct ChatRoomRowView: View {
    let room: ChatRoom
    
    var body: some View {
        HStack(spacing: 12) {
            // 프로필 이미지 또는 아이콘
            Circle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 50, height: 50)
                .overlay {
                    if room.roomType == .group {
                        Image(systemName: "person.3.fill")
                    } else {
                        Image(systemName: "person.fill")
                    }
                }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(room.displayName)
                    .font(.headline)
                
                Text(room.lastMessagePreview)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                if let date = room.updatedAtDate {
                    Text(date, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // 읽지 않은 메시지 수 (구현 필요)
            }
        }
        .padding(.vertical, 4)
    }
}

