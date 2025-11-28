//
//  DecryptedMessageCache.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/27/25.
//

import Foundation

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
        guard !decryptedContent.isEmpty else {
            return
        }
        
        if memoryCache[roomId] == nil {
            memoryCache[roomId] = [:]
        }
        memoryCache[roomId]?[messageId] = decryptedContent
        
        let success = await saveToDisk(roomId: roomId, messageId: messageId, decryptedContent: decryptedContent)
        
        if !success {
            memoryCache[roomId]?.removeValue(forKey: messageId)
        }
    }
    
    func get(roomId: String, messageId: String) async -> String? {
        if let cached = memoryCache[roomId]?[messageId] {
            return cached
        }
        
        if let content = await getFromDisk(roomId: roomId, messageId: messageId) {
            if memoryCache[roomId] == nil {
                memoryCache[roomId] = [:]
            }
            memoryCache[roomId]?[messageId] = content
            return content
        }
        
        return nil
    }
    
    func getAll(roomId: String) async -> [String: String] {
        if let cached = memoryCache[roomId], !cached.isEmpty {
            return cached
        }
        
        let messages = await getAllFromDisk(roomId: roomId)
        if !messages.isEmpty {
            memoryCache[roomId] = messages
        }
        return messages
    }
    
    func remove(roomId: String, messageId: String) async {
        memoryCache[roomId]?.removeValue(forKey: messageId)
        
        let roomDirectory = cacheDirectory.appendingPathComponent(roomId)
        let fileURL = roomDirectory.appendingPathComponent("\(messageId).txt")
        try? FileManager.default.removeItem(at: fileURL)
    }
    
    func remove(roomId: String) async {
        memoryCache.removeValue(forKey: roomId)
        
        let roomDirectory = cacheDirectory.appendingPathComponent(roomId)
        try? FileManager.default.removeItem(at: roomDirectory)
    }
    
    func clearAll() async {
        memoryCache.removeAll()
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    private func saveToDisk(roomId: String, messageId: String, decryptedContent: String) async -> Bool {
        let roomDirectory = cacheDirectory.appendingPathComponent(roomId)
        
        do {
            try FileManager.default.createDirectory(at: roomDirectory, withIntermediateDirectories: true)
        } catch {
            return false
        }
        
        let fileURL = roomDirectory.appendingPathComponent("\(messageId).txt")
        
        do {
            try decryptedContent.write(to: fileURL, atomically: true, encoding: .utf8)
            return true
        } catch {
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

