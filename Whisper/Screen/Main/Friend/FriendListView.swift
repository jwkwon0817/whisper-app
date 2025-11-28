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
            Group {
                if viewModel.isLoading && viewModel.friends.isEmpty {
                    // 초기 로딩 중일 때 스켈레톤 표시
                    List {
                        ForEach(0..<5) { _ in
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
                // 받은 친구 요청 섹션
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
                
                // 친구 요청 보내기 섹션
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
    @ObservedObject var viewModel: FriendRequestViewModel
    @State private var isAccepting = false
    @State private var isRejecting = false
    
    private var isProcessing: Bool {
        isAccepting || isRejecting || viewModel.isProcessing(request.id)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // 프로필 이미지
            profileImageView
            
            // 사용자 정보
            VStack(alignment: .leading, spacing: 4) {
                Text(request.requester.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text("친구 요청")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // 액션 버튼들
            actionButtons
        }
        .contentShape(Rectangle())
    }
    
    // MARK: - Profile Image View
    private var profileImageView: some View {
        Group {
            if let profileImageUrl = request.requester.profileImage,
               let url = URL(string: profileImageUrl) {
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
    
    // MARK: - Action Buttons
    private var actionButtons: some View {
        HStack(spacing: 8) {
            // 수락 버튼 (먼저 배치)
            acceptButton
            
            // 거절 버튼
            rejectButton
        }
    }
    
    private var acceptButton: some View {
        Button(action: {
            #if DEBUG
            print("🟢 [FriendRequestRowView] 수락 버튼 직접 클릭 감지 - friendId: \(request.id)")
            #endif
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
            #if DEBUG
            print("🔴 [FriendRequestRowView] 거절 버튼 직접 클릭 감지 - friendId: \(request.id)")
            #endif
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
    
    // MARK: - Actions
    private func handleAccept() {
        // 이미 처리 중이면 무시
        if isProcessing {
            #if DEBUG
            print("⚠️ [FriendRequestRowView] 이미 처리 중 - 수락 무시")
            #endif
            return
        }
        
        // 거절 중이면 무시
        if isRejecting {
            #if DEBUG
            print("⚠️ [FriendRequestRowView] 거절 처리 중 - 수락 무시")
            #endif
            return
        }
        
        #if DEBUG
        print("✅ [FriendRequestRowView] handleAccept 호출 - friendId: \(request.id), action: accept")
        #endif
        
        // 수락 상태로 변경
        isAccepting = true
        isRejecting = false
        
        // 비동기 작업 실행
        Task { @MainActor in
            #if DEBUG
            print("🔄 [FriendRequestRowView] 수락 API 호출 시작")
            #endif
            await viewModel.respondToRequest(request, action: "accept")
            isAccepting = false
            #if DEBUG
            print("✅ [FriendRequestRowView] 수락 API 호출 완료")
            #endif
        }
    }
    
    private func handleReject() {
        // 이미 처리 중이면 무시
        if isProcessing {
            #if DEBUG
            print("⚠️ [FriendRequestRowView] 이미 처리 중 - 거절 무시")
            #endif
            return
        }
        
        // 수락 중이면 무시
        if isAccepting {
            #if DEBUG
            print("⚠️ [FriendRequestRowView] 수락 처리 중 - 거절 무시")
            #endif
            return
        }
        
        #if DEBUG
        print("❌ [FriendRequestRowView] handleReject 호출 - friendId: \(request.id), action: reject")
        #endif
        
        // 거절 상태로 변경
        isRejecting = true
        isAccepting = false
        
        // 비동기 작업 실행
        Task { @MainActor in
            #if DEBUG
            print("🔄 [FriendRequestRowView] 거절 API 호출 시작")
            #endif
            await viewModel.respondToRequest(request, action: "reject")
            isRejecting = false
            #if DEBUG
            print("✅ [FriendRequestRowView] 거절 API 호출 완료")
            #endif
        }
    }
}

