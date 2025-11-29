//
//  MessageCacheManager.swift
//  Whisper
//
//  Created by Refactoring on 11/28/25.
//

import Foundation

@MainActor
final class MessageCacheManager {
    
    private let roomId: String
    
    private var sentMessagesStorageKey: String {
        "sent_messages_\(roomId)"
    }
    
    init(roomId: String) {
        self.roomId = roomId
    }
    
    func saveSentMessageContent(messageId: String, content: String) {
        var savedMessages = UserDefaults.standard.dictionary(forKey: sentMessagesStorageKey) as? [String: String] ?? [:]
        savedMessages[messageId] = content
        UserDefaults.standard.set(savedMessages, forKey: sentMessagesStorageKey)
    }
    
    func loadSentMessageContent(messageId: String) -> String? {
        let savedMessages = UserDefaults.standard.dictionary(forKey: sentMessagesStorageKey) as? [String: String] ?? [:]
        return savedMessages[messageId]
    }
    
    func removeSentMessageContent(messageId: String) {
        var savedMessages = UserDefaults.standard.dictionary(forKey: sentMessagesStorageKey) as? [String: String] ?? [:]
        savedMessages.removeValue(forKey: messageId)
        UserDefaults.standard.set(savedMessages, forKey: sentMessagesStorageKey)
    }
    
    func clearAllSentMessages() {
        UserDefaults.standard.removeObject(forKey: sentMessagesStorageKey)
    }
    
    func getSavedMessageIds() -> [String] {
        let savedMessages = UserDefaults.standard.dictionary(forKey: sentMessagesStorageKey) as? [String: String] ?? [:]
        return Array(savedMessages.keys)
    }
}

