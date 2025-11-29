//
//  FolderSelectionView.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/24/25.
//

import SwiftUI

// MARK: - Folder Selection View (롱 프레스 메뉴용)
struct FolderSelectionView: View {
    let folders: [ChatFolder]
    let currentFolderId: String?
    let onFolderSelected: (String?) -> Void
    let onCreateFolder: () -> Void
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button(action: {
                    onFolderSelected(nil)
                }) {
                    HStack {
                        Image(systemName: currentFolderId == nil ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(currentFolderId == nil ? .blue : .secondary)
                        Text("폴더 없음")
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                
                Divider()
                
                // 폴더 목록
                if folders.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "folder")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                            .padding(.top, 40)
                        Text("폴더가 없습니다")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ForEach(folders) { folder in
                        Button(action: {
                            onFolderSelected(folder.id)
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: folder.icon)
                                    .font(.body)
                                    .foregroundColor(Color(hex: folder.color))
                                    .frame(width: 24, height: 24)
                                
                                Text(folder.name)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                if currentFolderId == folder.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                        .fontWeight(.semibold)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                    }
                }
                
                Divider()
                
                // 새 폴더 생성
                Button(action: onCreateFolder) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                        Text("새 폴더 만들기")
                            .foregroundColor(.blue)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
        .background(Color(.systemBackground))
    }
}

