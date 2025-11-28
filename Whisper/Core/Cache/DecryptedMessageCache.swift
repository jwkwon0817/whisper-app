//
//  DecryptedMessageCache.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/27/25.
//

import Foundation

/// 복호화된 메시지를 디스크에 영구 저장하는 캐시
actor DecryptedMessageCache {
    static let shared = DecryptedMessageCache()
    
    private let cacheDirectory: URL
    private var memoryCache: [String: [String: String]] = [:] // roomId -> [messageId: decryptedContent]
    
    private init() {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDirectory = cacheDir.appendingPathComponent("DecryptedMessages")
        
        // 디렉토리 생성
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Public Methods
    
    /// 복호화된 메시지 저장
    func save(roomId: String, messageId: String, decryptedContent: String) async {
        // 버그 수정: 빈 문자열은 저장하지 않음
        guard !decryptedContent.isEmpty else {
            #if DEBUG
            print("⚠️ [DecryptedMessageCache] 빈 문자열 저장 시도 무시: \(messageId)")
            #endif
            return
        }
        
        // 메모리 캐시에 저장
        if memoryCache[roomId] == nil {
            memoryCache[roomId] = [:]
        }
        memoryCache[roomId]?[messageId] = decryptedContent
        
        // 디스크에 저장 (동기적으로 완료 확인)
        let success = await saveToDisk(roomId: roomId, messageId: messageId, decryptedContent: decryptedContent)
        
        // 버그 수정: 디스크 저장 실패 시 메모리 캐시도 롤백
        if !success {
            memoryCache[roomId]?.removeValue(forKey: messageId)
            #if DEBUG
            print("⚠️ [DecryptedMessageCache] 디스크 저장 실패로 메모리 캐시도 롤백: \(messageId)")
            #endif
        }
    }
    
    /// 복호화된 메시지 조회
    func get(roomId: String, messageId: String) async -> String? {
        // 메모리 캐시에서 먼저 확인
        if let cached = memoryCache[roomId]?[messageId] {
            return cached
        }
        
        // 디스크에서 조회
        if let content = await getFromDisk(roomId: roomId, messageId: messageId) {
            // 메모리 캐시에도 저장
            if memoryCache[roomId] == nil {
                memoryCache[roomId] = [:]
            }
            memoryCache[roomId]?[messageId] = content
            return content
        }
        
        return nil
    }
    
    /// 특정 채팅방의 모든 복호화된 메시지 조회
    func getAll(roomId: String) async -> [String: String] {
        // 메모리 캐시에 있으면 반환
        if let cached = memoryCache[roomId], !cached.isEmpty {
            return cached
        }
        
        // 디스크에서 전체 로드
        let messages = await getAllFromDisk(roomId: roomId)
        if !messages.isEmpty {
            memoryCache[roomId] = messages
        }
        return messages
    }
    
    /// 특정 메시지의 캐시 삭제
    func remove(roomId: String, messageId: String) async {
        // 메모리 캐시에서 삭제
        memoryCache[roomId]?.removeValue(forKey: messageId)
        
        // 디스크에서 삭제
        let roomDirectory = cacheDirectory.appendingPathComponent(roomId)
        let fileURL = roomDirectory.appendingPathComponent("\(messageId).txt")
        try? FileManager.default.removeItem(at: fileURL)
    }
    
    /// 특정 채팅방의 모든 캐시 삭제
    func remove(roomId: String) async {
        memoryCache.removeValue(forKey: roomId)
        
        let roomDirectory = cacheDirectory.appendingPathComponent(roomId)
        try? FileManager.default.removeItem(at: roomDirectory)
    }
    
    /// 모든 캐시 삭제
    func clearAll() async {
        memoryCache.removeAll()
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Private Methods
    
    private func saveToDisk(roomId: String, messageId: String, decryptedContent: String) async -> Bool {
        let roomDirectory = cacheDirectory.appendingPathComponent(roomId)
        
        do {
            try FileManager.default.createDirectory(at: roomDirectory, withIntermediateDirectories: true)
        } catch {
            #if DEBUG
            print("❌ [DecryptedMessageCache] 디렉토리 생성 실패: \(error)")
            #endif
            return false
        }
        
        let fileURL = roomDirectory.appendingPathComponent("\(messageId).txt")
        
        do {
            try decryptedContent.write(to: fileURL, atomically: true, encoding: .utf8)
            return true
        } catch {
            #if DEBUG
            print("❌ [DecryptedMessageCache] 디스크 저장 실패: \(error)")
            #endif
            return false
        }
    }
    
    private func getFromDisk(roomId: String, messageId: String) async -> String? {
        let fileURL = cacheDirectory.appendingPathComponent(roomId).appendingPathComponent("\(messageId).txt")
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        
        do {
            return try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            #if DEBUG
            print("⚠️ [DecryptedMessageCache] 캐시 로드 실패 (손상된 캐시일 수 있음): \(roomId)/\(messageId)")
            print("   에러: \(error)")
            #endif
            
            // 손상된 캐시 파일 삭제
            try? FileManager.default.removeItem(at: fileURL)
            
            return nil
        }
    }
    
    private func getAllFromDisk(roomId: String) async -> [String: String] {
        let roomDirectory = cacheDirectory.appendingPathComponent(roomId)
        
        guard let files = try? FileManager.default.contentsOfDirectory(at: roomDirectory, includingPropertiesForKeys: nil) else {
            return [:]
        }
        
        var messages: [String: String] = [:]
        
        for fileURL in files where fileURL.pathExtension == "txt" {
            let messageId = fileURL.deletingPathExtension().lastPathComponent
            if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                messages[messageId] = content
            }
        }
        
        return messages
    }
}

