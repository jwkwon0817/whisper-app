//
//  ChatFolderViewModel.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation
import Combine

// MARK: - Chat Folder ViewModel
@MainActor
class ChatFolderViewModel: ObservableObject {
    @Published var folders: [ChatFolder] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showError = false
    
    private let apiService = NetworkManager.shared.chatService
    
    func loadFolders() async {
        isLoading = true
        do {
            folders = try await apiService.fetchChatFolders()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isLoading = false
    }
    
    func createFolder(name: String, color: String = "#000000") async {
        isLoading = true
        do {
            let folder = try await apiService.createChatFolder(name: name, color: color)
            folders.append(folder)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isLoading = false
    }
    
    func updateFolder(folderId: String, name: String?, color: String?) async {
        isLoading = true
        do {
            let updatedFolder = try await apiService.updateChatFolder(folderId: folderId, name: name, color: color)
            if let index = folders.firstIndex(where: { $0.id == folderId }) {
                folders[index] = updatedFolder
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isLoading = false
    }
    
    func deleteFolder(folderId: String) async {
        isLoading = true
        do {
            try await apiService.deleteChatFolder(folderId: folderId)
            folders.removeAll { $0.id == folderId }
        } catch {
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

