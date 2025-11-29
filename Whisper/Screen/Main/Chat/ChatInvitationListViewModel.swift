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
                invitations = try await chatService.fetchAllChatInvitations(useCache: useCache)
                
            } catch {
                errorMessage = "초대 목록을 불러올 수 없습니다."
                showError = true
            }
        }
    }
    
    func respondToInvitation(_ invitation: ChatInvitation, accept: Bool) {
        let invitationToRestore = invitation
        invitations.removeAll { $0.id == invitation.id }
        
        _Concurrency.Task {
            do {
                let action = accept ? "accept" : "reject"
                
                if invitation.type == .direct {
                    if accept {
                        if let chatRoom = try await chatService.respondToDirectChatInvitation(invitationId: invitation.id, action: action) {
                        }
                    } else {
                        _ = try await chatService.respondToDirectChatInvitation(invitationId: invitation.id, action: action)
                    }
                } else {
                    _ = try await chatService.respondToGroupChatInvitation(invitationId: invitation.id, action: action)
                }
                
                await CacheManager.shared.remove(forKey: CacheKeys.chatInvitations())
                loadInvitations()
                
            } catch {
                if let moyaError = error as? MoyaError, moyaError.response?.statusCode == 404 {
                    loadInvitations()
                    return
                }
                
                if !invitations.contains(where: { $0.id == invitationToRestore.id }) {
                    invitations.append(invitationToRestore)
                    invitations.sort { $0.createdAt > $1.createdAt }
                }
                
                errorMessage = accept ? "초대 수락에 실패했습니다." : "초대 거절에 실패했습니다."
                showError = true
            }
        }
    }
}

