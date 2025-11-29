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
class ChatRoomListViewModel: BaseViewModelImpl {
    @Published var rooms: [ChatRoom] = []
    @Published var folders: [ChatFolder] = []
    @Published var selectedFolderId: String? = nil
    
    private let apiService = NetworkManager.shared.chatService
    private let folderViewModel = ChatFolderViewModel()
    private let wsManager = ChatWebSocketManager.shared
    
    // 선택된 폴더에 따라 필터링된 채팅방 목록
    var filteredRooms: [ChatRoom] {
        guard let folderId = selectedFolderId else {
            // "전체" 탭: 모든 채팅방 표시
            return rooms
        }
        
        // 선택된 폴더에 속한 채팅방만 필터링
        return rooms.filter { $0.folderIds.contains(folderId) }
    }
    
    func loadRooms(useCache: Bool = true) async {
        // 이미 로딩 중이면 중복 호출 방지
        guard !isLoading else {
            #if DEBUG
            print("⚠️ [ChatRoomListViewModel] 이미 로딩 중 - 중복 호출 방지")
            #endif
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            // 캐시 사용 시 즉시 표시, 백그라운드에서 최신 데이터 가져오기
            rooms = try await apiService.fetchChatRooms(useCache: useCache)
            await loadFolders()
            
            // WebSocket 구독 설정 (최초 1회만)
            if cancellables.isEmpty {
                setupWebSocketSubscriptions()
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        
        isLoading = false
    }
    
    // MARK: - WebSocket 구독
    
    private func setupWebSocketSubscriptions() {
        // 기존 ChatWebSocketManager 구독 유지 (혹시 모를 호환성 위해)
        wsManager.receivedMessage
            .sink { [weak self] wsMessage in
                guard let self = self else { return }
                
                Task { @MainActor in
                    switch wsMessage.type {
                    case .chatMessage:
                        if let message = wsMessage.message {
                            await self.updateRoomWithNewMessage(message)
                        }
                    default:
                        break
                    }
                }
            }
            .store(in: &cancellables)
            
        // ✅ Global Notification 구독 (채팅방 리스트 갱신용)
        NotificationManager.shared.newMessageReceived
            .sink { [weak self] notification in
                Task { @MainActor in
                    await self?.handleNewMessageNotification(notification)
                }
            }
            .store(in: &cancellables)
        
        #if DEBUG
        print("✅ [ChatRoomListViewModel] WebSocket 구독 설정 완료")
        #endif
    }
    
    private func handleNewMessageNotification(_ notification: AppNotification) async {
        #if DEBUG
        print("🆕 [ChatRoomListViewModel] 새 메시지 알림 수신 - 리스트 갱신")
        #endif
        
        // 단순히 리스트를 새로고침하여 최신 상태(안읽은 갯수, 마지막 메시지) 반영
        // 낙관적 업데이트를 하기에는 Notification 데이터가 Message 모델과 완벽히 일치하지 않을 수 있음
        await loadRooms(useCache: false)
    }
    
    // MARK: - 채팅방 마지막 메시지 업데이트
    
    private func updateRoomWithNewMessage(_ message: Message) async {
        // 메시지가 속한 채팅방 찾기
        guard let roomIndex = rooms.firstIndex(where: { room in
            // message.room은 "direct 채팅방 (UUID)" 형식일 수 있으므로 포함 여부로 확인
            room.id == message.room || message.room.contains(room.id)
        }) else {
            // 새로운 채팅방이면 전체 리스트 새로고침 (이미 로딩 중이면 스킵)
            guard !isLoading else {
                #if DEBUG
                print("⚠️ [ChatRoomListViewModel] 이미 로딩 중 - 새 채팅방 리스트 새로고침 스킵")
                #endif
                return
            }
            
            #if DEBUG
            print("🆕 [ChatRoomListViewModel] 새로운 채팅방 메시지 감지 - 리스트 새로고침")
            #endif
            await loadRooms(useCache: false)
            return
        }
        
        let room = rooms[roomIndex]
        
        #if DEBUG
        print("📨 [ChatRoomListViewModel] 채팅방 마지막 메시지 업데이트")
        print("   Room ID: \(room.id)")
        print("   Message ID: \(message.id)")
        print("   Sender: \(message.sender?.name ?? "Unknown")")
        #endif
        
        // 낙관적 업데이트: 해당 채팅방을 리스트 맨 위로 이동
        rooms.remove(at: roomIndex)
        rooms.insert(room, at: 0)
        
        // 백그라운드에서 정확한 데이터로 갱신 (캐시도 무효화)
        Task {
            do {
                let freshRooms = try await apiService.fetchChatRooms(useCache: false)
                rooms = freshRooms
                
                #if DEBUG
                print("✅ [ChatRoomListViewModel] 채팅방 리스트 백그라운드 갱신 완료")
                #endif
            } catch {
                #if DEBUG
                print("⚠️ [ChatRoomListViewModel] 채팅방 리스트 갱신 실패: \(error)")
                #endif
            }
        }
    }
    
    func loadFolders() async {
        // 이미 로딩 중이면 중복 호출 방지
        guard !folderViewModel.isLoading else {
            #if DEBUG
            print("⚠️ [ChatRoomListViewModel] 폴더 이미 로딩 중 - 중복 호출 방지")
            #endif
            return
        }
        
        await folderViewModel.loadFolders()
        folders = folderViewModel.folders
        
        #if DEBUG
        print("📁 [ChatRoomListViewModel] 폴더 목록 동기화 완료 - 개수: \(folders.count)")
        #endif
    }
    
    func refresh() async {
        await loadRooms()
    }
    
    func deleteRoom(roomId: String) async {
        // 낙관적 업데이트: 즉시 UI에서 제거
        let roomToDelete = rooms.first { $0.id == roomId }
        rooms.removeAll { $0.id == roomId }
        
        do {
            try await apiService.leaveChatRoom(roomId: roomId)
            // 캐시 무효화
            await CacheManager.shared.remove(forKey: CacheKeys.chatRooms())
        } catch {
            // 실패 시 롤백
            if let room = roomToDelete {
                rooms.append(room)
                rooms.sort { ($0.updatedAtDate ?? Date.distantPast) > ($1.updatedAtDate ?? Date.distantPast) }
            }
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    func selectFolder(_ folderId: String?) {
        selectedFolderId = folderId
    }
    
    func addRoomToFolder(folderId: String, roomId: String) async {
        // 낙관적 업데이트: 즉시 UI 업데이트
        guard let index = rooms.firstIndex(where: { $0.id == roomId }) else {
            #if DEBUG
            print("⚠️ [ChatRoomListViewModel] 채팅방을 찾을 수 없음 - Room ID: \(roomId)")
            #endif
            return
        }
        
        let originalRoom = rooms[index]
        
        // folderIds에 추가된 새 ChatRoom 생성
        var newFolderIds = originalRoom.folderIds
        if !newFolderIds.contains(folderId) {
            newFolderIds.append(folderId)
        }
        
        let updatedRoom = ChatRoom(
            id: originalRoom.id,
            roomType: originalRoom.roomType,
            name: originalRoom.name,
            description: originalRoom.description,
            createdBy: originalRoom.createdBy,
            members: originalRoom.members,
            memberCount: originalRoom.memberCount,
            lastMessage: originalRoom.lastMessage,
            folderIds: newFolderIds,
            unreadCount: originalRoom.unreadCount,
            createdAt: originalRoom.createdAt,
            updatedAt: originalRoom.updatedAt
        )
        
        // 즉시 UI 업데이트
        rooms[index] = updatedRoom
        
        #if DEBUG
        print("✅ [ChatRoomListViewModel] 채팅방을 폴더에 추가 (낙관적 업데이트)")
        print("   Room ID: \(roomId)")
        print("   Folder ID: \(folderId)")
        print("   New folderIds: \(newFolderIds)")
        #endif
        
        // 백그라운드에서 API 호출
        do {
            try await apiService.addRoomToFolder(folderId: folderId, roomId: roomId)
            
            // 캐시 무효화
            await CacheManager.shared.remove(forKey: CacheKeys.chatRooms())
            
            #if DEBUG
            print("✅ [ChatRoomListViewModel] 폴더 추가 API 호출 성공")
            #endif
            
            // 최신 데이터로 갱신 (백그라운드, 이미 로딩 중이면 스킵)
            Task {
                guard !isLoading else { return }
                await loadRooms(useCache: false)
            }
        } catch {
            // 실패 시 롤백
            #if DEBUG
            print("❌ [ChatRoomListViewModel] 폴더 추가 API 호출 실패 - 롤백")
            #endif
            rooms[index] = originalRoom
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    func removeRoomFromFolder(folderId: String, roomId: String) async {
        // 낙관적 업데이트: 즉시 UI 업데이트
        guard let index = rooms.firstIndex(where: { $0.id == roomId }) else {
            #if DEBUG
            print("⚠️ [ChatRoomListViewModel] 채팅방을 찾을 수 없음 - Room ID: \(roomId)")
            #endif
            return
        }
        
        let originalRoom = rooms[index]
        
        // folderIds에서 제거된 새 ChatRoom 생성
        let newFolderIds = originalRoom.folderIds.filter { $0 != folderId }
        
        let updatedRoom = ChatRoom(
            id: originalRoom.id,
            roomType: originalRoom.roomType,
            name: originalRoom.name,
            description: originalRoom.description,
            createdBy: originalRoom.createdBy,
            members: originalRoom.members,
            memberCount: originalRoom.memberCount,
            lastMessage: originalRoom.lastMessage,
            folderIds: newFolderIds,
            unreadCount: originalRoom.unreadCount,
            createdAt: originalRoom.createdAt,
            updatedAt: originalRoom.updatedAt
        )
        
        // 즉시 UI 업데이트
        rooms[index] = updatedRoom
        
        #if DEBUG
        print("✅ [ChatRoomListViewModel] 채팅방을 폴더에서 제거 (낙관적 업데이트)")
        print("   Room ID: \(roomId)")
        print("   Folder ID: \(folderId)")
        print("   New folderIds: \(newFolderIds)")
        #endif
        
        // 백그라운드에서 API 호출
        do {
            try await apiService.removeRoomFromFolder(folderId: folderId, roomId: roomId)
            
            // 캐시 무효화
            await CacheManager.shared.remove(forKey: CacheKeys.chatRooms())
            
            #if DEBUG
            print("✅ [ChatRoomListViewModel] 폴더 제거 API 호출 성공")
            #endif
            
            // 최신 데이터로 갱신 (백그라운드, 이미 로딩 중이면 스킵)
            Task {
                guard !isLoading else { return }
                await loadRooms(useCache: false)
            }
        } catch {
            // 실패 시 롤백
            #if DEBUG
            print("❌ [ChatRoomListViewModel] 폴더 제거 API 호출 실패 - 롤백")
            #endif
            rooms[index] = originalRoom
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

