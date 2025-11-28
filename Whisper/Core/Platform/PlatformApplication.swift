//
//  PlatformApplication.swift
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

struct PlatformApplication {
    static var shared: PlatformApplication {
        PlatformApplication()
    }
    
    func resignFirstResponder() {
        #if os(iOS)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        #elseif os(macOS)
        NSApplication.shared.keyWindow?.makeFirstResponder(nil)
        #endif
    }
}

