//
//  CacheManager.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/24/25.
//

import Foundation

// MARK: - Cache Manager
/// 메모리 및 디스크 캐시를 관리하는 매니저
actor CacheManager {
    static let shared = CacheManager()
    
    // 메모리 캐시
    private var memoryCache: [String: CachedItemWrapper] = [:]
    
    // 디스크 캐시 디렉토리
    private let cacheDirectory: URL
    
    private init() {
        // 캐시 디렉토리 설정
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDirectory = cacheDir.appendingPathComponent("WhisperCache")
        
        // 디렉토리 생성
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        // 오래된 캐시 정리
        Task {
            await cleanupExpiredCache()
        }
    }
    
    // MARK: - Cache Operations
    
    /// 캐시 저장
    func set<T: Codable>(_ value: T, forKey key: String, ttl: TimeInterval = 300) async {
        let item = CachedItemWrapper(
            data: value,
            expiresAt: Date().addingTimeInterval(ttl)
        )
        
        // 메모리 캐시에 저장
        memoryCache[key] = item
        
        // 디스크 캐시에 저장
        await saveToDisk(value, key: key, expiresAt: item.expiresAt)
    }
    
    /// 캐시 조회
    func get<T: Codable>(_ type: T.Type, forKey key: String) async -> T? {
        // 메모리 캐시에서 먼저 확인
        if let item = memoryCache[key], !item.isExpired {
            return item.data as? T
        }
        
        // 디스크 캐시에서 확인
        if let (data, expiresAt) = await getFromDisk(type, key: key), Date() < expiresAt {
            // 메모리 캐시에도 저장
            let item = CachedItemWrapper(data: data, expiresAt: expiresAt)
            memoryCache[key] = item
            return data
        }
        
        // 캐시 미스 시 해당 키의 손상된 캐시 정리
        await remove(forKey: key)
        
        return nil
    }
    
    /// 캐시 삭제
    func remove(forKey key: String) async {
        // 메모리 캐시에서 삭제
        memoryCache.removeValue(forKey: key)
        
        // 디스크 캐시에서 삭제
        let fileURL = cacheDirectory.appendingPathComponent("\(key).cache")
        try? FileManager.default.removeItem(at: fileURL)
    }
    
    /// 특정 키 패턴으로 캐시 삭제
    func remove(keysMatching pattern: String) async {
        // 메모리 캐시에서 삭제
        memoryCache = memoryCache.filter { !$0.key.contains(pattern) }
        
        // 디스크 캐시에서 삭제
        guard let files = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) else {
            return
        }
        
        for fileURL in files {
            if fileURL.lastPathComponent.contains(pattern) {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }
    
    /// 모든 캐시 삭제
    func clearAll() async {
        // 메모리 캐시 클리어
        memoryCache.removeAll()
        
        // 디스크 캐시 클리어
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Private Methods
    
    private func saveToDisk<T: Codable>(_ value: T, key: String, expiresAt: Date) async {
        let fileURL = cacheDirectory.appendingPathComponent("\(key).cache")
        let metadataURL = cacheDirectory.appendingPathComponent("\(key).meta")
        
        do {
            // 데이터 저장
            let encoder = JSONEncoder()
            let data = try encoder.encode(value)
            try data.write(to: fileURL)
            
            // 만료 시간 저장
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
            // 메타데이터 읽기
            let metadataData = try Data(contentsOf: metadataURL)
            let decoder = JSONDecoder()
            let metadata = try decoder.decode(CacheMetadata.self, from: metadataData)
            
            // 데이터 읽기
            let data = try Data(contentsOf: fileURL)
            let value = try decoder.decode(type, from: data)
            
            return (value, metadata.expiresAt)
        } catch {
            #if DEBUG
            print("⚠️ [CacheManager] 캐시 로드 실패 (손상된 캐시일 수 있음): \(key)")
            print("   에러: \(error)")
            #endif
            
            // 손상된 캐시 파일 삭제
            try? FileManager.default.removeItem(at: fileURL)
            try? FileManager.default.removeItem(at: metadataURL)
            
            return nil
        }
    }
    
    private func cleanupExpiredCache() async {
        let now = Date()
        
        // 메모리 캐시에서 만료된 항목 제거
        memoryCache = memoryCache.filter { !$0.value.isExpired(now: now) }
        
        // 디스크 캐시에서 만료된 항목 제거
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

// MARK: - Cached Item Wrapper
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

// MARK: - Cache Metadata
private struct CacheMetadata: Codable {
    let expiresAt: Date
}

