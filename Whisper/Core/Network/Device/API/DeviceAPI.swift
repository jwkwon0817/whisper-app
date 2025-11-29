//
//  DeviceAPI.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation
import Moya
internal import Alamofire

enum DeviceAPI {
    case getDevices
    case getDevicePrivateKey(deviceId: String)
    case registerDevice(deviceName: String, deviceFingerprint: String, encryptedPrivateKey: String)
}

extension DeviceAPI: TargetType {
    var baseURL: URL {
        return URL(string: EnvironmentVariables.baseURL)!
    }
    
    var path: String {
        switch self {
        case .getDevices, .registerDevice:
            return "/api/devices/"
        case .getDevicePrivateKey(let deviceId):
            return "/api/devices/\(deviceId)/private-key/"
        }
    }
    
    var method: Moya.Method {
        switch self {
        case .getDevices, .getDevicePrivateKey:
            return .get
        case .registerDevice:
            return .post
        }
    }
    
    var task: Task {
        switch self {
        case .getDevices, .getDevicePrivateKey:
            return .requestPlain
        case .registerDevice(let deviceName, let deviceFingerprint, let encryptedPrivateKey):
            let parameters: [String: Any] = [
                "device_name": deviceName,
                "device_fingerprint": deviceFingerprint,
                "encrypted_private_key": encryptedPrivateKey
            ]
            return .requestParameters(parameters: parameters, encoding: JSONEncoding.default)
        }
    }
    
    var headers: [String: String]? {
        return ["Content-Type": "application/json"]
    }
    
    var validationType: ValidationType {
        return .successCodes
    }
}

