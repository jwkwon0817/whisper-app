//
//  PlatformBlur.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum PlatformBlurStyle {
    case ultraThinMaterial
    case thinMaterial
    case regularMaterial
    case thickMaterial
    
    #if os(iOS)
    var uiBlurStyle: UIBlurEffect.Style {
        switch self {
        case .ultraThinMaterial:
            return .systemUltraThinMaterial
        case .thinMaterial:
            return .systemThinMaterial
        case .regularMaterial:
            return .systemMaterial
        case .thickMaterial:
            return .systemThickMaterial
        }
    }
    #elseif os(macOS)
    var nsVisualEffectMaterial: NSVisualEffectView.Material {
        switch self {
        case .ultraThinMaterial, .thinMaterial:
            return .hudWindow
        case .regularMaterial:
            return .windowBackground
        case .thickMaterial:
            return .sidebar
        }
    }
    #endif
}

struct PlatformBlur {
    let style: PlatformBlurStyle
    
    init(style: PlatformBlurStyle) {
        self.style = style
    }
    
    #if os(iOS)
    var uiBlurEffect: UIBlurEffect {
        UIBlurEffect(style: style.uiBlurStyle)
    }
    #elseif os(macOS)
    var nsVisualEffectMaterial: NSVisualEffectView.Material {
        style.nsVisualEffectMaterial
    }
    #endif
}

