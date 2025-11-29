//
//  FriendListView.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import SwiftUI

struct FriendListView: View {
    @StateObject private var viewModel = FriendListViewModel()
    @State private var showAddFriend = false
    
    var body: some View {
        NavigationView {
            Group {
                if viewModel.isLoading && viewModel.friends.isEmpty {
                    List {
                        ForEach(0 ..< 5) { _ in
                            FriendRowSkeletonView()
                                .listRowSeparator(.hidden)
                        }
                    }
                } else if viewModel.friends.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 60))
                            .foregroundColor(.gray.opacity(0.5))
                        Text("친구 목록이 비어있어요")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        Text("친구를 추가하여 대화를 시작해보세요")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground))
                } else {
                    List {
                        ForEach(viewModel.friends) { friend in
                            FriendRowView(friend: friend) {
                                Task {
                                    await viewModel.deleteFriend(friend)
                                }
                            }
                            .contextMenu {
                                Button(role: .destructive, action: {
                                    Task {
                                        await viewModel.deleteFriend(friend)
                                    }
                                }) {
                                    Label("친구 삭제", systemImage: "person.fill.xmark")
                                }
                            }
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
                Button("확인", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "알 수 없는 오류가 발생했습니다.")
            }
            .sheet(isPresented: $showAddFriend) {
                AddFriendView()
            }
        }
    }
}

struct FriendRowView: View {
    let friend: Friend
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            if let profileImageUrl = friend.user.profileImage,
               let url = URL(string: profileImageUrl)
            {
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
                Text(friend.user.name)
                    .font(.headline)
            }
            
            Spacer()
            
            Menu {
                Button(role: .destructive, action: onDelete) {
                    Label("친구 삭제", systemImage: "person.fill.xmark")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 4)
    }
}

struct AddFriendView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = FriendRequestViewModel()
    @State private var phoneNumber = ""
    
    var body: some View {
        NavigationView {
            Form {
                if !viewModel.receivedRequests.isEmpty {
                    Section {
                        ForEach(viewModel.receivedRequests) { request in
                            FriendRequestRowView(request: request, viewModel: viewModel)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    } header: {
                        Text("받은 친구 요청")
                    }
                }
                
                Section {
                    TextField("전화번호", text: $phoneNumber)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .padding(.vertical, 16)
                        .padding(.horizontal, 20)
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
                            phoneNumber = ""
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
                    Button("닫기") {
                        dismiss()
                    }
                }
            }
            .task {
                await viewModel.loadReceivedRequests()
            }
            .alert("오류", isPresented: $viewModel.showError) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "알 수 없는 오류가 발생했습니다.")
            }
        }
    }
}

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
                        FriendRequestRowView(request: request, viewModel: viewModel)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
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
                Button("확인", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "알 수 없는 오류가 발생했습니다.")
            }
        }
    }
}

struct FriendRequestRowView: View {
    let request: Friend
    @ObservedObject var viewModel: FriendRequestViewModel
    @State private var isAccepting = false
    @State private var isRejecting = false
    
    private var isProcessing: Bool {
        isAccepting || isRejecting || viewModel.isProcessing(request.id)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            profileImageView
            
            VStack(alignment: .leading, spacing: 4) {
                Text(request.user.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text("친구 요청")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            actionButtons
        }
        .contentShape(Rectangle())
    }
    
    private var profileImageView: some View {
        Group {
            if let profileImageUrl = request.user.profileImage,
               let url = URL(string: profileImageUrl)
            {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure(_), .empty:
                        placeholderImage
                    @unknown default:
                        placeholderImage
                    }
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
            } else {
                placeholderImage
            }
        }
    }
    
    private var placeholderImage: some View {
        Circle()
            .fill(Color.gray.opacity(0.2))
            .frame(width: 50, height: 50)
            .overlay {
                Image(systemName: "person.fill")
                    .foregroundColor(.gray)
            }
    }
    
    private var actionButtons: some View {
        HStack(spacing: 8) {
            acceptButton
            
            rejectButton
        }
    }
    
    private var acceptButton: some View {
        Button(action: {
            handleAccept()
        }) {
            HStack(spacing: 4) {
                if isAccepting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.7)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                }
                if !isAccepting {
                    Text("수락")
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .foregroundColor(.white)
            .frame(minWidth: isAccepting ? 40 : 60)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isAccepting ? Color.blue.opacity(0.7) : Color.blue)
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isProcessing)
        .opacity(isProcessing && !isAccepting ? 0.5 : 1.0)
    }
    
    private var rejectButton: some View {
        Button(action: {
            handleReject()
        }) {
            HStack(spacing: 4) {
                if isRejecting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .red))
                        .scaleEffect(0.7)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                }
                if !isRejecting {
                    Text("거절")
                        .font(.system(size: 13, weight: .medium))
                }
            }
            .foregroundColor(isRejecting ? .red.opacity(0.6) : .red)
            .frame(minWidth: isRejecting ? 40 : 60)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.red.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isProcessing)
        .opacity(isProcessing && !isRejecting ? 0.5 : 1.0)
    }
    
    private func handleAccept() {
        if isProcessing { return }
        
        if isRejecting {
            return
        }
        
        isAccepting = true
        isRejecting = false
        
        Task { @MainActor in
            await viewModel.respondToRequest(request, action: "accept")
            isAccepting = false
        }
    }
    
    private func handleReject() {
        if isProcessing {
            return
        }
        
        if isAccepting {
            return
        }
        
        isRejecting = true
        isAccepting = false
        
        Task { @MainActor in
            await viewModel.respondToRequest(request, action: "reject")
            isRejecting = false
        }
    }
}
