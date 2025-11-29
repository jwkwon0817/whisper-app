//
//  MessageBubbleView.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import SwiftUI

// MARK: - Message Bubble Component

struct MessageBubbleView: View, Equatable {
    let message: Message
    let displayContent: String
    let replyToDisplayContent: String?
    let showTime: Bool
    let showReadStatus: Bool
    let onEdit: ((Message) -> Void)?
    let onDelete: ((Message) -> Void)?
    let onReply: ((Message) -> Void)?
    
    init(
        message: Message,
        displayContent: String,
        replyToDisplayContent: String? = nil,
        showTime: Bool = true,
        showReadStatus: Bool = true,
        onEdit: ((Message) -> Void)? = nil,
        onDelete: ((Message) -> Void)? = nil,
        onReply: ((Message) -> Void)? = nil
    ) {
        self.message = message
        self.displayContent = displayContent
        self.replyToDisplayContent = replyToDisplayContent
        self.showTime = showTime
        self.showReadStatus = showReadStatus
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.onReply = onReply
    }
    
    // MARK: - Equatable

    static func == (lhs: MessageBubbleView, rhs: MessageBubbleView) -> Bool {
        lhs.message == rhs.message &&
            lhs.displayContent == rhs.displayContent &&
            lhs.replyToDisplayContent == rhs.replyToDisplayContent &&
            lhs.showTime == rhs.showTime &&
            lhs.showReadStatus == rhs.showReadStatus
    }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isFromCurrentUser {
                Spacer()
            }
            
            VStack(alignment: message.isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                if let replyTo = message.replyTo {
                    ReplyToPreviewView(
                        replyTo: replyTo,
                        displayContent: replyToDisplayContent ?? replyTo.displayContent // 수정
                    )
                    .padding(.bottom, 4)
                }
                
                messageContentView
                
                messageMetadataView
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: message.isFromCurrentUser ? .trailing : .leading)
            
            if !message.isFromCurrentUser {
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
    
    private var messageContentView: some View {
        Group {
            if let asset = message.asset {
                AssetMessageView(asset: asset, messageType: message.messageType)
            } else {
                Text(displayContent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(message.isFromCurrentUser ? Color.blue : Color.gray.opacity(0.2))
                    .foregroundColor(message.isFromCurrentUser ? .white : .primary)
                    .cornerRadius(16)
                    .contextMenu {
                        Button {
                            onReply?(message)
                        } label: {
                            Label("답장", systemImage: "arrowshape.turn.up.left")
                        }
                        
                        if message.isFromCurrentUser {
                            if message.messageType == .text {
                                Button {
                                    onEdit?(message)
                                } label: {
                                    Label("수정", systemImage: "pencil")
                                }
                            }
                            
                            Button(role: .destructive) {
                                onDelete?(message)
                            } label: {
                                Label("삭제", systemImage: "trash")
                            }
                        }
                    }
            }
        }
    }
    
    private var messageMetadataView: some View {
        HStack(spacing: 4) {
            if showTime, let date = message.createdAtDate {
                Text(date, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if message.isFromCurrentUser && showReadStatus {
                Image(systemName: message.isRead ? "checkmark" : "checkmark")
                    .font(.caption2)
                    .foregroundColor(message.isRead ? .blue : .secondary)
            }
        }
    }
}

struct ReplyToPreviewView: View {
    let replyTo: ReplyToMessage
    let displayContent: String
    
    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.blue)
                .frame(width: 3)
            
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
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
        )
    }
}

struct AssetMessageView: View, Equatable {
    let asset: Asset
    let messageType: Message.MessageType
    
    static func == (lhs: AssetMessageView, rhs: AssetMessageView) -> Bool {
        lhs.asset == rhs.asset && lhs.messageType == rhs.messageType
    }
    
    var body: some View {
        Group {
            switch messageType {
            case .image:
                AsyncImage(url: URL(string: asset.url)) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(height: 150)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    case .failure:
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                            .frame(height: 150)
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(maxHeight: 200)
                .cornerRadius(12)
                
            case .file:
                FileMessageView(fileName: asset.fileName ?? "파일", fileSize: asset.fileSize)
                
            default:
                EmptyView()
            }
        }
    }
}

struct FileMessageView: View {
    let fileName: String
    let fileSize: Int?
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.fill")
                .font(.title2)
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(fileName)
                    .font(.subheadline)
                    .lineLimit(1)
                
                if let size = fileSize {
                    Text(formatFileSize(size))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(12)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
    
    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
