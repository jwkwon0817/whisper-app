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
    
    // MARK: - 하이브리드 암호화 결과
    struct HybridEncryptionResult {
        let encryptedContent: String  // AES로 암호화된 메시지 (Base64)
        let encryptedSessionKey: String  // RSA로 암호화된 AES 세션 키 (Base64) - 상대방 공개키로 암호화
        let selfEncryptedSessionKey: String?  // 내 공개키로 암호화된 AES 세션 키 (Base64) - 양방향 복호화용
    }
    
    // MARK: - 하이브리드 암호화 (RSA + AES) - 권장 방식
    func encryptMessageHybrid(_ message: String, recipientPublicKeyPEM: String, selfPublicKeyPEM: String? = nil) async throws -> HybridEncryptionResult {
        // 1. AES 세션 키 생성 (256비트)
        let sessionKey = SymmetricKey(size: .bits256)
        
        // 2. 메시지를 AES-GCM으로 암호화
        guard let messageData = message.data(using: .utf8) else {
            throw CryptoError.invalidMessage
        }
        
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(messageData, using: sessionKey, nonce: nonce)
        
        // 암호화된 메시지 = nonce + ciphertext + tag
        // nonce는 12바이트
        var encryptedMessageData = Data()
        encryptedMessageData.append(contentsOf: nonce.withUnsafeBytes { Data($0) })
        encryptedMessageData.append(sealedBox.ciphertext)
        encryptedMessageData.append(sealedBox.tag)
        let encryptedContent = encryptedMessageData.base64EncodedString()
        
        // 3. AES 세션 키를 RSA-OAEP로 암호화
        guard let publicKey = try? parsePublicKey(from: recipientPublicKeyPEM) else {
            throw CryptoError.invalidPublicKey
        }
        
        // 세션 키를 Data로 변환
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
        
        // 내 공개키로도 세션 키 암호화 (양방향 복호화용)
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
                    #if DEBUG
                    print("✅ [E2EECryptoManager] 양방향 암호화 완료 - 내 공개키로도 세션 키 암호화")
                    #endif
                } else {
                    #if DEBUG
                    print("⚠️ [E2EECryptoManager] 내 공개키로 세션 키 암호화 실패 - 양방향 암호화 스킵")
                    #endif
                }
            } else {
                #if DEBUG
                print("⚠️ [E2EECryptoManager] 내 공개키 파싱 실패 - 양방향 암호화 스킵")
                #endif
            }
        }
        
        return HybridEncryptionResult(
            encryptedContent: encryptedContent,
            encryptedSessionKey: encryptedSessionKey,
            selfEncryptedSessionKey: selfEncryptedSessionKey
        )
    }
    
    // MARK: - 세션 키 복호화 (내 개인키로 암호화된 세션 키 복호화)
    func decryptSessionKey(encryptedSessionKey: String, password: String) throws -> String {
        // 1. 개인키 가져오기
        guard let encryptedPrivateKey = E2EEKeyManager.shared.getEncryptedPrivateKey() else {
            throw CryptoError.privateKeyNotFound
        }
        
        let privateKey = try E2EEKeyManager.shared.decryptPrivateKey(
            encryptedPrivateKey: encryptedPrivateKey,
            password: password
        )
        
        // 2. RSA로 암호화된 세션 키 복호화
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
    
    // MARK: - AES 단독 암호화 (세션 키 재사용)
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
    
    // MARK: - 하이브리드 복호화 (RSA + AES)
    func decryptMessageHybrid(_ encryptedContent: String, encryptedSessionKey: String, password: String) async throws -> String {
        // 1. 개인키 가져오기
        guard let encryptedPrivateKey = E2EEKeyManager.shared.getEncryptedPrivateKey() else {
            throw CryptoError.privateKeyNotFound
        }
        
        let privateKey = try E2EEKeyManager.shared.decryptPrivateKey(
            encryptedPrivateKey: encryptedPrivateKey,
            password: password
        )
        
        // 2. RSA로 암호화된 세션 키 복호화
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
        
        // 3. 세션 키를 SymmetricKey로 변환
        let sessionKey = SymmetricKey(data: sessionKeyData)
        
        // 4. AES-GCM으로 암호화된 메시지 복호화
        guard let encryptedMessageData = Data(base64Encoded: encryptedContent) else {
            throw CryptoError.invalidEncryptedMessage
        }
        
        // nonce는 12바이트, tag는 16바이트
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
        
        // 5. String으로 변환
        guard let message = String(data: decryptedData, encoding: .utf8) else {
            throw CryptoError.invalidMessage
        }
        
        return message
    }
    
    // MARK: - 하이브리드 복호화 (내 공개키로 암호화된 세션 키 사용 - 양방향 암호화)
    func decryptMessageHybridWithSelfKey(_ encryptedContent: String, selfEncryptedSessionKey: String, password: String) async throws -> String {
        // 1. 개인키 가져오기
        guard let encryptedPrivateKey = E2EEKeyManager.shared.getEncryptedPrivateKey() else {
            throw CryptoError.privateKeyNotFound
        }
        
        let privateKey = try E2EEKeyManager.shared.decryptPrivateKey(
            encryptedPrivateKey: encryptedPrivateKey,
            password: password
        )
        
        // 2. RSA로 암호화된 세션 키 복호화 (내 공개키로 암호화된 것을 내 개인키로 복호화)
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
        
        // 3. 세션 키를 SymmetricKey로 변환
        let sessionKey = SymmetricKey(data: sessionKeyData)
        
        // 4. AES-GCM으로 암호화된 메시지 복호화
        guard let encryptedMessageData = Data(base64Encoded: encryptedContent) else {
            throw CryptoError.invalidEncryptedMessage
        }
        
        // nonce는 12바이트, tag는 16바이트
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
        
        // 5. String으로 변환
        guard let message = String(data: decryptedData, encoding: .utf8) else {
            throw CryptoError.invalidMessage
        }
        
        return message
    }
    
    // MARK: - 메시지 암호화 (RSA-OAEP) - 기존 방식 (하위 호환성)
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
    
    // MARK: - 메시지 복호화 (RSA-OAEP 또는 하이브리드 자동 감지)
    func decryptMessage(_ encryptedMessage: String, encryptedSessionKey: String?, password: String) async throws -> String {
        // 하이브리드 방식인지 확인
        if let encryptedSessionKey = encryptedSessionKey {
            return try await decryptMessageHybrid(encryptedMessage, encryptedSessionKey: encryptedSessionKey, password: password)
        } else {
            // 기존 RSA-OAEP 방식
            return try await decryptMessageLegacy(encryptedMessage, password: password)
        }
    }
    
    // MARK: - 메시지 복호화 (RSA-OAEP) - 기존 방식 (하위 호환성)
    func decryptMessageLegacy(_ encryptedMessage: String, password: String) async throws -> String {
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
