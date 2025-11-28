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
            let allRequests = try await apiService.fetchReceivedFriendRequests(useCache: useCache)
            receivedRequests = allRequests.filter { $0.status == .pending }
            // 알림 카운트 업데이트
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
            
            #if DEBUG
            print("✅ [FriendRequestViewModel] 친구 요청 전송 성공")
            #endif
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
    
    @MainActor
    func respondToRequest(_ friend: Friend, action: String) async {
        // 이미 처리 중인 요청이면 무시
        guard !processingRequestIds.contains(friend.id) else {
            #if DEBUG
            print("⚠️ [FriendRequestViewModel] 이미 처리 중인 친구 요청: \(friend.id)")
            #endif
            return
        }
        
        #if DEBUG
        print("🔵 [FriendRequestViewModel] 친구 요청 처리 시작 - friendId: \(friend.id), action: \(action)")
        #endif
        
        // 처리 중 표시
        processingRequestIds.insert(friend.id)
        defer {
            processingRequestIds.remove(friend.id)
        }
        
        // 낙관적 업데이트: 즉시 목록에서 제거
        let requestToRestore = friend
        receivedRequests.removeAll { $0.id == friend.id }
        notificationManager.friendRequestCount = receivedRequests.count
        
        do {
            let result = try await apiService.respondToFriendRequest(friendId: friend.id, action: action)
            
            #if DEBUG
            print("🔵 [FriendRequestViewModel] API 응답 - status: \(result.status)")
            #endif
            
            #if DEBUG
            print("✅ [FriendRequestViewModel] 친구 요청 \(action) 성공: \(friend.id)")
            #endif
            
            // 수락한 경우 친구 목록 캐시 무효화 (FriendListViewModel이 자동 갱신할 수 있도록)
            if action == "accept" {
                await CacheManager.shared.remove(forKey: CacheKeys.friends())
            }
        } catch {
            // 실패 시 롤백
            if !receivedRequests.contains(where: { $0.id == requestToRestore.id }) {
                receivedRequests.append(requestToRestore)
                notificationManager.friendRequestCount = receivedRequests.count
            }
            #if DEBUG
            print("❌ [FriendRequestViewModel] 친구 요청 처리 실패 - error: \(error)")
            if let moyaError = error as? MoyaError {
                switch moyaError {
                case .statusCode(let response):
                    print("❌ Status Code: \(response.statusCode)")
                    if let responseData = String(data: response.data, encoding: .utf8) {
                        print("❌ Response Body: \(responseData)")
                    }
                default:
                    break
                }
            }
            #endif
            
            // 404 에러는 이미 처리된 요청으로 간주하고 목록에서 제거
            if let moyaError = error as? MoyaError,
               case .statusCode(let response) = moyaError,
               response.statusCode == 404
            {
                #if DEBUG
                print("⚠️ [FriendRequestViewModel] 친구 요청을 찾을 수 없음 (이미 처리됨): \(friend.id)")
                #endif
                // 이미 처리된 요청이므로 목록에서 제거
                receivedRequests.removeAll { $0.id == friend.id }
                notificationManager.friendRequestCount = receivedRequests.count
            } else {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
    
    // 특정 친구 요청이 처리 중인지 확인
    func isProcessing(_ friendId: String) -> Bool {
        return processingRequestIds.contains(friendId)
    }
    
    @MainActor
    func refresh() async {
        await loadReceivedRequests()
    }
}
