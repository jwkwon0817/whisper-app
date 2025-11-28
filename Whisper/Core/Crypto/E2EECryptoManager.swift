//
//  E2EECryptoManager.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation
import Security
import CryptoKit

class E2EECryptoManager {
    static let shared = E2EECryptoManager()
    
    private init() {}
    
    struct HybridEncryptionResult {
        let encryptedContent: String 
        let encryptedSessionKey: String 
        let selfEncryptedSessionKey: String? 
    }
    
    func encryptMessageHybrid(_ message: String, recipientPublicKeyPEM: String, selfPublicKeyPEM: String? = nil) async throws -> HybridEncryptionResult {
        let sessionKey = SymmetricKey(size: .bits256)
        
        guard let messageData = message.data(using: .utf8) else {
            throw CryptoError.invalidMessage
        }
        
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(messageData, using: sessionKey, nonce: nonce)
        
        var encryptedMessageData = Data()
        encryptedMessageData.append(contentsOf: nonce.withUnsafeBytes { Data($0) })
        encryptedMessageData.append(sealedBox.ciphertext)
        encryptedMessageData.append(sealedBox.tag)
        let encryptedContent = encryptedMessageData.base64EncodedString()
        
        guard let publicKey = try? parsePublicKey(from: recipientPublicKeyPEM) else {
            throw CryptoError.invalidPublicKey
        }
        
        let sessionKeyData = sessionKey.withUnsafeBytes { Data($0) }
        
        var error: Unmanaged<CFError>?
        guard let encryptedSessionKeyData = SecKeyCreateEncryptedData(
            publicKey,
            .rsaEncryptionOAEPSHA256,
            sessionKeyData as CFData,
            &error
        ) as Data? else {
            throw CryptoError.encryptionFailed
        }
        
        let encryptedSessionKey = encryptedSessionKeyData.base64EncodedString()
        
        var selfEncryptedSessionKey: String? = nil
        if let selfPublicKeyPEM = selfPublicKeyPEM {
            if let selfPublicKey = try? parsePublicKey(from: selfPublicKeyPEM) {
                var selfError: Unmanaged<CFError>?
                if let selfEncryptedSessionKeyData = SecKeyCreateEncryptedData(
                    selfPublicKey,
                    .rsaEncryptionOAEPSHA256,
                    sessionKeyData as CFData,
                    &selfError
                ) as Data? {
                    selfEncryptedSessionKey = selfEncryptedSessionKeyData.base64EncodedString()
                }
            } else {
            }
        }
        
        return HybridEncryptionResult(
            encryptedContent: encryptedContent,
            encryptedSessionKey: encryptedSessionKey,
            selfEncryptedSessionKey: selfEncryptedSessionKey
        )
    }
    
    func decryptSessionKey(encryptedSessionKey: String, password: String) throws -> String {
        guard let encryptedPrivateKey = E2EEKeyManager.shared.getEncryptedPrivateKey() else {
            throw CryptoError.privateKeyNotFound
        }
        
        let privateKey = try E2EEKeyManager.shared.decryptPrivateKey(
            encryptedPrivateKey: encryptedPrivateKey,
            password: password
        )
        
        guard let encryptedSessionKeyData = Data(base64Encoded: encryptedSessionKey) else {
            throw CryptoError.invalidEncryptedMessage
        }
        
        var error: Unmanaged<CFError>?
        guard let sessionKeyData = SecKeyCreateDecryptedData(
            privateKey,
            .rsaEncryptionOAEPSHA256,
            encryptedSessionKeyData as CFData,
            &error
        ) as Data? else {
            throw CryptoError.decryptionFailed
        }
        
        return sessionKeyData.base64EncodedString()
    }
    
    func encryptMessageWithSessionKey(_ message: String, sessionKey: String) throws -> String {
        guard let sessionKeyData = Data(base64Encoded: sessionKey) else {
            throw CryptoError.encryptionFailed
        }
        
        let symmetricKey = SymmetricKey(data: sessionKeyData)
        
        guard let messageData = message.data(using: .utf8) else {
            throw CryptoError.invalidMessage
        }
        
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(messageData, using: symmetricKey, nonce: nonce)
        
        var encryptedMessageData = Data()
        encryptedMessageData.append(contentsOf: nonce.withUnsafeBytes { Data($0) })
        encryptedMessageData.append(sealedBox.ciphertext)
        encryptedMessageData.append(sealedBox.tag)
        
        return encryptedMessageData.base64EncodedString()
    }
    
