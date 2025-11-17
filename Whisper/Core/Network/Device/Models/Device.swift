//
//  Device.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation

struct Device: Codable, Identifiable {
    let id: String
    let deviceName: String
    let deviceFingerprint: String
    let isPrimary: Bool
    let lastActive: String?
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case deviceName = "device_name"
        case deviceFingerprint = "device_fingerprint"
        case isPrimary = "is_primary"
        case lastActive = "last_active"
        case createdAt = "created_at"
    }
    
    var isCurrentDevice: Bool {
        if let currentFingerprint = DeviceManager.shared.getStoredDeviceFingerprint() {
            return deviceFingerprint == currentFingerprint
        }
        return false
    }
    
    var lastActiveFormatted: String {
        guard let lastActive = lastActive else {
            return "활동 기록 없음"
        }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: lastActive) {
            let relativeFormatter = RelativeDateTimeFormatter()
            relativeFormatter.unitsStyle = .full
            relativeFormatter.locale = Locale(identifier: "ko_KR")
            return relativeFormatter.localizedString(for: date, relativeTo: Date())
        }
        
        return lastActive
    }
    
    var createdAtFormatted: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: createdAt) {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .short
            dateFormatter.locale = Locale(identifier: "ko_KR")
            return dateFormatter.string(from: date)
        }
        
        return createdAt
    }
}

struct DevicePrivateKeyResponse: Codable {
    let deviceId: String
    let deviceName: String
    let encryptedPrivateKey: String
    
    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case deviceName = "device_name"
        case encryptedPrivateKey = "encrypted_private_key"
    }
}

