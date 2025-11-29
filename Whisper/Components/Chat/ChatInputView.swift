//
//  ChatInputView.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import SwiftUI

// MARK: - Chat Input Component

struct ChatInputView: View {
    @Binding var messageText: String
    @Binding var replyToMessage: Message?
    @Binding var editingMessage: Message?
    let getDisplayContent: ((Message) -> String)?
    let onSend: () -> Void
    let onTyping: (Bool) -> Void
    let onImageSelect: () -> Void
    var isSending: Bool = false
    
    @FocusState private var isFocused: Bool
    
    init(
        messageText: Binding<String>,
        replyToMessage: Binding<Message?>,
        editingMessage: Binding<Message?>,
        getDisplayContent: ((Message) -> String)? = nil,
        onSend: @escaping () -> Void,
        onTyping: @escaping (Bool) -> Void,
        onImageSelect: @escaping () -> Void,
        isSending: Bool = false
    ) {
        self._messageText = messageText
        self._replyToMessage = replyToMessage
        self._editingMessage = editingMessage
        self.getDisplayContent = getDisplayContent
        self.onSend = onSend
        self.onTyping = onTyping
        self.onImageSelect = onImageSelect
        self.isSending = isSending
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if let replyTo = replyToMessage {
                ReplyToHeaderView(
                    replyTo: replyTo,
                    displayContent: getDisplayContent?(replyTo) ?? replyTo.displayContent
                ) {
                    replyToMessage = nil
                }
            }
            
            if let editing = editingMessage {
                EditingHeaderView(message: editing) {
                    editingMessage = nil
                    messageText = ""
                }
            }
            
            inputFieldView
        }
        .background(Color(.systemBackground))
    }
    
    private var inputFieldView: some View {
        HStack(spacing: 12) {
            Button(action: onImageSelect) {
                Image(systemName: "photo")
                    .font(.system(size: 20))
                    .foregroundColor(.blue)
            }
            
            TextField("메시지 입력", text: $messageText, axis: .vertical)
                .padding(.vertical, 16)
                .padding(.horizontal, 8)
                .lineLimit(1 ... 5)
                .focused($isFocused)
                .onChange(of: messageText) { _, _ in
                    onTyping(true)
                }
            
            Button(action: onSend) {
                if isSending {
                    ProgressView()
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: editingMessage != nil ? "checkmark.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(messageText.isEmpty ? .gray : .blue)
                }
            }
            .disabled(messageText.isEmpty || isSending)
        }
        .padding()
    }
}

// MARK: - Reply To Header Component

struct ReplyToHeaderView: View {
    let replyTo: Message
    let displayContent: String
    let onDismiss: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.blue)
                .frame(width: 2)
                .cornerRadius(1)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .font(.caption2)
                        .foregroundColor(.blue)
                    Text(replyTo.sender?.name ?? "알 수 없음")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
                
                Text(displayContent)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(height: 50)
        .background(Color.blue.opacity(0.05))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color.gray.opacity(0.2)),
            alignment: .top
        )
    }
}

struct EditingHeaderView: View {
    let message: Message
    let onDismiss: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "pencil")
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("메시지 수정 중")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
                Text(message.displayContent)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.1))
    }
}
