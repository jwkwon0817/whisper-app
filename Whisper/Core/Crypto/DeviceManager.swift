//
//  DeviceManager.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation
import CryptoKit

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

class DeviceManager {
    static let shared = DeviceManager()
    
    private init() {}
    
    func generateDeviceFingerprint() -> String {
        var components: [String] = []
        
        #if os(iOS)
        components.append(UIDevice.current.identifierForVendor?.uuidString ?? "unknown")
        components.append(UIDevice.current.model)
        components.append(UIDevice.current.systemVersion)
        #elseif os(macOS)
        let hostName = Host.current().name ?? "unknown"
        components.append(hostName)
        components.append("Mac")
        
        let version = ProcessInfo.processInfo.operatingSystemVersionString
        components.append(version)
        #else
        components.append("unknown")
        components.append("Unknown")
        components.append("Unknown")
        #endif
        
        components.append(Locale.current.identifier)
        components.append(TimeZone.current.identifier)
        
        let screen = PlatformScreen.main
        components.append("\(Int(screen.width))x\(Int(screen.height))")
        components.append("\(screen.scale)")
        
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            components.append(version)
        }
        
        let storedRandom = UserDefaults.standard.string(forKey: "device_fingerprint_random")
        let random: String
        if let stored = storedRandom {
            random = stored
        } else {
            random = UUID().uuidString
            UserDefaults.standard.set(random, forKey: "device_fingerprint_random")
        }
        components.append(random)
        
        let fingerprintString = components.joined(separator: "|")
        let hash = SHA256.hash(data: fingerprintString.data(using: .utf8)!)
        
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    func getDeviceName() -> String {
        #if os(iOS)
        let device = UIDevice.current
        
        if device.userInterfaceIdiom == .phone {
            return "iPhone"
        } else if device.userInterfaceIdiom == .pad {
            return "iPad"
        }
        
        #if targetEnvironment(simulator)
        return "iOS Simulator"
        #else
        return device.model
        #endif
        
        #elseif os(macOS)
        let hostName = Host.current().name ?? "Mac"
        return hostName
        
        #else
        return "Unknown Device"
        #endif
    }
    
    func getStoredDeviceFingerprint() -> String? {
        return UserDefaults.standard.string(forKey: "device_fingerprint")
    }
    
    func saveDeviceFingerprint(_ fingerprint: String) {
        UserDefaults.standard.set(fingerprint, forKey: "device_fingerprint")
    }
    
    func isExistingDevice() -> Bool {
        let currentFingerprint = generateDeviceFingerprint()
        let storedFingerprint = getStoredDeviceFingerprint()
        return storedFingerprint == currentFingerprint
    }
}

