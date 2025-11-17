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
            // 로그인 성공 시 알림 WebSocket 연결
            if isLoggedIn {
                NotificationManager.shared.connect()
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            // 앱이 포그라운드로 돌아올 때 인증 상태 확인
            if oldPhase == .background && newPhase == .active {
                Task {
                    await checkAuth()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .userDidLogout)) { _ in
            // 로그아웃 시 NavigationStack 초기화
            router.path = NavigationPath()
            isLoggedIn = false
        }
    }
    
    private func checkAuth() async {
        // 토큰이 있으면 자동으로 로그인 상태 유지
        if let accessToken = KeychainHelper.getItem(forAccount: "accessToken"),
           !accessToken.isEmpty {
            do {
                // 토큰 유효성 검증 (BaseService가 자동으로 refresh 처리)
                _ = try await NetworkManager.shared.userService.fetchMe()
                isLoggedIn = true
            } catch {
                // 토큰이 유효하지 않으면 삭제하고 로그인 화면으로
                KeychainHelper.removeItem(forAccount: "accessToken")
                KeychainHelper.removeItem(forAccount: "refreshToken")
                E2EEKeyManager.shared.deleteEncryptedPrivateKey()
                isLoggedIn = false
            }
        } else {
            // 토큰이 없으면 로그인 화면으로
            isLoggedIn = false
        }
        
        isCheckingAuth = false
    }
}

#Preview {
    ContentView()
}
