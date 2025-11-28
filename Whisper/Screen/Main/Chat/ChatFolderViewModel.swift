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
    
    func loadFolders(useCache: Bool = true) async {
        // 이미 로딩 중이면 중복 호출 방지
        guard !isLoading else {
            #if DEBUG
            print("⚠️ [ChatFolderViewModel] 이미 로딩 중 - 중복 호출 방지")
            #endif
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
        // 낙관적 업데이트: 임시 폴더 생성
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
            // 임시 폴더를 실제 폴더로 교체
            if let index = folders.firstIndex(where: { $0.id == tempFolder.id }) {
                folders[index] = folder
            }
        } catch {
            // 실패 시 롤백
            folders.removeAll { $0.id == tempFolder.id }
            errorMessage = error.localizedDescription
            showError = true
        }
        isLoading = false
    }
    
    func updateFolder(folderId: String, name: String?, color: String?, icon: String?) async {
        // 낙관적 업데이트: 즉시 UI 업데이트
        guard let index = folders.firstIndex(where: { $0.id == folderId }),
              let originalFolder = folders.first(where: { $0.id == folderId }) else {
            return
        }
        
        // 임시로 업데이트된 폴더 생성
        let updatedFolder = ChatFolder(
            id: folderId,
            name: name ?? originalFolder.name,
            color: color ?? originalFolder.color,
            icon: icon ?? originalFolder.icon,
            order: originalFolder.order,
            roomCount: originalFolder.roomCount,
            createdAt: originalFolder.createdAt,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        folders[index] = updatedFolder
        
        isLoading = true
        do {
            let result = try await apiService.updateChatFolder(folderId: folderId, name: name, color: color, icon: icon)
            folders[index] = result
        } catch {
            // 실패 시 롤백
            folders[index] = originalFolder
            errorMessage = error.localizedDescription
            showError = true
        }
        isLoading = false
    }
    
    func deleteFolder(folderId: String) async {
        // 낙관적 업데이트: 즉시 UI에서 제거
        guard let folderToDelete = folders.first(where: { $0.id == folderId }) else {
            #if DEBUG
            print("⚠️ [ChatFolderViewModel] 삭제할 폴더를 찾을 수 없음 - ID: \(folderId)")
            #endif
            return
        }
        
        folders.removeAll { $0.id == folderId }
        
        isLoading = true
        showError = false
        errorMessage = nil
        
        do {
            #if DEBUG
            print("📡 [ChatFolderViewModel] API 호출 시작 - deleteChatFolder(folderId: \(folderId))")
            #endif
            
            try await apiService.deleteChatFolder(folderId: folderId)
            
            #if DEBUG
            print("✅ [ChatFolderViewModel] 폴더 삭제 API 호출 성공")
            #endif
        } catch {
            #if DEBUG
            print("❌ [ChatFolderViewModel] 폴더 삭제 API 호출 실패: \(error)")
            #endif
            // 실패 시 롤백
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

