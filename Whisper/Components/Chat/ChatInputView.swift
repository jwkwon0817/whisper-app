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
    let onSend: () -> Void
    let onTyping: (Bool) -> Void
    let onImageSelect: () -> Void
    var isSending: Bool = false // 메시지 전송 중 여부
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // 답장 표시
            if let replyTo = replyToMessage {
                ReplyToHeaderView(replyTo: replyTo) {
                    replyToMessage = nil
                }
            }
            
            // 편집 모드 표시
            if let editing = editingMessage {
                EditingHeaderView(message: editing) {
                    editingMessage = nil
                    messageText = ""
                }
            }
            
            // 입력 필드
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
            
            // 전송 버튼
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
    let onDismiss: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(replyTo.sender.name)에게 답장")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(replyTo.displayContent)
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

// MARK: - Editing Header Component

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
