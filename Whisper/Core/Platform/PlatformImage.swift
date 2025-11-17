//
//  PlatformImage.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import SwiftUI

#if os(iOS)
import UIKit
typealias PlatformImageType = UIImage
#elseif os(macOS)
import AppKit
typealias PlatformImageType = NSImage
#endif

/// 플랫폼 독립적인 Image 래퍼
struct PlatformImage {
    #if os(iOS)
    private let uiImage: UIImage
    #elseif os(macOS)
    private let nsImage: NSImage
    #endif
    
    #if os(iOS)
    init(_ uiImage: UIImage) {
        self.uiImage = uiImage
    }
    #elseif os(macOS)
    init(_ nsImage: NSImage) {
        self.nsImage = nsImage
    }
    #endif
    
    init?(data: Data) {
        #if os(iOS)
        guard let uiImage = UIImage(data: data) else { return nil }
        self.uiImage = uiImage
        #elseif os(macOS)
        guard let nsImage = NSImage(data: data) else { return nil }
        self.nsImage = nsImage
        #endif
    }
    
    var image: Image {
        #if os(iOS)
        return Image(uiImage: uiImage)
        #elseif os(macOS)
        return Image(nsImage: nsImage)
        #endif
    }
    
    func jpegData(quality: CGFloat) -> Data? {
        #if os(iOS)
        return uiImage.jpegData(compressionQuality: quality)
        #elseif os(macOS)
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: quality])
        #endif
    }
}

