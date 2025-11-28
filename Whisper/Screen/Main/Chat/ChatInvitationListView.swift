//
//  ChatInvitationListView.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/24/25.
//

import SwiftUI

struct ChatInvitationListView: View {
    @StateObject private var viewModel = ChatInvitationListViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.invitations.isEmpty {
                    // 로딩 중
                    LoadingView()
                } else if viewModel.invitations.isEmpty {
                    // 초대 없음
                    EmptyStateView(
                        icon: "envelope.open",
                        title: "받은 초대가 없습니다",
                        message: "친구들로부터 채팅 초대를 받으면 여기에 표시됩니다"
                    )
                } else {
                    // 초대 목록
                    List {
                        ForEach(viewModel.invitations) { invitation in
                            ChatInvitationRowView(
                                invitation: invitation,
                                onAccept: {
                                    viewModel.respondToInvitation(invitation, accept: true)
                                },
                                onReject: {
                                    viewModel.respondToInvitation(invitation, accept: false)
                                }
                            )
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        viewModel.loadInvitations()
                    }
                }
            }
            .navigationTitle("채팅 초대")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(.primary)
                    }
                }
            }
            .alert("오류", isPresented: $viewModel.showError) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "알 수 없는 오류가 발생했습니다.")
            }
        }
    }
}

// MARK: - ChatInvitationRowView
struct ChatInvitationRowView: View {
    let invitation: ChatInvitation
    let onAccept: () -> Void
    let onReject: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 초대 정보
            HStack(spacing: 12) {
                // 프로필 이미지
                AsyncImage(url: URL(string: invitation.inviter.profileImage ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .foregroundColor(.gray)
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(invitation.inviter.name)
                        .font(.headline)
                    
                    if invitation.type == .group, let room = invitation.room {
                        Text("\(room.name ?? "그룹 채팅")에 초대했습니다")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        Text("1:1 채팅에 초대했습니다")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(formatDate(invitation.createdAt))
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
            }
            
            // 버튼
            HStack(spacing: 12) {
                Button {
                    onReject()
                } label: {
                    Text("거절")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }
                
                Button {
                    onAccept()
                } label: {
                    Text("수락")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        guard let date = formatter.date(from: dateString) else {
            return dateString
        }
        
        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.minute, .hour, .day], from: date, to: now)
        
        if let day = components.day, day > 0 {
            return "\(day)일 전"
        } else if let hour = components.hour, hour > 0 {
            return "\(hour)시간 전"
        } else if let minute = components.minute, minute > 0 {
            return "\(minute)분 전"
        } else {
            return "방금 전"
        }
    }
}

#Preview {
    ChatInvitationListView()
}

