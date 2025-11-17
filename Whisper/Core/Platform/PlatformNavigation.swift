//
//  PlatformNavigation.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import SwiftUI

/// 플랫폼 독립적인 Navigation Title Display Mode
enum PlatformNavigationTitleDisplayMode {
    case automatic
    case inline
    case large
    
    #if os(iOS)
    var uiDisplayMode: NavigationBarItem.TitleDisplayMode {
        switch self {
        case .automatic:
            return .automatic
        case .inline:
            return .inline
        case .large:
            return .large
        }
    }
    #endif
}

/// 플랫폼 독립적인 ToolbarItem Placement
enum PlatformToolbarItemPlacement {
    case automatic
    case principal
    case primaryAction
    case cancellationAction
    case navigationBarTrailing
    case navigationBarLeading
    case bottomBar
    case status
    case secondaryAction
    
    var toolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
        switch self {
        case .automatic:
            return .automatic
        case .principal:
            return .principal
        case .primaryAction:
            return .primaryAction
        case .cancellationAction:
            return .cancellationAction
        case .navigationBarTrailing:
            return .navigationBarTrailing
        case .navigationBarLeading:
            return .navigationBarLeading
        case .bottomBar:
            return .bottomBar
        case .status:
            return .status
        case .secondaryAction:
            return .secondaryAction
        }
        #elseif os(macOS)
        // macOS에서는 navigationBarTrailing/Leading이 없으므로 자동으로 적절한 위치에 배치
        switch self {
        case .automatic:
            return .automatic
        case .principal:
            return .principal
        case .primaryAction:
            return .primaryAction
        case .cancellationAction:
            return .cancellationAction
        case .navigationBarTrailing, .navigationBarLeading:
            // macOS에서는 자동으로 적절한 위치에 배치
            return .automatic
        case .bottomBar:
            return .automatic
        case .status:
            return .status
        case .secondaryAction:
            return .secondaryAction
        }
        #else
        return .automatic
        #endif
    }
}

extension View {
    /// 플랫폼 독립적인 Navigation Title Display Mode 설정
    func platformNavigationBarTitleDisplayMode(_ mode: PlatformNavigationTitleDisplayMode) -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(mode.uiDisplayMode)
        #else
        // macOS에서는 navigationBarTitleDisplayMode가 없으므로 무시
        self
        #endif
    }
}

/// 플랫폼 독립적인 ToolbarItem
struct PlatformToolbarItem<Content: View>: ToolbarContent {
    let placement: PlatformToolbarItemPlacement
    @ViewBuilder let content: () -> Content
    
    var body: some ToolbarContent {
        ToolbarItem(placement: placement.toolbarPlacement) {
            content()
        }
    }
}

