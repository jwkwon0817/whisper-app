//
//  DeviceService.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation
import Moya

class DeviceService: BaseService<DeviceAPI> {
    func getDevices() async throws -> [Device] {
        return try await request(.getDevices, as: [Device].self)
    }
    
    func getDevicePrivateKey(deviceId: String) async throws -> DevicePrivateKeyResponse {
        return try await request(.getDevicePrivateKey(deviceId: deviceId), as: DevicePrivateKeyResponse.self)
    }
    
    func registerDevice(deviceName: String, deviceFingerprint: String, encryptedPrivateKey: String) async throws -> Device {
        return try await request(.registerDevice(
            deviceName: deviceName,
            deviceFingerprint: deviceFingerprint,
            encryptedPrivateKey: encryptedPrivateKey
        ), as: Device.self)
    }
    
    func deleteDevice(deviceId: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            provider.request(.deleteDevice(deviceId: deviceId)) { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

