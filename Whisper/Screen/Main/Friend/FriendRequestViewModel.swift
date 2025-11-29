//
//  FriendRequestViewModel.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Combine
import Foundation
import Moya

class FriendRequestViewModel: ObservableObject {
    @Published var receivedRequests: [Friend] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var phoneNumber = ""
    
    private var processingRequestIds: Set<String> = []
    
    private let apiService = NetworkManager.shared.friendService
    private let notificationManager = NotificationManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupNotificationSubscription()
    }
    
    private func setupNotificationSubscription() {
        notificationManager.friendRequestReceived
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                _ = _Concurrency.Task {
                    await self.loadReceivedRequests()
                }
            }
            .store(in: &cancellables)
    }
    
    @MainActor
    func loadReceivedRequests(useCache: Bool = true) async {
        isLoading = true
        errorMessage = nil
        
        do {
            receivedRequests = try await apiService.fetchReceivedFriendRequests(useCache: useCache)
            notificationManager.friendRequestCount = receivedRequests.count
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        
        isLoading = false
    }
    
    @MainActor
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
            if let decodingError = error as? DecodingError {
                errorMessage = "서버 응답 형식이 예상과 다릅니다."
            } else {
                errorMessage = error.localizedDescription
            }
            showError = true
        }
        
        isLoading = false
    }
    
    @MainActor
    func respondToRequest(_ friend: Friend, action: String) async {
        guard !processingRequestIds.contains(friend.id) else {
            return
        }
        
        processingRequestIds.insert(friend.id)
        defer {
            processingRequestIds.remove(friend.id)
        }
        
        let requestToRestore = friend
        receivedRequests.removeAll { $0.id == friend.id }
        notificationManager.friendRequestCount = receivedRequests.count
        
        do {
            try await apiService.respondToFriendRequest(friendId: friend.id, action: action)
            
            if action == "accept" {
                await CacheManager.shared.remove(forKey: CacheKeys.friends())
                
                NotificationCenter.default.post(name: .friendRequestAccepted, object: nil)
            }
        } catch {
            if !receivedRequests.contains(where: { $0.id == requestToRestore.id }) {
                receivedRequests.append(requestToRestore)
                notificationManager.friendRequestCount = receivedRequests.count
            }
            if let moyaError = error as? MoyaError,
               case .statusCode(let response) = moyaError,
               response.statusCode == 404
            {
                receivedRequests.removeAll { $0.id == friend.id }
                notificationManager.friendRequestCount = receivedRequests.count
            } else {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
    
    func isProcessing(_ friendId: String) -> Bool {
        return processingRequestIds.contains(friendId)
    }
    
    @MainActor
    func refresh() async {
        await loadReceivedRequests()
    }
}
