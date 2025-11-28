//
//  FolderTabView.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/24/25.
//

import SwiftUI

// MARK: - Folder Tab View
struct FolderTabView: View {
    let folders: [ChatFolder]
    let selectedFolderId: String?
    let onFolderSelected: (String?) -> Void
    let onCreateFolder: () -> Void
    let onFolderDelete: (ChatFolder) -> Void
    
    @State private var folderToDelete: ChatFolder?
    @State private var showDeleteAlert = false
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // 전체 탭
                FolderTabItem(
                    name: "전체",
                    color: nil,
                    icon: nil,
                    isSelected: selectedFolderId == nil,
                    roomCount: nil,
                    onTap: {
                        onFolderSelected(nil)
                    },
                    onLongPress: {
                        // 전체 탭은 삭제 불가
                    }
                )
                
                // 폴더 탭들
                ForEach(folders) { folder in
                    FolderTabItem(
                        name: folder.name,
                        color: Color(hex: folder.color),
                        icon: folder.icon,
                        isSelected: selectedFolderId == folder.id,
                        roomCount: folder.roomCount,
                        onTap: {
                            onFolderSelected(folder.id)
                        },
                        onLongPress: {
                            folderToDelete = folder
                            showDeleteAlert = true
                        }
                    )
                }
                
                // 새 폴더 추가 버튼
                Button(action: onCreateFolder) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.caption)
                        Text("폴더")
                            .font(.subheadline)
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(20)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .alert("폴더 삭제", isPresented: $showDeleteAlert) {
            Button("취소", role: .cancel) {
                folderToDelete = nil
            }
            Button("삭제", role: .destructive) {
                if let folder = folderToDelete {
                    onFolderDelete(folder)
                }
                folderToDelete = nil
            }
        } message: {
            if let folder = folderToDelete {
                Text("'\(folder.name)' 폴더를 삭제하시겠습니까? 폴더에 속한 채팅방은 삭제되지 않습니다.")
            }
        }
    }
}

// MARK: - Folder Tab Item
struct FolderTabItem: View {
    let name: String
    let color: Color?
    let icon: String?
    let isSelected: Bool
    let roomCount: Int?
    let onTap: () -> Void
    let onLongPress: () -> Void
    
    var body: some View {
        HStack(spacing: 6) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(color ?? .primary)
            } else if let color = color {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            }
            
            Text(name)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
            
            if let count = roomCount, count > 0 {
                Text("(\(count))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .foregroundColor(isSelected ? .blue : .primary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isSelected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
        .cornerRadius(20)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            onLongPress()
        }
    }
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

