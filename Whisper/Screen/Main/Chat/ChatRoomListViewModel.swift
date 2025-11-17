//
//  ChatRoomListViewModel.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation
import Combine

// MARK: - Chat Room List ViewModel
@MainActor
class ChatRoomListViewModel: ObservableObject {
    @Published var rooms: [ChatRoom] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showError = false
    
    private let apiService = NetworkManager.shared.chatService
    
    func loadRooms() async {
        isLoading = true
        errorMessage = nil
        
        do {
            rooms = try await apiService.fetchChatRooms()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        
        isLoading = false
    }
    
    func refresh() async {
        await loadRooms()
    }
}

