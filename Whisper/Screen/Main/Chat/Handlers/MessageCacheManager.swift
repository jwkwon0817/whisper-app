//
//  MessageCacheManager.swift
//  Whisper
//
//  Created by Refactoring on 11/28/25.
//

import Foundation

/// 전송한 메시지 원본 내용 캐시 관리를 담당하는 매니저
@MainActor
final class MessageCacheManager {
    
    // MARK: - State
    
    private let roomId: String
    
    private var sentMessagesStorageKey: String {
        "sent_messages_\(roomId)"
    }
    
    // MARK: - Init
    
    init(roomId: String) {
        self.roomId = roomId
    }
    
    // MARK: - Public Methods
    
    /// 전송한 메시지 원본 내용 저장
    func saveSentMessageContent(messageId: String, content: String) {
        var savedMessages = UserDefaults.standard.dictionary(forKey: sentMessagesStorageKey) as? [String: String] ?? [:]
        savedMessages[messageId] = content
        UserDefaults.standard.set(savedMessages, forKey: sentMessagesStorageKey)
    }
    
    /// 전송한 메시지 원본 내용 로드
    func loadSentMessageContent(messageId: String) -> String? {
        let savedMessages = UserDefaults.standard.dictionary(forKey: sentMessagesStorageKey) as? [String: String] ?? [:]
        return savedMessages[messageId]
    }
    
    /// 전송한 메시지 원본 내용 삭제
    func removeSentMessageContent(messageId: String) {
        var savedMessages = UserDefaults.standard.dictionary(forKey: sentMessagesStorageKey) as? [String: String] ?? [:]
        savedMessages.removeValue(forKey: messageId)
        UserDefaults.standard.set(savedMessages, forKey: sentMessagesStorageKey)
    }
    
    /// 모든 전송 메시지 캐시 삭제
    func clearAllSentMessages() {
        UserDefaults.standard.removeObject(forKey: sentMessagesStorageKey)
    }
    
    /// 저장된 메시지 ID 목록 가져오기
    func getSavedMessageIds() -> [String] {
        let savedMessages = UserDefaults.standard.dictionary(forKey: sentMessagesStorageKey) as? [String: String] ?? [:]
        return Array(savedMessages.keys)
    }
}

