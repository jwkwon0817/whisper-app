//
//  ChatFolderViewModel.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation
import Combine

@MainActor
class ChatFolderViewModel: ObservableObject {
    @Published var folders: [ChatFolder] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showError = false
    
    private let apiService = NetworkManager.shared.chatService
    
    func loadFolders(useCache: Bool = true) async {
        guard !isLoading else {
            return
        }
        
        isLoading = true
        do {
            folders = try await apiService.fetchChatFolders(useCache: useCache)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isLoading = false
    }
    
    func createFolder(name: String, color: String = "#000000", icon: String = "folder.fill") async {
        let tempFolder = ChatFolder(
            id: UUID().uuidString,
            name: name,
            color: color,
            icon: icon,
            order: folders.count,
            roomCount: 0,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        folders.append(tempFolder)
        
        isLoading = true
        do {
            let folder = try await apiService.createChatFolder(name: name, color: color, icon: icon)
            if let index = folders.firstIndex(where: { $0.id == tempFolder.id }) {
                folders[index] = folder
            }
        } catch {
            folders.removeAll { $0.id == tempFolder.id }
            errorMessage = error.localizedDescription
            showError = true
        }
        isLoading = false
    }
    
    func deleteFolder(folderId: String) async {
        guard let folderToDelete = folders.first(where: { $0.id == folderId }) else {
            return
        }
        
        folders.removeAll { $0.id == folderId }
        
        isLoading = true
        showError = false
        errorMessage = nil
        
        do {
            try await apiService.deleteChatFolder(folderId: folderId)
        } catch {
            folders.append(folderToDelete)
            folders.sort { $0.order < $1.order }
            errorMessage = error.localizedDescription
            showError = true
        }
        isLoading = false
    }
    
    func addRoomToFolder(folderId: String, roomId: String) async {
        isLoading = true
        do {
            try await apiService.addRoomToFolder(folderId: folderId, roomId: roomId)
            await loadFolders()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isLoading = false
    }
    
    func removeRoomFromFolder(folderId: String, roomId: String) async {
        isLoading = true
        do {
            try await apiService.removeRoomFromFolder(folderId: folderId, roomId: roomId)
            await loadFolders()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isLoading = false
    }
    
    func refresh() async {
        await loadFolders()
    }
}

