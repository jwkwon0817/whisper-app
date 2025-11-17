//
//  ChatRoomView.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import SwiftUI

// MARK: - Chat Room View
struct ChatRoomView: View {
    let roomId: String
    @StateObject private var viewModel: ChatRoomViewModel
    @State private var messageText = ""
    @State private var replyToMessage: Message?
    @State private var showImagePicker = false
    @State private var selectedImage: UIImage?
    @FocusState private var isInputFocused: Bool
    
    init(roomId: String) {
        self.roomId = roomId
        _viewModel = StateObject(wrappedValue: ChatRoomViewModel(roomId: roomId))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            messageListView
            typingIndicatorView
            inputView
        }
        .navigationTitle(viewModel.room?.displayName ?? "채팅")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadRoom()
        }
        .alert("오류", isPresented: $viewModel.showError) {
            Button("확인", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage ?? "알 수 없는 오류가 발생했습니다.")
        }
    }
    
    private var messageListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if viewModel.isLoadingMore {
                        ProgressView()
                            .padding()
                    }
                    
                    ForEach(viewModel.messages) { message in
                        MessageBubbleView(
                            message: message,
                            displayContent: viewModel.getDisplayContent(for: message)
                        )
                        .id(message.id)
                        .onAppear {
                            if message.id == viewModel.messages.first?.id {
                                Task {
                                    await viewModel.loadMoreMessages()
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .onChange(of: viewModel.messages.count) { _ in
                if let lastMessage = viewModel.messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    private var typingIndicatorView: some View {
        Group {
            if !viewModel.typingUsers.isEmpty {
                HStack {
                    Text(typingUsersText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
    }
    
    private var typingUsersText: String {
        viewModel.typingUsers.map { $0.name }.joined(separator: ", ") + "님이 입력 중..."
    }
    
    private var inputView: some View {
        ChatInputView(
            messageText: $messageText,
            replyToMessage: $replyToMessage,
            onSend: handleSend,
            onTyping: { isTyping in
                viewModel.sendTypingIndicator(isTyping: isTyping)
            },
            onImageSelect: {
                showImagePicker = true
            }
        )
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selectedImage: $selectedImage)
        }
        .onChange(of: selectedImage) { _, newImage in
            handleImageSelection(newImage)
        }
    }
    
    private func handleSend() {
        Task {
            await viewModel.sendMessage(
                content: messageText,
                replyTo: replyToMessage?.id
            )
            messageText = ""
            replyToMessage = nil
        }
    }
    
    private func handleImageSelection(_ image: UIImage?) {
        guard let image = image else { return }
        Task {
            await viewModel.sendImage(image)
            selectedImage = nil
        }
    }
}

// MARK: - Message Bubble View
struct MessageBubbleView: View {
    let message: Message
    let displayContent: String
    
    var body: some View {
        HStack {
            if message.isFromCurrentUser {
                Spacer()
            }
            
            VStack(alignment: message.isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                // 답장 대상 표시
                if let replyTo = message.replyTo {
                    ReplyToView(replyTo: replyTo)
                        .padding(.bottom, 4)
                }
                
                // 메시지 내용
                Text(displayContent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(message.isFromCurrentUser ? Color.blue : Color.gray.opacity(0.2))
                    .foregroundColor(message.isFromCurrentUser ? .white : .primary)
                    .cornerRadius(16)
                
                // 시간 및 읽음 상태
                HStack(spacing: 4) {
                    if let date = message.createdAtDate {
                        Text(date, style: .time)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    if message.isFromCurrentUser {
                        Image(systemName: message.isRead ? "checkmark" : "checkmark")
                            .font(.caption2)
                            .foregroundColor(message.isRead ? .blue : .secondary)
                    }
                }
            }
            
            if !message.isFromCurrentUser {
                Spacer()
            }
        }
    }
}

// MARK: - Reply To View
struct ReplyToView: View {
    let replyTo: ReplyToMessage
    
    var body: some View {
        HStack {
            Rectangle()
                .fill(Color.blue)
                .frame(width: 3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(replyTo.sender.name)
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(replyTo.content)
                    .font(.caption)
                    .lineLimit(1)
            }
            
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Chat Input View
struct ChatInputView: View {
    @Binding var messageText: String
    @Binding var replyToMessage: Message?
    let onSend: () -> Void
    let onTyping: (Bool) -> Void
    let onImageSelect: () -> Void
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // 답장 표시
            if let replyTo = replyToMessage {
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(replyTo.sender.name)에게 답장")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text(replyTo.displayContent)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        replyToMessage = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.1))
            }
            
            // 입력 필드
            HStack(spacing: 12) {
                Button(action: onImageSelect) {
                    Image(systemName: "photo")
                        .font(.system(size: 20))
                        .foregroundColor(.blue)
                }
                
                TextField("메시지 입력", text: $messageText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .focused($isFocused)
                    .onChange(of: messageText) { _ in
                        onTyping(true)
                    }
                
                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(messageText.isEmpty ? .gray : .blue)
                }
                .disabled(messageText.isEmpty)
            }
            .padding()
        }
        .background(Color(.systemBackground))
    }
}

