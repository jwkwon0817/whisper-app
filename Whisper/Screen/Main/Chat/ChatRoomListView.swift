//
//  ChatRoomListView.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import SwiftUI

struct ChatRoomListView: View {
    @StateObject private var viewModel = ChatRoomListViewModel()
    @StateObject private var folderViewModel = ChatFolderViewModel()
    
    @State private var showCreateChat = false
    @State private var showInvitations = false
    @State private var showCreateFolder = false
    @State private var roomForFolderSelection: ChatRoom?
    
    var body: some View {
        VStack(spacing: 0) {
            FolderTabView(
                    folders: viewModel.folders,
                    selectedFolderId: viewModel.selectedFolderId,
                    onFolderSelected: { folderId in
                        viewModel.selectFolder(folderId)
                    },
                    onCreateFolder: {
                        showCreateFolder = true
                    },
                    onFolderDelete: { _ in }
                )
                
                List {
                    if viewModel.isLoading && viewModel.filteredRooms.isEmpty {
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
            .alert("오류", isPresented: $viewModel.showError) {
                Button("확인", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage ?? "알 수 없는 오류가 발생했습니다.")
            }
    }
}

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


