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
    @StateObject private var folderViewModel = ChatFolderViewModel()
    
    @State private var showCreateChat = false
    @State private var showInvitations = false
    @State private var showCreateFolder = false
    @State private var showFolderMenu = false
    @State private var folderToManage: ChatFolder?
    @State private var roomToDelete: ChatRoom?
    @State private var showDeleteAlert = false
    @State private var roomForFolderSelection: ChatRoom?
    
    var body: some View {
        VStack(spacing: 0) {
            // 폴더 탭
            FolderTabView(
                    folders: viewModel.folders,
                    selectedFolderId: viewModel.selectedFolderId,
                    onFolderSelected: { folderId in
                        viewModel.selectFolder(folderId)
                    },
                    onCreateFolder: {
                        showCreateFolder = true
                    },
                    onFolderDelete: { folder in
                        Task {
                            #if DEBUG
                            print("🗑️ [ChatRoomListView] 폴더 삭제 시작 - ID: \(folder.id), Name: \(folder.name)")
                            #endif
                            
                            // 낙관적 업데이트: 즉시 UI에서 제거
                            let folderToRestore = folder
                            viewModel.folders.removeAll { $0.id == folder.id }
                            
                            do {
                                // API 직접 호출
                                try await NetworkManager.shared.chatService.deleteChatFolder(folderId: folder.id)
                                
                                #if DEBUG
                                print("✅ [ChatRoomListView] 폴더 삭제 API 호출 성공")
                                #endif
                                
                                // 성공 시 폴더 목록 새로고침 (동기화)
                                await viewModel.loadFolders()
                            } catch {
                                #if DEBUG
                                print("❌ [ChatRoomListView] 폴더 삭제 실패 - 롤백: \(error)")
                                #endif
                                // 실패 시 롤백
                                if !viewModel.folders.contains(where: { $0.id == folderToRestore.id }) {
                                    viewModel.folders.append(folderToRestore)
                                    viewModel.folders.sort { $0.order < $1.order }
                                }
                                viewModel.errorMessage = error.localizedDescription
                                viewModel.showError = true
                            }
                        }
                    }
                )
                
                // 채팅방 목록
                List {
                    if viewModel.isLoading && viewModel.filteredRooms.isEmpty {
                        // 초기 로딩 중일 때 스켈레톤 표시
                        ForEach(0..<5) { _ in
                            ChatRoomRowSkeletonView()
                                .listRowSeparator(.hidden)
                        }
                    } else {
                        ForEach(viewModel.filteredRooms) { room in
                            NavigationLink(value: room.id) {
                                ChatRoomRowView(room: room)
                            }
                            .contextMenu {
                                Button(action: {
                                    roomForFolderSelection = room
                                }) {
                                    Label("폴더에 추가", systemImage: "folder.badge.plus")
                                }
                                
                                Button(role: .destructive, action: {
                                    roomToDelete = room
                                    showDeleteAlert = true
                                }) {
                                    Label("삭제", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    roomToDelete = room
                                    showDeleteAlert = true
                                } label: {
                                    Label("삭제", systemImage: "trash")
                                        .foregroundColor(.white)
                                }
                                .tint(.red)
                            }
                        }
                    }
                }
            }
            .navigationTitle("채팅")
            .navigationDestination(for: String.self) { roomId in
                ChatRoomView(roomId: roomId)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        showInvitations = true
                    }) {
                        Image(systemName: "envelope")
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showCreateChat = true
                    }) {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .refreshable {
                await viewModel.refresh()
            }
            .task {
                // 한 번만 실행되도록 확인
                if !viewModel.isLoading && viewModel.rooms.isEmpty {
                    await viewModel.loadRooms()
                }
            }
            .sheet(isPresented: $showCreateChat) {
                CreateChatView { roomId in
                    Task {
                        await viewModel.refresh()
                    }
                }
            }
            .sheet(isPresented: $showInvitations, onDismiss: {
                Task {
                    await viewModel.refresh()
                }
            }) {
                ChatInvitationListView()
            }
            .sheet(isPresented: $showCreateFolder) {
                CreateFolderView { _ in
                    // 폴더 목록 새로고침
                    Task {
                        await viewModel.loadFolders()
                    }
                }
            }
            .sheet(item: $roomForFolderSelection) { room in
                FolderSelectionSheet(
                    folders: viewModel.folders,
                    currentFolderId: room.folderIds.first, // 현재 채팅방이 속한 첫 번째 폴더 ID
                    onFolderSelected: { folderId in
                        Task {
                            if let folderId = folderId {
                                // 기존 폴더에서 제거 후 새 폴더에 추가
                                if let currentFolderId = room.folderIds.first, currentFolderId != folderId {
                                    await viewModel.removeRoomFromFolder(folderId: currentFolderId, roomId: room.id)
                                }
                                await viewModel.addRoomToFolder(folderId: folderId, roomId: room.id)
                            } else {
                                // 폴더 없음 선택 시 기존 폴더에서 제거
                                if let currentFolderId = room.folderIds.first {
                                    await viewModel.removeRoomFromFolder(folderId: currentFolderId, roomId: room.id)
                                }
                            }
                            await viewModel.refresh()
                        }
                        roomForFolderSelection = nil
                    },
                    onCreateFolder: {
                        roomForFolderSelection = nil
                        showCreateFolder = true
                    }
                )
            }
            .confirmationDialog("폴더 관리", isPresented: $showFolderMenu, presenting: folderToManage) { folder in
                Button("이름 변경") {
                    // TODO: 폴더 이름 변경 구현
                }
                Button("삭제", role: .destructive) {
                    if let folder = folderToManage {
                        Task {
                            await folderViewModel.deleteFolder(folderId: folder.id)
                            await viewModel.loadFolders()
                        }
                    }
                }
                Button("취소", role: .cancel) { }
            }
            .alert("오류", isPresented: $viewModel.showError) {
                Button("확인", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage ?? "알 수 없는 오류가 발생했습니다.")
            }
            .alert("채팅방 삭제", isPresented: $showDeleteAlert) {
                Button("취소", role: .cancel) {
                    roomToDelete = nil
                }
                Button("예", role: .destructive) {
                    if let room = roomToDelete {
                        Task {
                            await viewModel.deleteRoom(roomId: room.id)
                        }
                    }
                    roomToDelete = nil
                }
            } message: {
                if let room = roomToDelete {
                    Text("'\(room.displayName)' 채팅방을 삭제하시겠습니까?")
                }
            }
    }
}

// MARK: - Folder Selection Sheet
struct FolderSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let folders: [ChatFolder]
    let currentFolderId: String?
    let onFolderSelected: (String?) -> Void
    let onCreateFolder: () -> Void
    
    var body: some View {
        NavigationStack {
            FolderSelectionView(
                folders: folders,
                currentFolderId: currentFolderId,
                onFolderSelected: { folderId in
                    onFolderSelected(folderId)
                    dismiss()
                },
                onCreateFolder: {
                    dismiss()
                    onCreateFolder()
                }
            )
            .navigationTitle("폴더 선택")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}


