//
//  CacheManager.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/24/25.
//

import Foundation

actor CacheManager {
    static let shared = CacheManager()
    
    private var memoryCache: [String: CachedItemWrapper] = [:]
    
    private let cacheDirectory: URL
    
    private init() {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDirectory = cacheDir.appendingPathComponent("WhisperCache")
        
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        Task {
            await cleanupExpiredCache()
        }
    }
    
    func set<T: Codable>(_ value: T, forKey key: String, ttl: TimeInterval = 300) async {
        let item = CachedItemWrapper(
            data: value,
            expiresAt: Date().addingTimeInterval(ttl)
        )
        
        memoryCache[key] = item
        
        await saveToDisk(value, key: key, expiresAt: item.expiresAt)
    }
    
    func get<T: Codable>(_ type: T.Type, forKey key: String) async -> T? {
        if let item = memoryCache[key], !item.isExpired {
            return item.data as? T
        }
        
        if let (data, expiresAt) = await getFromDisk(type, key: key), Date() < expiresAt {
            let item = CachedItemWrapper(data: data, expiresAt: expiresAt)
            memoryCache[key] = item
            return data
        }
        
        await remove(forKey: key)
        
        return nil
    }
    
    func remove(forKey key: String) async {
        memoryCache.removeValue(forKey: key)
        
        let fileURL = cacheDirectory.appendingPathComponent("\(key).cache")
        try? FileManager.default.removeItem(at: fileURL)
    }
    
    func remove(keysMatching pattern: String) async {
        memoryCache = memoryCache.filter { !$0.key.contains(pattern) }
        
        guard let files = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) else {
            return
        }
        
        for fileURL in files {
            if fileURL.lastPathComponent.contains(pattern) {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }
    
    func clearAll() async {
        memoryCache.removeAll()
        
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    private func saveToDisk<T: Codable>(_ value: T, key: String, expiresAt: Date) async {
        let fileURL = cacheDirectory.appendingPathComponent("\(key).cache")
        let metadataURL = cacheDirectory.appendingPathComponent("\(key).meta")
        
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(value)
            try data.write(to: fileURL)
            
            let metadata = CacheMetadata(expiresAt: expiresAt)
            let metadataData = try encoder.encode(metadata)
            try metadataData.write(to: metadataURL)
        } catch {
            print("Failed to save cache to disk: \(error)")
        }
    }
    
    private func getFromDisk<T: Codable>(_ type: T.Type, key: String) async -> (T, Date)? {
        let fileURL = cacheDirectory.appendingPathComponent("\(key).cache")
        let metadataURL = cacheDirectory.appendingPathComponent("\(key).meta")
        
        guard FileManager.default.fileExists(atPath: fileURL.path),
              FileManager.default.fileExists(atPath: metadataURL.path) else {
            return nil
        }
        
        do {
            let metadataData = try Data(contentsOf: metadataURL)
            let decoder = JSONDecoder()
            let metadata = try decoder.decode(CacheMetadata.self, from: metadataData)
            
            let data = try Data(contentsOf: fileURL)
            let value = try decoder.decode(type, from: data)
            
            return (value, metadata.expiresAt)
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            try? FileManager.default.removeItem(at: metadataURL)
            
            return nil
        }
    }
    
    private func cleanupExpiredCache() async {
        let now = Date()
        
        memoryCache = memoryCache.filter { !$0.value.isExpired(now: now) }
        
        guard let files = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) else {
            return
        }
        
        for fileURL in files {
            if fileURL.pathExtension == "meta" {
                let key = fileURL.deletingPathExtension().lastPathComponent
                if let metadataData = try? Data(contentsOf: fileURL),
                   let metadata = try? JSONDecoder().decode(CacheMetadata.self, from: metadataData),
                   metadata.expiresAt < now {
                    // 만료된 캐시 파일 삭제
                    try? FileManager.default.removeItem(at: fileURL)
                    try? FileManager.default.removeItem(at: cacheDirectory.appendingPathComponent("\(key).cache"))
                }
            }
        }
    }
}

private struct CachedItemWrapper {
    let data: Any
    let expiresAt: Date
    
    init<T>(data: T, expiresAt: Date) {
        self.data = data
        self.expiresAt = expiresAt
    }
    
    var isExpired: Bool {
        return Date() > expiresAt
    }
    
    func isExpired(now: Date) -> Bool {
        return now > expiresAt
    }
}

private struct CacheMetadata: Codable {
    let expiresAt: Date
}

