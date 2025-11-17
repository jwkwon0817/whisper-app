//
//  DeviceService.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation
import Moya

class DeviceService: BaseService<DeviceAPI> {
    /// 기기 목록 조회
    func getDevices() async throws -> [Device] {
        return try await request(.getDevices, as: [Device].self)
    }
    
    /// 특정 기기의 암호화된 개인키 조회
    func getDevicePrivateKey(deviceId: String) async throws -> DevicePrivateKeyResponse {
        return try await request(.getDevicePrivateKey(deviceId: deviceId), as: DevicePrivateKeyResponse.self)
    }
    
    /// 새 기기 등록
    func registerDevice(deviceName: String, deviceFingerprint: String, encryptedPrivateKey: String) async throws -> Device {
        return try await request(.registerDevice(
            deviceName: deviceName,
            deviceFingerprint: deviceFingerprint,
            encryptedPrivateKey: encryptedPrivateKey
        ), as: Device.self)
    }
    
    /// 기기 삭제
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

