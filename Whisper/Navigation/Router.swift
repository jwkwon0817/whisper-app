//
//  Router.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import SwiftUI

@Observable
class Router {
    var paths: [TabRoute: NavigationPath] = [:]
    
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
    
    var currentActiveChatRoomId: String?
    
    var selectedTab: TabRoute = .home {
        didSet {
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
        for _ in 0 ..< count {
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
    case home = "홈"
    case chat = "채팅"
    case profile = "프로필"
    
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
