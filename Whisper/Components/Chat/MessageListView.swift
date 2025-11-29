//
//  MessageListView.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import SwiftUI

struct MessageListView: View {
    let messages: [Message]
    let isLoadingMore: Bool
    let getDisplayContent: (Message) -> String
    let getReplyToDisplayContent: (ReplyToMessage) -> String
    let onLoadMore: () async -> Void
    let onEdit: ((Message) -> Void)?
    let onDelete: ((Message) -> Void)?
    let onReply: ((Message) -> Void)?
    let onMessageAppear: ((Message) -> Void)?
    
    @State private var hasScrolledToBottom = false
    @State private var isInitialLoad = true
    @State private var previousFirstMessageId: String?
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
                            replyToDisplayContent: message.replyTo.map { getReplyToDisplayContent($0) },
                            showTime: shouldShowTime(at: index, in: messages),
                            showReadStatus: shouldShowReadStatus(at: index, in: messages),
                            onEdit: onEdit,
                            onDelete: onDelete,
                            onReply: onReply
                        )
                        .id(message.id)
                        .padding(.top, spacing)
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                onReply?(message)
                            } label: {
                                Label("답장", systemImage: "arrowshape.turn.up.left")
                            }
                            .tint(.blue)
                        }
                        .onAppear {
                            onMessageAppear?(message)
                            
                            if index < 3 && !isLoadingMore {
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
                if let newId = newId, newId != oldId, !isInitialLoad {
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
    
    private func scrollToBottomImmediately(proxy: ScrollViewProxy) {
        guard let lastMessage = messages.last else { return }
        proxy.scrollTo(lastMessage.id, anchor: .bottom)
        hasScrolledToBottom = true
        isInitialLoad = false
    }
    
    private func handleMessagesCountChange(oldCount: Int, newCount: Int, proxy: ScrollViewProxy) {
        if isInitialLoad && newCount > 0 && oldCount == 0 {
            scrollToBottomImmediately(proxy: proxy)
            return
        }
        
        if newCount > oldCount && !isInitialLoad {
            let addedCount = newCount - oldCount
            
            if let previousId = previousFirstMessageId, addedCount > 0 {
                proxy.scrollTo(previousId, anchor: .top)
                
                previousFirstMessageId = nil
                previousMessageCount = newCount
            } else if previousFirstMessageId == nil, let lastMessage = messages.last {
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
        
        guard let sender = message.sender, let previousSender = previousMessage.sender,
              sender.id == previousSender.id
        else {
            return 8
        }
        if sender.id == previousSender.id {
            guard let d1 = message.createdAtDate, let d2 = previousMessage.createdAtDate else {
                return 4
            }
            let c1 = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: d1)
            let c2 = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: d2)
            
            if c1 == c2 { return 2 }
        }
        
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
        
        if isLast { return true }
        
        let nextMessage = messages[index + 1]
        
        guard let sender = message.sender, let nextSender = nextMessage.sender else { return true }
        if sender.id != nextSender.id { return true }
        
        guard let d1 = message.createdAtDate, let d2 = nextMessage.createdAtDate else { return true }
        let c1 = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: d1)
        let c2 = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: d2)
        
        return c1 != c2
    }
    
    private func shouldShowReadStatus(at index: Int, in messages: [Message]) -> Bool {
        let message = messages[index]
        
        guard message.isFromCurrentUser else { return false }
        
        let isLast = index == messages.count - 1
        if isLast { return true }
        
        let nextMessage = messages[index + 1]
        
        guard let sender = message.sender, let nextSender = nextMessage.sender else { return true }
        if sender.id != nextSender.id { return true }
        
        guard let d1 = message.createdAtDate, let d2 = nextMessage.createdAtDate else { return true }
        let c1 = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: d1)
        let c2 = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: d2)
        
        return c1 != c2
    }
}

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
