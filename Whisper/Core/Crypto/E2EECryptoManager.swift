//
//  E2EECryptoManager.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation
import Security
import CryptoKit

// MARK: - E2EE Crypto Manager
class E2EECryptoManager {
    static let shared = E2EECryptoManager()
    
    private init() {}
    
    // MARK: - 메시지 암호화 (RSA-OAEP)
    func encryptMessage(_ message: String, recipientPublicKeyPEM: String) async throws -> String {
        // PEM 형식의 공개키를 SecKey로 변환
        guard let publicKey = try? parsePublicKey(from: recipientPublicKeyPEM) else {
            throw CryptoError.invalidPublicKey
        }
        
        // 메시지를 Data로 변환
        guard let messageData = message.data(using: .utf8) else {
            throw CryptoError.invalidMessage
        }
        
        // RSA-OAEP로 암호화
        var error: Unmanaged<CFError>?
        guard let encryptedData = SecKeyCreateEncryptedData(
            publicKey,
            .rsaEncryptionOAEPSHA256,
            messageData as CFData,
            &error
        ) as Data? else {
            throw CryptoError.encryptionFailed
        }
        
        // Base64로 인코딩하여 반환
        return encryptedData.base64EncodedString()
    }
    
    // MARK: - 메시지 복호화 (RSA-OAEP)
    func decryptMessage(_ encryptedMessage: String, password: String) async throws -> String {
        // 개인키 가져오기 (Keychain에서 암호화된 개인키를 복호화)
        guard let encryptedPrivateKey = E2EEKeyManager.shared.getEncryptedPrivateKey() else {
            throw CryptoError.privateKeyNotFound
        }
        
        let privateKey = try E2EEKeyManager.shared.decryptPrivateKey(
            encryptedPrivateKey: encryptedPrivateKey,
            password: password
        )
        
        // Base64 디코딩
        guard let encryptedData = Data(base64Encoded: encryptedMessage) else {
            throw CryptoError.invalidEncryptedMessage
        }
        
        // RSA-OAEP로 복호화
        var error: Unmanaged<CFError>?
        guard let decryptedData = SecKeyCreateDecryptedData(
            privateKey,
            .rsaEncryptionOAEPSHA256,
            encryptedData as CFData,
            &error
        ) as Data? else {
            throw CryptoError.decryptionFailed
        }
        
        // String으로 변환하여 반환
        guard let message = String(data: decryptedData, encoding: .utf8) else {
            throw CryptoError.invalidMessage
        }
        
        return message
    }
    
    // MARK: - PEM 공개키 파싱
    private func parsePublicKey(from pemString: String) throws -> SecKey {
        // PEM 헤더/푸터 제거
        let base64String = pemString
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: " ", with: "")
        
        guard let keyData = Data(base64Encoded: base64String) else {
            throw CryptoError.invalidPublicKey
        }
        
        // SecKey 생성
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: 2048
        ]
        
        var error: Unmanaged<CFError>?
        guard let publicKey = SecKeyCreateWithData(
            keyData as CFData,
            attributes as CFDictionary,
            &error
        ) else {
            throw CryptoError.invalidPublicKey
        }
        
        return publicKey
    }
}

// MARK: - Crypto Errors
enum CryptoError: LocalizedError {
    case invalidPublicKey
    case invalidMessage
    case encryptionFailed
    case decryptionFailed
    case invalidEncryptedMessage
    case privateKeyNotFound
    
    var errorDescription: String? {
        switch self {
        case .invalidPublicKey:
            return "유효하지 않은 공개키입니다."
        case .invalidMessage:
            return "유효하지 않은 메시지입니다."
        case .encryptionFailed:
            return "암호화에 실패했습니다."
        case .decryptionFailed:
            return "복호화에 실패했습니다."
        case .invalidEncryptedMessage:
            return "유효하지 않은 암호화된 메시지입니다."
        case .privateKeyNotFound:
            return "개인키를 찾을 수 없습니다."
        }
    }
}

