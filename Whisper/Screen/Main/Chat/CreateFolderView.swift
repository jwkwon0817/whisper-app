//
//  CreateFolderView.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/24/25.
//

import SwiftUI

// MARK: - Create Folder View

struct CreateFolderView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ChatFolderViewModel()
    
    let onFolderCreated: ((ChatFolder?) -> Void)?
    
    @State private var folderName = ""
    @State private var selectedColor = "#000000"
    @State private var selectedIcon = "folder.fill"
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    init(onFolderCreated: ((ChatFolder?) -> Void)? = nil) {
        self.onFolderCreated = onFolderCreated
    }
    
    let presetColors: [String] = [
        "#000000", "#FF3B30", "#FF9500", "#FFCC00",
        "#34C759", "#5AC8FA", "#007AFF", "#5856D6",
        "#AF52DE", "#FF2D55", "#8E8E93"
    ]
    
    let presetIcons: [String] = [
        "folder.fill", "heart.fill", "star.fill", "bookmark.fill",
        "tag.fill", "flag.fill", "bell.fill", "envelope.fill",
        "paperclip", "tray.fill", "archivebox.fill", "briefcase.fill",
        "house.fill", "car.fill", "gamecontroller.fill", "music.note",
        "camera.fill", "paintbrush.fill", "pencil.circle.fill", "sparkles"
    ]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("폴더 이름") {
                    TextField("폴더 이름을 입력하세요", text: $folderName)
                        .padding(.vertical, 16)
                        .padding(.horizontal, 20)
                }
                
                Section("폴더 색상") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 16) {
                        ForEach(Array(presetColors.enumerated()), id: \.element) { _, colorHex in
                            ColorCircleView(
                                color: Color(hex: colorHex),
                                isSelected: selectedColor == colorHex
                            ) {
                                selectedColor = colorHex
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Section("폴더 아이콘") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 16) {
                        ForEach(Array(presetIcons.enumerated()), id: \.element) { _, iconName in
                            IconCircleView(
                                iconName: iconName,
                                isSelected: selectedIcon == iconName
                            ) {
                                selectedIcon = iconName
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("새 폴더")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") {
                        Task {
                            await createFolder()
                        }
                    }
                    .disabled(folderName.isEmpty || isLoading)
                }
            }
            .alert("오류", isPresented: .constant(errorMessage != nil)) {
                Button("확인", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
        }
    }
    
    private func createFolder() async {
        guard !folderName.isEmpty else { return }
        
        isLoading = true
        errorMessage = nil
        
        await viewModel.createFolder(name: folderName, color: selectedColor, icon: selectedIcon)
        
        if viewModel.showError {
            errorMessage = viewModel.errorMessage
        } else {
            onFolderCreated?(nil)
            dismiss()
        }
        
        isLoading = false
    }
}

struct ColorCircleView: View {
    let color: Color
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 40, height: 40)
                
                if isSelected {
                    Circle()
                        .stroke(Color.blue, lineWidth: 3)
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct IconCircleView: View {
    let iconName: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 40, height: 40)
                
                Image(systemName: iconName)
                    .font(.system(size: 20))
                    .foregroundColor(.primary)
                
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.blue, lineWidth: 3)
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .background(Color.white)
                        .clipShape(Circle())
                        .offset(x: 14, y: -14)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}
