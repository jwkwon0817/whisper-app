//
//  ChatInvitationListViewModel.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/24/25.
//

import Foundation
import Combine
import Moya

@MainActor
class ChatInvitationListViewModel: BaseViewModelImpl {
    @Published var invitations: [ChatInvitation] = []
    
    private let chatService = NetworkManager.shared.chatService
    
    override init() {
        super.init()
        loadInvitations()
    }
    
    func loadInvitations(useCache: Bool = true) {
        guard !isLoading else { return }
        
        _Concurrency.Task {
            isLoading = true
            defer { isLoading = false }
            
            do {
                #if DEBUG
                print("📥 [ChatInvitationViewModel] 초대 목록 로드 시작")
                #endif
                
                invitations = try await chatService.fetchAllChatInvitations(useCache: useCache)
                
                #if DEBUG
                print("✅ [ChatInvitationViewModel] 초대 목록 로드 성공: \(invitations.count)개")
                #endif
            } catch {
                #if DEBUG
                print("❌ [ChatInvitationViewModel] 초대 목록 로드 실패: \(error)")
                #endif
                
                errorMessage = "초대 목록을 불러올 수 없습니다."
                showError = true
            }
        }
    }
    
    func respondToInvitation(_ invitation: ChatInvitation, accept: Bool) {
        // 낙관적 업데이트: 즉시 목록에서 제거
        let invitationToRestore = invitation
        invitations.removeAll { $0.id == invitation.id }
        
        _Concurrency.Task {
            do {
                let action = accept ? "accept" : "reject"
                
                #if DEBUG
                print("📨 [ChatInvitationViewModel] 초대 응답: \(invitation.type) - \(action)")
                #endif
                
                if invitation.type == .direct {
                    // 1:1 채팅 초대 수락/거절
                    if accept {
                        if let chatRoom = try await chatService.respondToDirectChatInvitation(invitationId: invitation.id, action: action) {
                            #if DEBUG
                            print("✅ [ChatInvitationViewModel] 1:1 채팅 초대 수락 - 채팅방 생성: \(chatRoom.id)")
                            #endif
                        }
                    } else {
                        _ = try await chatService.respondToDirectChatInvitation(invitationId: invitation.id, action: action)
                        #if DEBUG
                        print("✅ [ChatInvitationViewModel] 1:1 채팅 초대 거절")
                        #endif
                    }
                } else {
                    // 그룹 채팅 초대 수락/거절
                    _ = try await chatService.respondToGroupChatInvitation(invitationId: invitation.id, action: action)
                    #if DEBUG
                    print("✅ [ChatInvitationViewModel] 그룹 채팅 초대 \(action)")
                    #endif
                }
                
                // 캐시 무효화 및 목록 새로고침
                await CacheManager.shared.remove(forKey: CacheKeys.chatInvitations())
                loadInvitations()
                
            } catch {
                #if DEBUG
                print("❌ [ChatInvitationViewModel] 초대 응답 실패: \(error)")
                #endif
                
                // 404 에러(이미 처리된 초대)인 경우 목록만 새로고침
                if let moyaError = error as? MoyaError, moyaError.response?.statusCode == 404 {
                    loadInvitations()
                    return
                }
                
                // 실패 시 롤백
                if !invitations.contains(where: { $0.id == invitationToRestore.id }) {
                    invitations.append(invitationToRestore)
                    // 날짜순 정렬 (최신순)
                    invitations.sort { $0.createdAt > $1.createdAt }
                }
                
                errorMessage = accept ? "초대 수락에 실패했습니다." : "초대 거절에 실패했습니다."
                showError = true
            }
        }
    }
}

