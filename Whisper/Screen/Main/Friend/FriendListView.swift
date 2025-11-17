//
//  FriendListView.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import SwiftUI

// MARK: - Friend List View
struct FriendListView: View {
    @StateObject private var viewModel = FriendListViewModel()
    @State private var showAddFriend = false
    
    var body: some View {
        NavigationView {
            List {
                ForEach(viewModel.friends) { friend in
                    FriendRowView(friend: friend) {
                        Task {
                            await viewModel.deleteFriend(friend)
                        }
                    }
                }
            }
            .navigationTitle("친구")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showAddFriend = true
                    }) {
                        Image(systemName: "person.badge.plus")
                    }
                }
            }
            .refreshable {
                await viewModel.refresh()
            }
            .task {
                await viewModel.loadFriends()
            }
            .alert("오류", isPresented: $viewModel.showError) {
                Button("확인", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage ?? "알 수 없는 오류가 발생했습니다.")
            }
            .sheet(isPresented: $showAddFriend) {
                AddFriendView()
            }
        }
    }
}

// MARK: - Friend Row View
struct FriendRowView: View {
    let friend: Friend
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // 프로필 이미지
            if let profileImageUrl = friend.otherUser.profileImage,
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
                        }
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 50, height: 50)
                    .overlay {
                        Image(systemName: "person.fill")
                    }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(friend.otherUser.name)
                    .font(.headline)
            }
            
            Spacer()
            
            Menu {
                Button(role: .destructive, action: onDelete) {
                    Label("친구 삭제", systemImage: "person.fill.xmark")
                }
            } label: {
                Image(systemName: "ellipsis")
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add Friend View
struct AddFriendView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = FriendRequestViewModel()
    @State private var phoneNumber = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("전화번호", text: $phoneNumber)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                } header: {
                    Text("친구 추가")
                } footer: {
                    Text("전화번호로 친구를 검색하고 요청을 보냅니다.")
                }
                
                Button(action: {
                    viewModel.phoneNumber = phoneNumber
                    Task {
                        await viewModel.sendFriendRequest()
                        if viewModel.errorMessage == nil {
                            dismiss()
                        }
                    }
                }) {
                    HStack {
                        Spacer()
                        if viewModel.isLoading {
                            ProgressView()
                        } else {
                            Text("친구 요청 보내기")
                        }
                        Spacer()
                    }
                }
                .disabled(phoneNumber.isEmpty || viewModel.isLoading)
            }
            .navigationTitle("친구 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("취소") {
                        dismiss()
                    }
                }
            }
            .alert("오류", isPresented: $viewModel.showError) {
                Button("확인", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage ?? "알 수 없는 오류가 발생했습니다.")
            }
        }
    }
}

// MARK: - Friend Request List View
struct FriendRequestListView: View {
    @StateObject private var viewModel = FriendRequestViewModel()
    
    var body: some View {
        NavigationView {
            List {
                if viewModel.receivedRequests.isEmpty && !viewModel.isLoading {
                    Text("받은 친구 요청이 없습니다.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    ForEach(viewModel.receivedRequests) { request in
                        FriendRequestRowView(request: request) { action in
                            Task {
                                await viewModel.respondToRequest(request, action: action)
                            }
                        }
                    }
                }
            }
            .navigationTitle("친구 요청")
            .refreshable {
                await viewModel.refresh()
            }
            .task {
                await viewModel.loadReceivedRequests()
            }
            .alert("오류", isPresented: $viewModel.showError) {
                Button("확인", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage ?? "알 수 없는 오류가 발생했습니다.")
            }
        }
    }
}

// MARK: - Friend Request Row View
struct FriendRequestRowView: View {
    let request: Friend
    let onRespond: (String) -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // 프로필 이미지
            if let profileImageUrl = request.requester.profileImage,
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
                        }
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 50, height: 50)
                    .overlay {
                        Image(systemName: "person.fill")
                    }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(request.requester.name)
                    .font(.headline)
                Text("친구 요청")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                Button(action: {
                    onRespond("reject")
                }) {
                    Text("거절")
                        .foregroundColor(.red)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }
                
                Button(action: {
                    onRespond("accept")
                }) {
                    Text("수락")
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

