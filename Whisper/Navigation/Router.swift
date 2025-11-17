//
//  Router.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import SwiftUI

@Observable
class Router {
    // 각 탭마다 독립적인 네비게이션 스택
    private var paths: [TabRoute: NavigationPath] = [:]
    
    var path: NavigationPath {
        get {
            paths[selectedTab] ?? NavigationPath()
        }
        set {
            paths[selectedTab] = newValue
        }
    }
    
    var presentedSheet: Route?
    var presentedFullScreen: Route?
    
    var selectedTab: TabRoute = .home {
        didSet {
            // 탭 전환 시 이전 탭의 스택을 저장하고 새 탭의 스택을 로드
            // paths는 이미 각 탭별로 관리되므로 자동으로 처리됨
        }
    }
    
    func navigate(to route: Route) {
        var currentPath = paths[selectedTab] ?? NavigationPath()
        currentPath.append(route)
        paths[selectedTab] = currentPath
    }
    
    func goBack() {
        var currentPath = paths[selectedTab] ?? NavigationPath()
        if !currentPath.isEmpty {
            currentPath.removeLast()
            paths[selectedTab] = currentPath
        }
    }
    
    func pop(count: Int = 1) {
        var currentPath = paths[selectedTab] ?? NavigationPath()
        for _ in 0..<count {
            if !currentPath.isEmpty {
                currentPath.removeLast()
            }
        }
        paths[selectedTab] = currentPath
    }
    
    func popToRoot() {
        paths[selectedTab] = NavigationPath()
    }
    
    func replace(with route: Route) {
        var currentPath = paths[selectedTab] ?? NavigationPath()
        if !currentPath.isEmpty {
            currentPath.removeLast()
        }
        currentPath.append(route)
        paths[selectedTab] = currentPath
    }
    
    func present(sheet route: Route) {
        presentedSheet = route
    }
    
    func present(fullScreen route: Route) {
        presentedFullScreen = route
    }
    
    func dismiss() {
        presentedSheet = nil
        presentedFullScreen = nil
    }
    
    
    func switchTab(to tab: TabRoute) {
        selectedTab = tab
    }
}

enum TabRoute: String, CaseIterable, Identifiable {
    case home = "Home"
    case chat = "Chat"
    case profile = "Profile"
    
    var id: String { rawValue }
    
    var title: String { rawValue }
    
    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .chat: return "message.fill"
        case .profile: return "person.fill"
        }
    }
}

