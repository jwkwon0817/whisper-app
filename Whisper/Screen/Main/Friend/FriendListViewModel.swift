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
class FriendListViewModel: BaseViewModelImpl {
    @Published var friends: [Friend] = []
    
    private let apiService = NetworkManager.shared.friendService
    private let notificationManager = NotificationManager.shared
    
    override init() {
        super.init()
        setupNotificationSubscription()
    }
    
    private func setupNotificationSubscription() {
        // 친구 요청 수신 시 목록 갱신 (친구가 추가될 수 있으므로)
        notificationManager.friendRequestReceived
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                // 친구 요청을 받았다는 것은 상대방이 나를 추가했다는 의미일 수 있음
                // 또는 내가 보낸 요청이 수락되었을 수도 있음
                _ = _Concurrency.Task {
                    await self.loadFriends(useCache: false)
                }
            }
            .store(in: &cancellables)
        
        // 친구 요청 수락 시 목록 갱신
        NotificationCenter.default.publisher(for: .friendRequestAccepted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                #if DEBUG
                print("📬 [FriendListViewModel] 친구 수락 알림 수신 - 목록 갱신")
                #endif
                _ = _Concurrency.Task {
                    await self.loadFriends(useCache: false)
                }
            }
            .store(in: &cancellables)
        
        #if DEBUG
        print("✅ [FriendListViewModel] 알림 구독 설정 완료")
        #endif
    }
    
    func loadFriends(useCache: Bool = true) async {
        isLoading = true
        errorMessage = nil
        
        do {
            // 백엔드에서 이미 수락된 친구만 반환하므로 필터링 불필요
            friends = try await apiService.fetchFriends(useCache: useCache)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        
        isLoading = false
    }
    
    func deleteFriend(_ friend: Friend) async {
        // 낙관적 업데이트: 즉시 UI에서 제거
        let friendToRestore = friend
        friends.removeAll { $0.id == friend.id }
        
        do {
            try await apiService.deleteFriend(friendId: friend.id)
        } catch {
            // 실패 시 롤백
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

