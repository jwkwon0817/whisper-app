//
//  PlatformNavigation.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import SwiftUI

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
    func platformNavigationBarTitleDisplayMode(_ mode: PlatformNavigationTitleDisplayMode) -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(mode.uiDisplayMode)
        #else
        self
        #endif
    }
}

struct PlatformToolbarItem<Content: View>: ToolbarContent {
    let placement: PlatformToolbarItemPlacement
    @ViewBuilder let content: () -> Content
    
    var body: some ToolbarContent {
        ToolbarItem(placement: placement.toolbarPlacement) {
            content()
        }
    }
}

