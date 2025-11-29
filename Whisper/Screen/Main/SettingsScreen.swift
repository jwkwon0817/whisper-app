//
//  SettingsScreen.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import SwiftUI

struct SettingsScreen: View {
    @Environment(Router.self) private var router
    @State private var showDeleteAccountAlert = false
    @State private var showLogoutAlert = false
    
    var body: some View {
        List {
            Section("계정") {
                Button("로그아웃") {
                    showLogoutAlert = true
                }
                
                Button("회원탈퇴", role: .destructive) {
                    showDeleteAccountAlert = true
                }
            }
        }
        .navigationTitle("설정")
        .alert("로그아웃", isPresented: $showLogoutAlert) {
            Button("취소", role: .cancel) {}
            Button("로그아웃", role: .destructive) {
                Task {
                    do {
                        try await NetworkManager.shared.authService.logout()
                        NotificationCenter.default.post(name: .userDidLogout, object: nil)
                    } catch {
                    }
                }
            }
        } message: {
            Text("정말 로그아웃 하시겠습니까?")
        }
        .sheet(isPresented: $showDeleteAccountAlert) {
            DeleteAccountView()
        }
    }
}

struct DeleteAccountView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var confirmText = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var error: String?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.red)
                    
                    Text("정말로 탈퇴하시겠습니까?")
                        .font(.title2)
                        .bold()
                    
                    Text("모든 데이터가 영구적으로 삭제되며\n복구할 수 없습니다.")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 32)
                
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("확인을 위해 \"회원탈퇴\"를 입력해주세요")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        TextField("회원탈퇴", text: $confirmText)
                            .padding(.vertical, 16)
                            .padding(.horizontal, 20)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("비밀번호를 입력해주세요")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        SecureField("비밀번호", text: $password)
                            .padding(.vertical, 16)
                            .padding(.horizontal, 20)
                    }
                }
                .padding(.horizontal)
                
                if let error {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
                
                Spacer()
                
                Button {
                    Task {
                        await deleteAccount()
                    }
                } label: {
                    if isLoading {
                        ProgressView()
                    } else {
                        Text("탈퇴하기")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(isDeleteEnabled ? Color.red : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(12)
                .padding(.horizontal)
                .disabled(!isDeleteEnabled || isLoading)
            }
            .navigationTitle("회원탈퇴")
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                PlatformToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        dismiss()
                    }
                }
            }
            .hideKeyboardOnTap()
        }
    }
    
    private var isDeleteEnabled: Bool {
        confirmText == "회원탈퇴" && !password.isEmpty
    }
    
    private func deleteAccount() async {
        isLoading = true
        error = nil
        
        do {
            try await NetworkManager.shared.userService.deleteAccount(
                confirmText: confirmText,
                password: password
            )
            
            dismiss()
            
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
}

#Preview {
    NavigationStack {
        SettingsScreen()
    }
}

#Preview("Delete Account") {
    DeleteAccountView()
}
