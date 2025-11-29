//
//  E2EEKeyManager.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation
import Security
import CryptoKit

struct EncryptedPrivateKey: Codable {
    let iv: String
    let data: String
}

class E2EEKeyManager {
    static let shared = E2EEKeyManager()
    
    private let salt = "whisper-app-salt-DO-NOT-CHANGE".data(using: .utf8)!
    private let iterations: UInt32 = 100000
    
    private init() {}
    
    func generateRSAKeyPair() throws -> (privateKey: SecKey, publicKey: SecKey) {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: false
            ]
        ]
        
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
              let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw error?.takeRetainedValue() ?? NSError(domain: "E2EEKeyManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "키 페어 생성 실패"])
        }
        
        return (privateKey, publicKey)
    }
    
    func exportPublicKeyToPEM(publicKey: SecKey) throws -> String {
        var error: Unmanaged<CFError>?
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw error?.takeRetainedValue() ?? NSError(domain: "E2EEKeyManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "공개키 내보내기 실패"])
        }
        
        let base64String = publicKeyData.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        
        return "-----BEGIN PUBLIC KEY-----\n\(base64String)\n-----END PUBLIC KEY-----"
    }
    
    private func exportPrivateKeyToPKCS8(privateKey: SecKey) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let privateKeyData = SecKeyCopyExternalRepresentation(privateKey, &error) as Data? else {
            throw error?.takeRetainedValue() ?? NSError(domain: "E2EEKeyManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "개인키 내보내기 실패"])
        }
        
        return privateKeyData
    }
    
    private func deriveKeyFromPassword(_ password: String) throws -> SymmetricKey {
        let passwordData = password.data(using: .utf8)!
        
        let symmetricKey = try PBKDF2.derive(
            password: passwordData,
            salt: salt,
            iterations: iterations,
            keyLength: 32
        )
        
        return SymmetricKey(data: symmetricKey)
    }
    
    func encryptPrivateKey(privateKey: SecKey, password: String) throws -> EncryptedPrivateKey {
        let privateKeyData = try exportPrivateKeyToPKCS8(privateKey: privateKey)
        
        let symmetricKey = try deriveKeyFromPassword(password)
        
        let iv = Data((0..<12).map { _ in UInt8.random(in: 0...255) })
        
        let sealedBox = try AES.GCM.seal(privateKeyData, using: symmetricKey, nonce: AES.GCM.Nonce(data: iv))
        
        let encryptedData = sealedBox.ciphertext + sealedBox.tag
        
        return EncryptedPrivateKey(
            iv: iv.base64EncodedString(),
            data: encryptedData.base64EncodedString()
        )
    }
    
    func decryptPrivateKey(encryptedPrivateKey: EncryptedPrivateKey, password: String) throws -> SecKey {
        let symmetricKey = try deriveKeyFromPassword(password)
        
        guard let iv = Data(base64Encoded: encryptedPrivateKey.iv),
              let encryptedData = Data(base64Encoded: encryptedPrivateKey.data) else {
            throw NSError(domain: "E2EEKeyManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Base64 디코딩 실패"])
        }
        
        let nonce = try AES.GCM.Nonce(data: iv)
        let tagLength = 16
        let ciphertext = encryptedData.prefix(encryptedData.count - tagLength)
        let tag = encryptedData.suffix(tagLength)
        
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        let decryptedData = try AES.GCM.open(sealedBox, using: symmetricKey)
        
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 2048
        ]
        
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateWithData(decryptedData as CFData, attributes as CFDictionary, &error) else {
            throw error?.takeRetainedValue() ?? NSError(domain: "E2EEKeyManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "개인키 복원 실패"])
        }
        
        return privateKey
    }
    
    func saveEncryptedPrivateKey(_ encryptedPrivateKey: EncryptedPrivateKey) {
        let encoder = JSONEncoder()
        if let jsonData = try? encoder.encode(encryptedPrivateKey),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            KeychainHelper.setItem(token: jsonString, forAccount: "e2ee_encrypted_private_key")
        }
    }
    
    func getEncryptedPrivateKey() -> EncryptedPrivateKey? {
        guard let jsonString = KeychainHelper.getItem(forAccount: "e2ee_encrypted_private_key"),
              let jsonData = jsonString.data(using: .utf8) else {
            return nil
        }
        
        let decoder = JSONDecoder()
        return try? decoder.decode(EncryptedPrivateKey.self, from: jsonData)
    }
    
    func deleteEncryptedPrivateKey() {
        KeychainHelper.removeItem(forAccount: "e2ee_encrypted_private_key")
    }
}

enum PBKDF2 {
    static func derive(password: Data, salt: Data, iterations: UInt32, keyLength: Int) throws -> Data {
        var derivedKeyData = Data(count: keyLength)
        
        let status = derivedKeyData.withUnsafeMutableBytes { derivedKeyBytes in
            password.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        password.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        iterations,
                        derivedKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        keyLength
                    )
                }
            }
        }
        
        guard status == kCCSuccess else {
            throw NSError(domain: "PBKDF2", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "PBKDF2 키 파생 실패"])
        }
        
        return derivedKeyData
    }
}

@_silgen_name("CCKeyDerivationPBKDF")
func CCKeyDerivationPBKDF(
    _ algorithm: CCPBKDFAlgorithm,
    _ password: UnsafePointer<UInt8>?,
    _ passwordLen: Int,
    _ salt: UnsafePointer<UInt8>?,
    _ saltLen: Int,
    _ prf: CCPseudoRandomAlgorithm,
    _ rounds: UInt32,
    _ derivedKey: UnsafeMutablePointer<UInt8>?,
    _ derivedKeyLen: Int
) -> Int32

typealias CCPBKDFAlgorithm = UInt32
let kCCPBKDF2: CCPBKDFAlgorithm = 2

typealias CCPseudoRandomAlgorithm = UInt32
let kCCPRFHmacAlgSHA256: CCPseudoRandomAlgorithm = 2

let kCCSuccess: Int32 = 0
