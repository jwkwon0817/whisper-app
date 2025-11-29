//
//  FriendListViewModel.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Combine
import Foundation

@MainActor
class FriendListViewModel: BaseViewModelImpl {
    @Published var friends: [Friend] = []
    
    private let apiService = NetworkManager.shared.friendService
    private let notificationManager = NotificationManager.shared
    
    override init() {
        super.init()
        setupNotificationSubscription()
    }
    
    private func setupNotificationSubscription() {
        notificationManager.friendRequestReceived
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                _ = _Concurrency.Task {
                    await self.loadFriends(useCache: false)
                }
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .friendRequestAccepted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                _ = _Concurrency.Task {
                    await self.loadFriends(useCache: false)
                }
            }
            .store(in: &cancellables)
    }
    
    func loadFriends(useCache: Bool = true) async {
        isLoading = true
        errorMessage = nil
        
        do {
            friends = try await apiService.fetchFriends(useCache: useCache)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        
        isLoading = false
    }
    
    func deleteFriend(_ friend: Friend) async {
        let friendToRestore = friend
        friends.removeAll { $0.id == friend.id }
        
        do {
            try await apiService.deleteFriend(friendId: friend.id)
        } catch {
            if !friends.contains(where: { $0.id == friendToRestore.id }) {
                friends.append(friendToRestore)
                friends.sort(by: { (friend1: Friend, friend2: Friend) -> Bool in
                    friend1.user.name < friend2.user.name
                })
            }
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    func refresh() async {
        await loadFriends()
    }
}
