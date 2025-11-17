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
    
    /// 기기 지문 생성 (고유한 기기 식별자)
    func generateDeviceFingerprint() -> String {
        var components: [String] = []
        
        // 기기 정보 수집
        #if os(iOS)
        components.append(UIDevice.current.identifierForVendor?.uuidString ?? "unknown")
        components.append(UIDevice.current.model)
        components.append(UIDevice.current.systemVersion)
        #elseif os(macOS)
        // macOS에서는 호스트 이름과 하드웨어 UUID 사용
        let hostName = Host.current().name ?? "unknown"
        components.append(hostName)
        components.append("Mac")
        
        // 시스템 버전
        let version = ProcessInfo.processInfo.operatingSystemVersionString
        components.append(version)
        #else
        components.append("unknown")
        components.append("Unknown")
        components.append("Unknown")
        #endif
        
        components.append(Locale.current.identifier)
        components.append(TimeZone.current.identifier)
        
        // 화면 정보
        let screen = PlatformScreen.main
        components.append("\(Int(screen.width))x\(Int(screen.height))")
        components.append("\(screen.scale)")
        
        // 앱 버전
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            components.append(version)
        }
        
        // 랜덤 값 (앱 설치 시 한 번만 생성되어 저장됨)
        let storedRandom = UserDefaults.standard.string(forKey: "device_fingerprint_random")
        let random: String
        if let stored = storedRandom {
            random = stored
        } else {
            random = UUID().uuidString
            UserDefaults.standard.set(random, forKey: "device_fingerprint_random")
        }
        components.append(random)
        
        // 모든 정보를 합쳐서 해시 생성
        let fingerprintString = components.joined(separator: "|")
        let hash = SHA256.hash(data: fingerprintString.data(using: .utf8)!)
        
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// 기기 이름 자동 감지
    func getDeviceName() -> String {
        #if os(iOS)
        let device = UIDevice.current
        
        // 모바일 기기
        if device.userInterfaceIdiom == .phone {
            return "iPhone"
        } else if device.userInterfaceIdiom == .pad {
            return "iPad"
        }
        
        // 시뮬레이터
        #if targetEnvironment(simulator)
        return "iOS Simulator"
        #else
        // 기타
        return device.model
        #endif
        
        #elseif os(macOS)
        // macOS에서는 호스트 이름 사용
        let hostName = Host.current().name ?? "Mac"
        return hostName
        
        #else
        return "Unknown Device"
        #endif
    }
    
    /// 저장된 기기 지문 가져오기
    func getStoredDeviceFingerprint() -> String? {
        return UserDefaults.standard.string(forKey: "device_fingerprint")
    }
    
    /// 기기 지문 저장
    func saveDeviceFingerprint(_ fingerprint: String) {
        UserDefaults.standard.set(fingerprint, forKey: "device_fingerprint")
    }
    
    /// 현재 기기가 기존 기기인지 확인
    func isExistingDevice() -> Bool {
        let currentFingerprint = generateDeviceFingerprint()
        let storedFingerprint = getStoredDeviceFingerprint()
        return storedFingerprint == currentFingerprint
    }
}

