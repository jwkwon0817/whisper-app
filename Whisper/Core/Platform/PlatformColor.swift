//
//  PlatformColor.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import SwiftUI

#if os(iOS)
import UIKit
typealias PlatformColorType = UIColor
#elseif os(macOS)
import AppKit
typealias PlatformColorType = NSColor
#endif

struct PlatformColor {
    #if os(iOS)
    private let uiColor: UIColor
    #elseif os(macOS)
    private let nsColor: NSColor
    #endif
    
    #if os(iOS)
    init(_ uiColor: UIColor) {
        self.uiColor = uiColor
    }
    #elseif os(macOS)
    init(_ nsColor: NSColor) {
        self.nsColor = nsColor
    }
    #endif
    
    var color: Color {
        #if os(iOS)
        return Color(uiColor: uiColor)
        #elseif os(macOS)
        return Color(nsColor: nsColor)
        #endif
    }
    
    static func dynamic(light: Color, dark: Color) -> PlatformColor {
        #if os(iOS)
        return PlatformColor(UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .light:
                return UIColor(light)
            case .dark:
                return UIColor(dark)
            case .unspecified:
                return UIColor(light)
            @unknown default:
                return UIColor(light)
            }
        })
        #elseif os(macOS)
        let appearance = NSAppearance.current
        if appearance?.name == .darkAqua || appearance?.name == .vibrantDark {
            return PlatformColor(NSColor(dark))
        } else {
            return PlatformColor(NSColor(light))
        }
        #endif
    }
}

extension Color {
    init(light: Color, dark: Color) {
        self = PlatformColor.dynamic(light: light, dark: dark).color
    }
}

