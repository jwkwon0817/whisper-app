//
//  FriendListViewModel.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation
import Combine

// MARK: - Friend List ViewModel
@MainActor
class FriendListViewModel: ObservableObject {
    @Published var friends: [Friend] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showError = false
    
    private let apiService = NetworkManager.shared.friendService
    
    func loadFriends() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let allFriends = try await apiService.fetchFriends()
            // 수락된 친구만 필터링
            friends = allFriends.filter { $0.status == .accepted }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        
        isLoading = false
    }
    
    func deleteFriend(_ friend: Friend) async {
        do {
            try await apiService.deleteFriend(friendId: friend.id)
            friends.removeAll { $0.id == friend.id }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    func refresh() async {
        await loadFriends()
    }
}

