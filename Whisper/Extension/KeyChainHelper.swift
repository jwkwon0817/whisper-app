//
//  KeyChainHelper.swift
//  Whisper
//
//  Created by  jwkwon0817 on 11/17/25.
//

import Foundation
import Security

class KeychainHelper {
    static let serviceName = "Whisper"
    
    static func getItem(forAccount account: String) -> String? {
        let keychainItem = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: account,
            kSecAttrService: serviceName,
            kSecReturnData: true
        ] as [String: Any]
        
        var item: AnyObject?
        let status = SecItemCopyMatching(keychainItem as CFDictionary, &item)
        if status == errSecSuccess {
            return String(data: item as! Data, encoding: .utf8)
        }
        
        if status == errSecItemNotFound {
            print("The token was not found in keychain")
            return nil
        } else {
            print("Error getting token from keychain: \(status)")
            return nil
        }
    }
    
    @discardableResult
    static func setItem(token: String, forAccount account: String) -> Bool {
        if getItem(forAccount: account) != nil {
            let keychainItem = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrAccount: account,
                kSecAttrService: serviceName
            ] as [String: Any]
            
            let attributes = [
                kSecValueData: token.data(using: .utf8) as Any
            ] as [String: Any]
            
            let status = SecItemUpdate(keychainItem as CFDictionary, attributes as CFDictionary)
            guard status == errSecSuccess else {
                print("Keychain update error: \(status)")
                return false
            }
            print("The token in keychain is updated")
            return true
        } else {
            let keychainItem = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrAccount: account,
                kSecAttrService: serviceName,
                kSecValueData: token.data(using: .utf8) as Any
            ] as [String: Any]
            
            let status = SecItemAdd(keychainItem as CFDictionary, nil)
            guard status == errSecSuccess else {
                print("Keychain create error: \(status)")
                return false
            }
            print("The token is added to keychain")
            return true
        }
    }
    
    @discardableResult
    static func removeItem(forAccount account: String) -> Bool {
        let keychainItem = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: account
        ] as [String: Any]
        
        let status = SecItemDelete(keychainItem as CFDictionary)
        guard status != errSecItemNotFound else {
            print("The token was not found in keychain")
            return false
        }
        guard status == errSecSuccess else {
            print("Keychain delete error: \(status)")
            return false
        }
        print("The token in keychain is deleted")
        return true
    }
}
