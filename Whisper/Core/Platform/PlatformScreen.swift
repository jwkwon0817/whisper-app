//
//  PlatformScreen.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// 플랫폼 독립적인 Screen 정보
struct PlatformScreen {
    static var main: PlatformScreen {
        PlatformScreen()
    }
    
    var bounds: CGRect {
        #if os(iOS)
        return UIScreen.main.bounds
        #elseif os(macOS)
        return NSScreen.main?.frame ?? .zero
        #endif
    }
    
    var scale: CGFloat {
        #if os(iOS)
        return UIScreen.main.scale
        #elseif os(macOS)
        return NSScreen.main?.backingScaleFactor ?? 1.0
        #endif
    }
    
    var width: CGFloat {
        bounds.width
    }
    
    var height: CGFloat {
        bounds.height
    }
}

