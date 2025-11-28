//
//  NavigationRoot.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import SwiftUI

struct NavigationRoot: View {
    @Environment(Router.self) private var router
    
    @State private var currentNotification: AppNotification?
    @State private var showBanner = false
    @State private var bannerWorkItem: DispatchWorkItem?
    
    private var selectedTabBinding: Binding<TabRoute> {
        Binding(
            get: { router.selectedTab },
            set: { router.selectedTab = $0 }
        )
    }
    
    private var presentedSheetBinding: Binding<Route?> {
        Binding(
            get: { router.presentedSheet },
            set: { router.presentedSheet = $0 }
        )
    }
    
    private var presentedFullScreenBinding: Binding<Route?> {
        Binding(
            get: { router.presentedFullScreen },
            set: { router.presentedFullScreen = $0 }
        )
    }
    
    // 각 탭마다 독립적인 NavigationPath binding 생성
    private func pathBinding(for tab: TabRoute) -> Binding<NavigationPath> {
        Binding(
            get: {
                // Router의 paths 딕셔너리에서 직접 가져오기
                router.paths[tab] ?? NavigationPath()
            },
            set: { newValue in
                router.paths[tab] = newValue
            }
        )
    }

    var body: some View {
        TabView(selection: selectedTabBinding) {
            ForEach(TabRoute.allCases, id: \.self) { tab in
                NavigationStack(path: pathBinding(for: tab)) {
                    tab.rootView
                        .navigationDestination(for: Route.self) { route in
                            route.destination
                        }
                }
                .tabItem {
                    Label(tab.title, systemImage: tab.icon)
                }
                .tag(tab)
            }
        }
        .tint(.primary)
        .onAppear {
            #if os(iOS)
            let appearance = UITabBarAppearance()
            appearance.configureWithTransparentBackground()
            let blur = PlatformBlur(style: .ultraThinMaterial)
            appearance.backgroundEffect = blur.uiBlurEffect
            
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
            #endif
        }
        .sheet(item: presentedSheetBinding) { route in
            NavigationStack {
                route.destination
                    .toolbar {
                        PlatformToolbarItem(placement: .cancellationAction) {
                            Button("닫기") {
                                router.dismiss()
                            }
                        }
                    }
            }
        }
        .platformFullScreenCover(item: presentedFullScreenBinding) { route in
            NavigationStack {
                route.destination
            }
        }
        .overlay(alignment: .top) {
            if showBanner, let notification = currentNotification,
               let senderName = notification.data.sender?.name {
                NotificationBanner(
                    title: senderName,
                    message: getMessageContent(for: notification),
                    onDismiss: {
                        withAnimation {
                            showBanner = false
                        }
                    },
                    onTap: {
                        handleNotificationTap(notification)
                        withAnimation {
                            showBanner = false
                        }
                    }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(100)
                .ignoresSafeArea(edges: .top) // Safe area 무시하고 맨 위에 배치
            }
        }
        .onReceive(NotificationManager.shared.newMessageReceived) { notification in
            handleNewMessage(notification)
        }
    }
    
    private func handleNewMessage(_ notification: AppNotification) {
        // 현재 보고 있는 채팅방의 메시지면 알림 표시 안함
        if let notificationRoomId = notification.data.roomId,
           let currentRoomId = router.currentActiveChatRoomId,
           notificationRoomId == currentRoomId {
            #if DEBUG
            print("🔕 [NavigationRoot] 현재 채팅방의 메시지이므로 알림 표시 안함 - Room ID: \(notificationRoomId)")
            #endif
            return
        }
        
        self.currentNotification = notification
        withAnimation {
            self.showBanner = true
        }
        
        // 햅틱 피드백
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        // 3초 후 자동 숨김
        bannerWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            withAnimation {
                self.showBanner = false
            }
        }
        bannerWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: workItem)
    }
    
    private func getMessageContent(for notification: AppNotification) -> String {
        let messageType = notification.data.messageType ?? "text"
        
        if let content = notification.data.content {
            return content
        } else {
            // 백엔드에서 content를 제공하지 않은 경우
            switch messageType {
            case "image":
                return "📷 사진"
            case "file":
                return "📎 파일"
            default:
                return "새로운 메시지"
            }
        }
    }
    
    private func handleNotificationTap(_ notification: AppNotification) {
        guard let roomId = notification.data.roomId else { return }
        
        // 채팅 탭으로 이동
        router.selectedTab = .chat
        
        // 해당 채팅방으로 네비게이션
        // NavigationPath에 roomId(String) 추가
        var path = router.paths[.chat] ?? NavigationPath()
        path.append(roomId)
        router.paths[.chat] = path
    }
}

extension TabRoute {
    @ViewBuilder
    var rootView: some View {
        switch self {
        case .home:
            HomeScreen()
        case .chat:
            ChatRoomListView()
        case .profile:
            ProfileScreen()
        }
    }
}

extension Route: Identifiable {
    var id: Self { self }
}
