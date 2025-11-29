//
//  ContentView.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/9/25.
//

import SwiftUI

struct ContentView: View {
    @State private var router = Router()
    @State private var isLoggedIn = false
    @State private var isCheckingAuth = true
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        Group {
            if isCheckingAuth {
                ProgressView("로딩 중...")
            } else if isLoggedIn {
                NavigationRoot()
            } else {
                NavigationStack(path: $router.path) {
                    LoginScreen(onLoginSuccess: {
                        // 로그인 성공 시 WebSocket 연결
                        NotificationManager.shared.connect()
                        isLoggedIn = true
                    })
                    .navigationDestination(for: Route.self) { route in
                        route.destination
                    }
                }
            }
        }
        .environment(router)
        .task {
            await checkAuth()
        }
        .onChange(of: isLoggedIn) { oldValue, newValue in
            // 로그인 상태 변경 시 WebSocket 연결/해제
            if newValue {
                NotificationManager.shared.connect()
                #if DEBUG
                print("✅ [ContentView] 로그인 상태 변경 - WebSocket 연결")
                #endif
            } else {
                NotificationManager.shared.disconnect()
                #if DEBUG
                print("🔌 [ContentView] 로그아웃 - WebSocket 연결 해제")
                #endif
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if oldPhase == .background && newPhase == .active {
                Task {
                    await checkAuth()
                }
                // 앱이 포그라운드로 돌아올 때 WebSocket 재연결
                if isLoggedIn {
                    NotificationManager.shared.connect()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .userDidLogout)) { _ in
            router.path = NavigationPath()
            isLoggedIn = false
        }
    }
    
    private func checkAuth() async {
        if let accessToken = KeychainHelper.getItem(forAccount: "accessToken"),
           !accessToken.isEmpty {
            do {
                let user = try await NetworkManager.shared.userService.fetchMe()
                CurrentUser.shared.update(user: user)
                isLoggedIn = true
            } catch {
                KeychainHelper.removeItem(forAccount: "accessToken")
                KeychainHelper.removeItem(forAccount: "refreshToken")
                KeychainHelper.removeItem(forAccount: "user_password")
                E2EEKeyManager.shared.deleteEncryptedPrivateKey()
                CurrentUser.shared.clear()
                isLoggedIn = false
            }
        } else {
            isLoggedIn = false
            CurrentUser.shared.clear()
        }
        
        isCheckingAuth = false
    }
}

#Preview {
    ContentView()
}