    func decryptMessageHybrid(_ encryptedContent: String, encryptedSessionKey: String, password: String) async throws -> String {
        guard let encryptedPrivateKey = E2EEKeyManager.shared.getEncryptedPrivateKey() else {
            throw CryptoError.privateKeyNotFound
        }
        
        let privateKey = try E2EEKeyManager.shared.decryptPrivateKey(
            encryptedPrivateKey: encryptedPrivateKey,
            password: password
        )
        
        guard let encryptedSessionKeyData = Data(base64Encoded: encryptedSessionKey) else {
            throw CryptoError.invalidEncryptedMessage
        }
        
        var error: Unmanaged<CFError>?
        guard let sessionKeyData = SecKeyCreateDecryptedData(
            privateKey,
            .rsaEncryptionOAEPSHA256,
            encryptedSessionKeyData as CFData,
            &error
        ) as Data? else {
            throw CryptoError.decryptionFailed
        }
        
        let sessionKey = SymmetricKey(data: sessionKeyData)
        
        guard let encryptedMessageData = Data(base64Encoded: encryptedContent) else {
            throw CryptoError.invalidEncryptedMessage
        }
        
        guard encryptedMessageData.count >= 28 else {
            throw CryptoError.invalidEncryptedMessage
        }
        
        let nonceData = encryptedMessageData.prefix(12)
        let ciphertextAndTag = encryptedMessageData.suffix(from: 12)
        let tag = ciphertextAndTag.suffix(16)
        let ciphertext = ciphertextAndTag.prefix(ciphertextAndTag.count - 16)
        
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        
        let decryptedData = try AES.GCM.open(sealedBox, using: sessionKey)
        
        guard let message = String(data: decryptedData, encoding: .utf8) else {
            throw CryptoError.invalidMessage
        }
        
        return message
    }
    
    func decryptMessageHybridWithSelfKey(_ encryptedContent: String, selfEncryptedSessionKey: String, password: String) async throws -> String {
        guard let encryptedPrivateKey = E2EEKeyManager.shared.getEncryptedPrivateKey() else {
            throw CryptoError.privateKeyNotFound
        }
        
        let privateKey = try E2EEKeyManager.shared.decryptPrivateKey(
            encryptedPrivateKey: encryptedPrivateKey,
            password: password
        )
        
        guard let encryptedSessionKeyData = Data(base64Encoded: selfEncryptedSessionKey) else {
            throw CryptoError.invalidEncryptedMessage
        }
        
        var error: Unmanaged<CFError>?
        guard let sessionKeyData = SecKeyCreateDecryptedData(
            privateKey,
            .rsaEncryptionOAEPSHA256,
            encryptedSessionKeyData as CFData,
            &error
        ) as Data? else {
            throw CryptoError.decryptionFailed
        }
        
        let sessionKey = SymmetricKey(data: sessionKeyData)
        
        guard let encryptedMessageData = Data(base64Encoded: encryptedContent) else {
            throw CryptoError.invalidEncryptedMessage
        }
        
        guard encryptedMessageData.count >= 28 else {
            throw CryptoError.invalidEncryptedMessage
        }
        
        let nonceData = encryptedMessageData.prefix(12)
        let ciphertextAndTag = encryptedMessageData.suffix(from: 12)
        let tag = ciphertextAndTag.suffix(16)
        let ciphertext = ciphertextAndTag.prefix(ciphertextAndTag.count - 16)
        
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        
        let decryptedData = try AES.GCM.open(sealedBox, using: sessionKey)
        
        guard let message = String(data: decryptedData, encoding: .utf8) else {
            throw CryptoError.invalidMessage
        }
        
        return message
    }
    
    func encryptMessage(_ message: String, recipientPublicKeyPEM: String) async throws -> String {
        guard let publicKey = try? parsePublicKey(from: recipientPublicKeyPEM) else {
            throw CryptoError.invalidPublicKey
        }
        
        guard let messageData = message.data(using: .utf8) else {
            throw CryptoError.invalidMessage
        }
        
        var error: Unmanaged<CFError>?
        guard let encryptedData = SecKeyCreateEncryptedData(
            publicKey,
            .rsaEncryptionOAEPSHA256,
            messageData as CFData,
            &error
        ) as Data? else {
            throw CryptoError.encryptionFailed
        }
        
        return encryptedData.base64EncodedString()
    }
    
    func decryptMessage(_ encryptedMessage: String, encryptedSessionKey: String?, password: String) async throws -> String {
        if let encryptedSessionKey = encryptedSessionKey {
            return try await decryptMessageHybrid(encryptedMessage, encryptedSessionKey: encryptedSessionKey, password: password)
        } else {
            return try await decryptMessageLegacy(encryptedMessage, password: password)
        }
    }
    
    func decryptMessageLegacy(_ encryptedMessage: String, password: String) async throws -> String {
        guard let encryptedPrivateKey = E2EEKeyManager.shared.getEncryptedPrivateKey() else {
            throw CryptoError.privateKeyNotFound
        }
        
        let privateKey = try E2EEKeyManager.shared.decryptPrivateKey(
            encryptedPrivateKey: encryptedPrivateKey,
            password: password
        )
        
        guard let encryptedData = Data(base64Encoded: encryptedMessage) else {
            throw CryptoError.invalidEncryptedMessage
        }
        
        var error: Unmanaged<CFError>?
        guard let decryptedData = SecKeyCreateDecryptedData(
            privateKey,
            .rsaEncryptionOAEPSHA256,
            encryptedData as CFData,
            &error
        ) as Data? else {
            throw CryptoError.decryptionFailed
        }
        
        guard let message = String(data: decryptedData, encoding: .utf8) else {
            throw CryptoError.invalidMessage
        }
        
        return message
    }
    
    private func parsePublicKey(from pemString: String) throws -> SecKey {
        let base64String = pemString
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: " ", with: "")
        
        guard let keyData = Data(base64Encoded: base64String) else {
            throw CryptoError.invalidPublicKey
        }
        
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
