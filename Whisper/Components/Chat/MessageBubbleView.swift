//
//  MessageBubbleView.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import SwiftUI

// MARK: - Message Bubble Component
/// 메시지 버블 뷰
/// Equatable 프로토콜을 준수하여 메시지 내용이 변경되지 않았다면 뷰를 다시 그리지 않음
struct MessageBubbleView: View, Equatable {
    let message: Message
    let displayContent: String
    let showTime: Bool
    let showReadStatus: Bool
    let onEdit: ((Message) -> Void)?
    let onDelete: ((Message) -> Void)?
    
    init(message: Message, displayContent: String, showTime: Bool = true, showReadStatus: Bool = true, onEdit: ((Message) -> Void)? = nil, onDelete: ((Message) -> Void)? = nil) {
        self.message = message
        self.displayContent = displayContent
        self.showTime = showTime
        self.showReadStatus = showReadStatus
        self.onEdit = onEdit
        self.onDelete = onDelete
    }
    
    // MARK: - Equatable
    // 불필요한 뷰 리렌더링 방지를 위한 Equatable 구현
    static func == (lhs: MessageBubbleView, rhs: MessageBubbleView) -> Bool {
        lhs.message == rhs.message &&
        lhs.displayContent == rhs.displayContent &&
        lhs.showTime == rhs.showTime &&
        lhs.showReadStatus == rhs.showReadStatus
    }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isFromCurrentUser {
                Spacer()
            }
            
            VStack(alignment: message.isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                // 답장 대상 표시
                if let replyTo = message.replyTo {
                    ReplyToPreviewView(replyTo: replyTo)
                        .padding(.bottom, 4)
                }
                
                // 메시지 내용
                messageContentView
                
                // 시간 및 읽음 상태
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
    
    // MARK: - Message Content View
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
    
    // MARK: - Message Metadata View
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

// MARK: - Reply To Preview Component
struct ReplyToPreviewView: View {
    let replyTo: ReplyToMessage
    
    var body: some View {
        HStack(spacing: 8) {
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

// MARK: - Asset Message Component
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
                // MARK: - 이미지 캐싱 개선 제안
                // AsyncImage는 기본적으로 URLCache를 사용하지만, 캐싱 정책을 세밀하게 제어하기 어려움
                // 개선 방안:
                // 1. Kingfisher 또는 SDWebImageSwiftUI 라이브러리 사용 권장
                //    - 디스크 캐시 크기/만료 정책 제어 가능
                //    - 메모리 캐시 관리 용이
                //    - 이미지 다운샘플링 지원 (메모리 절약)
                // 2. 커스텀 이미지 캐싱 매니저 구현
                //    - NSCache를 사용한 메모리 캐시
                //    - FileManager를 사용한 디스크 캐시
                // 예시 (Kingfisher 사용 시):
                // KFImage(URL(string: asset.url))
                //     .placeholder { ProgressView() }
                //     .fade(duration: 0.25)
                //     .cacheOriginalImage()
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

// MARK: - File Message Component
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

