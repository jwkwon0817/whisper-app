//
//  NavigationRoot.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import SwiftUI

struct NavigationRoot: View {
    @Environment(Router.self) private var router
    
    private var pathBinding: Binding<NavigationPath> {
        Binding(
            get: { router.path },
            set: { router.path = $0 }
        )
    }
    
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

    var body: some View {
        TabView(selection: selectedTabBinding) {
            ForEach(TabRoute.allCases, id: \.self) { tab in
                NavigationStack(path: pathBinding) {
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
