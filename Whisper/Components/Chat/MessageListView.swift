//
//  MessageListView.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import SwiftUI

// MARK: - Message List Component
struct MessageListView: View {
    let messages: [Message]
    let isLoadingMore: Bool
    let getDisplayContent: (Message) -> String
    let onLoadMore: () async -> Void
    let onEdit: ((Message) -> Void)?
    let onDelete: ((Message) -> Void)?
    let onMessageAppear: ((Message) -> Void)?
    
    @State private var hasScrolledToBottom = false
    @State private var isInitialLoad = true
    @State private var previousFirstMessageId: String? // 무한 스크롤 시 위치 복원용
    @State private var previousMessageCount: Int = 0
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if isLoadingMore {
                        LoadingMoreView()
                            .padding(.vertical, 8)
                    }
                    
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        let spacing = getSpacing(at: index, in: messages)
                        
                        MessageBubbleView(
                            message: message,
                            displayContent: getDisplayContent(message),
                            showTime: shouldShowTime(at: index, in: messages),
                            showReadStatus: shouldShowReadStatus(at: index, in: messages),
                            onEdit: onEdit,
                            onDelete: onDelete
                        )
                        .id(message.id)
                        .padding(.top, spacing)
                        .onAppear {
                            // 메시지가 화면에 나타날 때 읽음 처리
                            onMessageAppear?(message)
                            
                            // 상단 근처(첫 3개 메시지)에 도달하면 더 많은 메시지 로드 (무한 스크롤)
                            if index < 3 && !isLoadingMore {
                                // 현재 첫 번째 메시지 ID 저장 (스크롤 위치 복원용)
                                if !messages.isEmpty {
                                    previousFirstMessageId = messages.first?.id
                                    previousMessageCount = messages.count
                                }
                                Task {
                                    await onLoadMore()
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .onAppear {
                // 초기 로드 시 맨 아래로 스크롤 (애니메이션 없이 즉시)
                if isInitialLoad && !messages.isEmpty {
                    scrollToBottomImmediately(proxy: proxy)
                }
            }
            .onChange(of: messages.count) { oldCount, newCount in
                handleMessagesCountChange(
                    oldCount: oldCount,
                    newCount: newCount,
                    proxy: proxy
                )
            }
            .onChange(of: messages.last?.id) { oldId, newId in
                // 마지막 메시지가 변경되었을 때 (새 메시지 수신)
                // 단, 무한 스크롤로 인한 변경이 아닌 경우에만
                if let newId = newId, newId != oldId, !isInitialLoad {
                    // 무한 스크롤로 인한 변경인지 확인
                    let isInfiniteScrollChange = previousFirstMessageId != nil && 
                        messages.count > previousMessageCount
                    
                    if !isInfiniteScrollChange {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(newId, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Scroll Helpers
    
    /// 즉시 맨 아래로 스크롤 (애니메이션 없음)
    private func scrollToBottomImmediately(proxy: ScrollViewProxy) {
        guard let lastMessage = messages.last else { return }
        proxy.scrollTo(lastMessage.id, anchor: .bottom)
        hasScrolledToBottom = true
        isInitialLoad = false
    }
    
    /// 메시지 개수 변경 처리
    private func handleMessagesCountChange(oldCount: Int, newCount: Int, proxy: ScrollViewProxy) {
        // 초기 로드 완료 후 맨 아래로 스크롤
        if isInitialLoad && newCount > 0 && oldCount == 0 {
            scrollToBottomImmediately(proxy: proxy)
            return
        }
        
        // 무한 스크롤: 위에 메시지가 추가된 경우
        if newCount > oldCount && !isInitialLoad {
            let addedCount = newCount - oldCount
            
            // 위에 메시지가 추가된 경우 (무한 스크롤)
            if let previousId = previousFirstMessageId, addedCount > 0 {
                // 이전에 보던 메시지로 스크롤 위치 복원 (애니메이션 없이)
                proxy.scrollTo(previousId, anchor: .top)
                
                // 복원 완료 후 초기화
                previousFirstMessageId = nil
                previousMessageCount = newCount
            }
            // 아래에 메시지가 추가된 경우 (새 메시지 수신)
            else if previousFirstMessageId == nil, let lastMessage = messages.last {
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
        }
    }
    
    private func getSpacing(at index: Int, in messages: [Message]) -> CGFloat {
        guard index > 0 else { return 0 }
        
        let message = messages[index]
        let previousMessage = messages[index - 1]
        
        // 같은 사람이 보낸 메시지이고 같은 시간대(분 단위)면 spacing을 작게
        if message.sender.id == previousMessage.sender.id {
            guard let d1 = message.createdAtDate, let d2 = previousMessage.createdAtDate else {
                return 4
            }
            let c1 = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: d1)
            let c2 = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: d2)
            
            if c1 == c2 {
                // 같은 시간대: spacing을 작게 (2)
                return 2
            }
        }
        
        // 다른 사람이 보냈거나 시간이 다르면 기본 spacing (8)
        return 8
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let lastMessage = messages.last {
            withAnimation {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
    
    private func shouldShowTime(at index: Int, in messages: [Message]) -> Bool {
        let message = messages[index]
        let isLast = index == messages.count - 1
        
        // 마지막 메시지는 무조건 시간 표시
        if isLast { return true }
        
        let nextMessage = messages[index + 1]
        
        // 보낸 사람이 다르면 시간 표시
        if message.sender.id != nextMessage.sender.id { return true }
        
        // 시간이 다르면(분 단위) 표시
        guard let d1 = message.createdAtDate, let d2 = nextMessage.createdAtDate else { return true }
        let c1 = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: d1)
        let c2 = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: d2)
        
        return c1 != c2
    }
    
    private func shouldShowReadStatus(at index: Int, in messages: [Message]) -> Bool {
        let message = messages[index]
        
        // 내가 보낸 메시지가 아니면 읽음 상태 표시 안 함
        guard message.isFromCurrentUser else { return false }
        
        let isLast = index == messages.count - 1
        
        // 마지막 메시지는 무조건 읽음 상태 표시
        if isLast { return true }
        
        let nextMessage = messages[index + 1]
        
        // 다음 메시지가 다른 사람이 보낸 것이면 읽음 상태 표시
        if message.sender.id != nextMessage.sender.id { return true }
        
        // 다음 메시지가 같은 사람이 보낸 것이지만 시간이 다르면(분 단위) 읽음 상태 표시
        guard let d1 = message.createdAtDate, let d2 = nextMessage.createdAtDate else { return true }
        let c1 = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: d1)
        let c2 = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: d2)
        
        // 시간이 다르면 읽음 상태 표시 (같은 시간대 그룹의 마지막 메시지)
        return c1 != c2
    }
}

// MARK: - Loading More View
struct LoadingMoreView: View {
    var body: some View {
        HStack {
            Spacer()
            ProgressView()
                .padding()
            Spacer()
        }
    }
}

