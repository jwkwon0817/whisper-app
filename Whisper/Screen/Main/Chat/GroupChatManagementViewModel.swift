//
//  GroupChatManagementViewModel.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation
import Combine

// MARK: - Group Chat Management ViewModel
@MainActor
class GroupChatManagementViewModel: ObservableObject {
    @Published var room: ChatRoom?
    @Published var invitations: [GroupChatInvitation] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showError = false
    
    private let apiService = NetworkManager.shared.chatService
    
    init(roomId: String) {
        loadRoom(roomId: roomId)
    }
    
    func loadRoom(roomId: String) {
        Task {
            isLoading = true
            do {
                room = try await apiService.fetchChatRoomDetail(roomId: roomId)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            isLoading = false
        }
    }
    
    func updateRoom(name: String?, description: String?) async {
        guard let roomId = room?.id else { return }
        isLoading = true
        do {
            room = try await apiService.updateChatRoom(roomId: roomId, name: name, description: description)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isLoading = false
    }
    
    func addMembers(userIds: [String]) async {
        guard let roomId = room?.id else { return }
        isLoading = true
        do {
            try await apiService.addChatRoomMembers(roomId: roomId, userIds: userIds)
            await loadRoom(roomId: roomId)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isLoading = false
    }
    
    func removeMember(userId: String) async {
        guard let roomId = room?.id else { return }
        isLoading = true
        do {
            try await apiService.removeChatRoomMember(roomId: roomId, userId: userId)
            await loadRoom(roomId: roomId)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isLoading = false
    }
    
    func sendInvitation(userId: String) async {
        guard let roomId = room?.id else { return }
        isLoading = true
        do {
            _ = try await apiService.sendGroupChatInvitation(roomId: roomId, userId: userId)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isLoading = false
    }
    
    func loadInvitations() async {
        isLoading = true
        do {
            invitations = try await apiService.fetchGroupChatInvitations()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isLoading = false
    }
    
    func respondToInvitation(invitationId: String, action: String) async {
        isLoading = true
        do {
            _ = try await apiService.respondToGroupChatInvitation(invitationId: invitationId, action: action)
            invitations.removeAll { $0.id == invitationId }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isLoading = false
    }
}

