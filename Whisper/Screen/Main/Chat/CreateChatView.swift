//
//  CreateChatView.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import SwiftUI

struct CreateChatView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var friendListViewModel = FriendListViewModel()
    @State private var selectedChatType: ChatType = .direct
    @State private var selectedFriend: Friend?
    @State private var groupName = ""
    @State private var groupDescription = ""
    @State private var selectedFriends: Set<Friend> = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showSuccess = false
    @State private var successMessage: String?
    
    var onChatCreated: ((String) -> Void)? = nil
    
    enum ChatType {
        case direct
        case group
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    Picker("채팅 타입", selection: $selectedChatType) {
                        Text("1:1 채팅").tag(ChatType.direct)
                        Text("그룹 채팅").tag(ChatType.group)
                    }
                    .pickerStyle(.segmented)
                }
                
                if selectedChatType == .direct {
                    Section {
                        if friendListViewModel.friends.isEmpty {
                            Text("친구가 없습니다.")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(friendListViewModel.friends) { friend in
                                Button(action: {
                                    selectedFriend = friend
                                }) {
                                    HStack {
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
                                            .frame(width: 40, height: 40)
                                            .clipShape(Circle())
                                        } else {
                                            Circle()
                                                .fill(Color.gray.opacity(0.2))
                                                .frame(width: 40, height: 40)
                                                .overlay {
                                                    Image(systemName: "person.fill")
                                                }
                                        }
                                        
                                        Text(friend.otherUser.name)
                                            .foregroundColor(.primary)
                                        
                                        Spacer()
                                        
                                        if selectedFriend?.id == friend.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.blue)
                                        }
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("친구 선택")
                    }
                } else {
                    Section {
                        TextField("그룹 이름", text: $groupName)
                            .padding(.vertical, 16)
                            .padding(.horizontal, 20)
                        TextField("설명 (선택사항)", text: $groupDescription, axis: .vertical)
                            .padding(.vertical, 16)
                            .padding(.horizontal, 20)
                            .lineLimit(2...4)
                    } header: {
                        Text("그룹 정보")
                    }
                    
                    Section {
                        if friendListViewModel.friends.isEmpty {
                            Text("친구가 없습니다.")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(friendListViewModel.friends) { friend in
                                Button(action: {
                                    if selectedFriends.contains(friend) {
                                        selectedFriends.remove(friend)
                                    } else {
                                        selectedFriends.insert(friend)
                                    }
                                }) {
                                    HStack {
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
                                            .frame(width: 40, height: 40)
                                            .clipShape(Circle())
                                        } else {
                                            Circle()
                                                .fill(Color.gray.opacity(0.2))
                                                .frame(width: 40, height: 40)
                                                .overlay {
                                                    Image(systemName: "person.fill")
                                                }
                                        }
                                        
                                        Text(friend.otherUser.name)
                                            .foregroundColor(.primary)
                                        
                                        Spacer()
                                        
                                        if selectedFriends.contains(friend) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.blue)
                                        }
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("멤버 선택")
                    } footer: {
                        if !selectedFriends.isEmpty {
                            Text("\(selectedFriends.count)명 선택됨")
                        }
                    }
                }
                
                Section {
                    Button(action: {
                        Task {
                            await createChat()
                        }
                    }) {
                        HStack {
                            Spacer()
                            if isLoading {
                                ProgressView()
                            } else {
                                Text(selectedChatType == .direct ? "초대 보내기" : "그룹 만들기")
                            }
                            Spacer()
                        }
                    }
                    .disabled(!canCreate)
                }
            }
            .navigationTitle(selectedChatType == .direct ? "1:1 채팅" : "그룹 채팅")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("취소") {
                        dismiss()
                    }
                }
            }
            .task {
                await friendListViewModel.loadFriends()
            }
            .alert("오류", isPresented: $showError) {
                Button("확인", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "알 수 없는 오류가 발생했습니다.")
            }
            .alert("성공", isPresented: $showSuccess) {
                Button("확인", role: .cancel) {
                    dismiss()
                }
            } message: {
                Text(successMessage ?? "초대를 보냈습니다.")
            }
        }
    }
    
    private var canCreate: Bool {
        if isLoading {
            return false
        }
        
        if selectedChatType == .direct {
            return selectedFriend != nil
        } else {
            return !groupName.isEmpty && !selectedFriends.isEmpty
        }
    }
    
    private func createChat() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let chatService = NetworkManager.shared.chatService
            
            if selectedChatType == .direct {
                guard let friend = selectedFriend else {
                    errorMessage = "친구를 선택해주세요."
                    showError = true
                    isLoading = false
                    return
                }
                
                _ = try await chatService.createDirectChat(userId: friend.otherUser.id)
                
                successMessage = "\(friend.otherUser.name)님에게 1:1 채팅 초대를 보냈습니다.\n상대방이 수락하면 채팅을 시작할 수 있습니다."
                showSuccess = true
                
            } else {
                guard !groupName.isEmpty else {
                    errorMessage = "그룹 이름을 입력해주세요."
                    showError = true
                    isLoading = false
                    return
                }
                
                guard !selectedFriends.isEmpty else {
                    errorMessage = "최소 1명의 멤버를 선택해주세요."
                    showError = true
                    isLoading = false
                    return
                }
                
                let memberIds = selectedFriends.map { $0.otherUser.id }
                let room = try await chatService.createGroupChat(
                    name: groupName,
                    description: groupDescription.isEmpty ? nil : groupDescription,
                    memberIds: memberIds
                )
                
                successMessage = "\(groupName) 그룹이 생성되었습니다.\n멤버들에게 초대가 전송되었습니다."
                showSuccess = true
                
                onChatCreated?(room.id)
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        
        isLoading = false
    }
}

