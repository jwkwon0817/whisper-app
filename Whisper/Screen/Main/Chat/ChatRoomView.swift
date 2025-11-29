//
//  ChatRoomView.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import SwiftUI

struct ChatRoomView: View {
    let roomId: String
    @StateObject private var viewModel: ChatRoomViewModel
    @Environment(Router.self) private var router
    @State private var messageText = ""
    @State private var replyToMessage: Message?
    @State private var showImagePicker = false
    @State private var selectedImage: UIImage?
    @State private var showImagePreview = false
    @State private var editingMessage: Message?
    @State private var showDeleteAlert = false
    @State private var messageToDelete: Message?
    
    init(roomId: String) {
        self.roomId = roomId
        _viewModel = StateObject(wrappedValue: ChatRoomViewModel(roomId: roomId))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading && viewModel.messages.isEmpty {
                // 메시지가 전혀 없고 로딩 중일 때만 스켈레톤 표시
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(0..<5) { _ in
                            MessageSkeletonView()
                        }
                    }
                    .padding(.vertical, 8)
                }
            } else {
                MessageListView(
                    messages: viewModel.messages,
                    isLoadingMore: viewModel.isLoadingMore,
                    getDisplayContent: { viewModel.getDisplayContent(for: $0) },
                    getReplyToDisplayContent: { viewModel.getReplyToDisplayContent(for: $0) },
                    onLoadMore: {
                        await viewModel.loadMoreMessages()
                    },
                    onEdit: { message in
                        editingMessage = message
                        messageText = viewModel.getDisplayContent(for: message)
                    },
                    onDelete: { message in
                        messageToDelete = message
                        showDeleteAlert = true
                    },
                    onReply: { message in
                        replyToMessage = message
                    },
                    onMessageAppear: { message in
                        viewModel.onMessageAppear(message)
                    }
                )
            }
            
            TypingIndicatorView(typingUsers: viewModel.typingUsers)
            
            ChatInputView(
                messageText: $messageText,
                replyToMessage: $replyToMessage,
                editingMessage: $editingMessage,
                getDisplayContent: { viewModel.getDisplayContent(for: $0) },
                onSend: handleSend,
                onTyping: { viewModel.sendTypingIndicator(isTyping: $0) },
                onImageSelect: { showImagePicker = true },
                isSending: viewModel.isSending
            )
        }
        .navigationTitle(viewModel.room?.displayName ?? "채팅")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task {
            router.currentActiveChatRoomId = roomId
            NotificationManager.shared.currentActiveChatRoomId = roomId
            await viewModel.loadRoom()
        }
        .onDisappear {
            if router.currentActiveChatRoomId == roomId {
                router.currentActiveChatRoomId = nil
            }
            if NotificationManager.shared.currentActiveChatRoomId == roomId {
                NotificationManager.shared.currentActiveChatRoomId = nil
            }
            viewModel.disconnect()
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selectedImage: $selectedImage)
        }
        .onChange(of: selectedImage) { _, newImage in
            if newImage != nil {
                showImagePreview = true
            }
        }
        .sheet(isPresented: $showImagePreview, onDismiss: {
            selectedImage = nil
        }) {
            if let image = selectedImage {
                ImagePreviewView(image: image) {
                    showImagePreview = false
                    handleImageSelection(image)
                }
            }
        }
        .alert("오류", isPresented: $viewModel.showError) {
            Button("확인", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage ?? "알 수 없는 오류가 발생했습니다.")
        }
        .alert("메시지 삭제", isPresented: $showDeleteAlert) {
            Button("취소", role: .cancel) {
                messageToDelete = nil
            }
            Button("삭제", role: .destructive) {
                if let message = messageToDelete {
                    viewModel.deleteMessage(message)
                }
                messageToDelete = nil
            }
        } message: {
            Text("정말로 이 메시지를 삭제하시겠습니까?")
        }
    }
    
    private func handleSend() {
        if let editingMessage = editingMessage {
            viewModel.editMessage(editingMessage, newContent: messageText)
            self.editingMessage = nil
            messageText = ""
        } else {
            Task {
                await viewModel.sendMessage(
                    content: messageText,
                    replyTo: replyToMessage?.id
                )
                messageText = ""
                replyToMessage = nil
            }
        }
    }
    
    private func handleImageSelection(_ image: UIImage) {
        Task {
            await viewModel.sendImage(image)
            selectedImage = nil
        }
    }
}

