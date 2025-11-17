//
//  ProfileScreen.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import SwiftUI

struct ProfileScreen: View {
    @State private var me = UseMe(autoFetch: true)
    @State private var showLogoutAlert = false
    @Environment(Router.self) private var router
    
    var body: some View {
        List {
            Section {
                if me.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if let user = me.data {
                    VStack(spacing: 12) {
                        if let profileImage = user.profileImage {
                            AsyncImage(url: URL(string: profileImage)) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                Circle()
                                    .fill(Color.gray.opacity(0.3))
                            }
                            .frame(width: 80, height: 80)
                            .clipShape(Circle())
                        }
                        
                        Text(user.name)
                            .font(.title2)
                            .bold()
                        
                        Text(user.maskedPhoneNumber ?? "")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)
                } else if let error = me.error {
                    Text(error)
                        .foregroundColor(.red)
                }
            }
            
            Section("기기") {
                Button("내 기기") {
                    router.navigate(to: .deviceList)
                }
            }
            
            Section("설정") {
                Button("설정") {
                    router.navigate(to: .settings)
                }
                
                Button("로그아웃", role: .destructive) {
                    showLogoutAlert = true
                }
            }
        }
        .alert("로그아웃", isPresented: $showLogoutAlert) {
            Button("취소", role: .cancel) { }
            Button("로그아웃", role: .destructive) {
                Task {
                    do {
                        try await NetworkManager.shared.authService.logout()
                        // 로그아웃 성공 시 Notification 전송
                        NotificationCenter.default.post(name: .userDidLogout, object: nil)
                    } catch {
                        print("로그아웃 실패: \(error)")
                    }
                }
            }
        } message: {
            Text("정말 로그아웃 하시겠습니까?")
        }
        .navigationTitle("Profile")
        .refreshable {
            await me.refetch()
        }
    }
}

#Preview {
    NavigationStack {
        ProfileScreen()
            .environment(Router())
    }
}

