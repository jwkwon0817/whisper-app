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
            if newValue {
                NotificationManager.shared.connect()
            } else {
                NotificationManager.shared.disconnect()
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if oldPhase == .background && newPhase == .active {
                Task {
                    await checkAuth()
                }
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
