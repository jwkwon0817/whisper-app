//
//  FriendRequestViewModel.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation
import Combine

// MARK: - Friend Request ViewModel
@MainActor
class FriendRequestViewModel: ObservableObject {
    @Published var receivedRequests: [Friend] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var phoneNumber = ""
    
    private let apiService = NetworkManager.shared.friendService
    private let notificationManager = NotificationManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupNotificationSubscription()
    }
    
    // MARK: - 알림 구독 설정
    private func setupNotificationSubscription() {
        notificationManager.friendRequestReceived
            .sink { [weak self] _ in
                Task { @MainActor in
                    // 친구 요청 알림이 오면 자동으로 목록 새로고침
                    await self?.loadReceivedRequests()
                }
            }
            .store(in: &cancellables)
    }
    
    func loadReceivedRequests() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let allRequests = try await apiService.fetchReceivedFriendRequests()
            receivedRequests = allRequests.filter { $0.status == .pending }
            // 알림 카운트 업데이트
            notificationManager.friendRequestCount = receivedRequests.count
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        
        isLoading = false
    }
    
    func sendFriendRequest() async {
        guard !phoneNumber.isEmpty else {
            errorMessage = "전화번호를 입력해주세요."
            showError = true
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            try await apiService.sendFriendRequest(phoneNumber: phoneNumber)
            phoneNumber = ""
        } catch {
            // 디코딩 오류인 경우 더 친화적인 메시지 표시
            if let decodingError = error as? DecodingError {
                errorMessage = "서버 응답 형식이 예상과 다릅니다."
            } else {
                errorMessage = error.localizedDescription
            }
            showError = true
        }
        
        isLoading = false
    }
    
    func respondToRequest(_ friend: Friend, action: String) async {
        do {
            _ = try await apiService.respondToFriendRequest(friendId: friend.id, action: action)
            receivedRequests.removeAll { $0.id == friend.id }
            // 알림 카운트 업데이트
            notificationManager.friendRequestCount = receivedRequests.count
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    func refresh() async {
        await loadReceivedRequests()
    }
}

