//
//  ChatRoomListViewModel.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation
import Combine

@MainActor
class ChatRoomListViewModel: BaseViewModelImpl {
    @Published var rooms: [ChatRoom] = []
    @Published var folders: [ChatFolder] = []
    @Published var selectedFolderId: String? = nil
    
    private let apiService = NetworkManager.shared.chatService
    private let folderViewModel = ChatFolderViewModel()
    private let wsManager = ChatWebSocketManager.shared
    
    var filteredRooms: [ChatRoom] {
        guard let folderId = selectedFolderId else {
            return rooms
        }
        
        return rooms.filter { $0.folderIds.contains(folderId) }
    }
    
    func loadRooms(useCache: Bool = true) async {
        guard !isLoading else {
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            rooms = try await apiService.fetchChatRooms(useCache: useCache)
            await loadFolders()
            
            if cancellables.isEmpty {
                setupWebSocketSubscriptions()
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        
        isLoading = false
    }
    
    private func setupWebSocketSubscriptions() {
        wsManager.receivedMessage
            .sink { [weak self] wsMessage in
                guard let self = self else { return }
                
                Task { @MainActor in
                    switch wsMessage.type {
                    case .chatMessage:
                        if let message = wsMessage.message {
                            await self.updateRoomWithNewMessage(message)
                        }
                    default:
                        break
                    }
                }
            }
            .store(in: &cancellables)
            
        NotificationManager.shared.newMessageReceived
            .sink { [weak self] notification in
                Task { @MainActor in
                    await self?.handleNewMessageNotification(notification)
                }
            }
            .store(in: &cancellables)
    }
    
    private func handleNewMessageNotification(_ notification: AppNotification) async {
        await loadRooms(useCache: false)
    }
    
    private func updateRoomWithNewMessage(_ message: Message) async {
        guard let roomIndex = rooms.firstIndex(where: { room in
            room.id == message.room || message.room.contains(room.id)
        }) else {
            guard !isLoading else {
                return
            }
            
            await loadRooms(useCache: false)
            return
        }
        
        let room = rooms[roomIndex]
        
        rooms.remove(at: roomIndex)
        rooms.insert(room, at: 0)
        
        Task {
            do {
                let freshRooms = try await apiService.fetchChatRooms(useCache: false)
                rooms = freshRooms
            } catch {
            }
        }
    }
    
    func loadFolders() async {
        guard !folderViewModel.isLoading else {
            return
        }
        
        await folderViewModel.loadFolders()
        folders = folderViewModel.folders
    }
    
    func refresh() async {
        await loadRooms()
    }
    
    func deleteRoom(roomId: String) async {
        let roomToDelete = rooms.first { $0.id == roomId }
        rooms.removeAll { $0.id == roomId }
        
        do {
            try await apiService.leaveChatRoom(roomId: roomId)
            await CacheManager.shared.remove(forKey: CacheKeys.chatRooms())
        } catch {
            if let room = roomToDelete {
                rooms.append(room)
                rooms.sort { ($0.updatedAtDate ?? Date.distantPast) > ($1.updatedAtDate ?? Date.distantPast) }
            }
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    func selectFolder(_ folderId: String?) {
        selectedFolderId = folderId
    }
    
    func addRoomToFolder(folderId: String, roomId: String) async {
        guard let index = rooms.firstIndex(where: { $0.id == roomId }) else {
            return
        }
        
        let originalRoom = rooms[index]
        
        var newFolderIds = originalRoom.folderIds
        if !newFolderIds.contains(folderId) {
            newFolderIds.append(folderId)
        }
        
        let updatedRoom = ChatRoom(
            id: originalRoom.id,
            roomType: originalRoom.roomType,
            name: originalRoom.name,
            description: originalRoom.description,
            createdBy: originalRoom.createdBy,
            members: originalRoom.members,
            memberCount: originalRoom.memberCount,
            lastMessage: originalRoom.lastMessage,
            folderIds: newFolderIds,
            unreadCount: originalRoom.unreadCount,
            createdAt: originalRoom.createdAt,
            updatedAt: originalRoom.updatedAt
        )
        
        rooms[index] = updatedRoom
        
        do {
            try await apiService.addRoomToFolder(folderId: folderId, roomId: roomId)
            
            await CacheManager.shared.remove(forKey: CacheKeys.chatRooms())
            
            Task {
                guard !isLoading else { return }
                await loadRooms(useCache: false)
            }
        } catch {
            rooms[index] = originalRoom
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    func removeRoomFromFolder(folderId: String, roomId: String) async {
        guard let index = rooms.firstIndex(where: { $0.id == roomId }) else {
            return
        }
        
        let originalRoom = rooms[index]
        
        let newFolderIds = originalRoom.folderIds.filter { $0 != folderId }
        
        let updatedRoom = ChatRoom(
            id: originalRoom.id,
            roomType: originalRoom.roomType,
            name: originalRoom.name,
            description: originalRoom.description,
            createdBy: originalRoom.createdBy,
            members: originalRoom.members,
            memberCount: originalRoom.memberCount,
            lastMessage: originalRoom.lastMessage,
            folderIds: newFolderIds,
            unreadCount: originalRoom.unreadCount,
            createdAt: originalRoom.createdAt,
            updatedAt: originalRoom.updatedAt
        )
        
        rooms[index] = updatedRoom
        
        do {
            try await apiService.removeRoomFromFolder(folderId: folderId, roomId: roomId)
            
            await CacheManager.shared.remove(forKey: CacheKeys.chatRooms())
            
            Task {
                guard !isLoading else { return }
                await loadRooms(useCache: false)
            }
        } catch {
            rooms[index] = originalRoom
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

