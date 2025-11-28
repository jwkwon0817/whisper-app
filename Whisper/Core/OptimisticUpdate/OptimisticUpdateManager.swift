//
//  OptimisticUpdateManager.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/24/25.
//

import Foundation
import Combine

// MARK: - Optimistic Update Manager
/// 낙관적 UI 업데이트를 관리하는 매니저
@MainActor
class OptimisticUpdateManager {
    static let shared = OptimisticUpdateManager()
    
    private var updateQueue: [OptimisticUpdate] = []
    private var cancellables = Set<AnyCancellable>()
    
    private init() {}
    
    /// 낙관적 업데이트 실행
    /// - Parameters:
    ///   - id: 업데이트를 식별할 고유 ID
    ///   - optimisticUpdate: 즉시 실행할 UI 업데이트 클로저
    ///   - apiCall: 실제 API 호출
    ///   - rollback: 실패 시 롤백할 클로저
    func execute<T>(
        id: String,
        optimisticUpdate: @escaping () -> Void,
        apiCall: @escaping () async throws -> T,
        rollback: @escaping () -> Void
    ) async throws -> T {
        // 즉시 UI 업데이트
        optimisticUpdate()
        
        // 업데이트 정보 저장
        let update = OptimisticUpdate(
            id: id,
            rollback: rollback
        )
        updateQueue.append(update)
        
        do {
            // API 호출
            let result = try await apiCall()
            
            // 성공 시 업데이트 제거
            updateQueue.removeAll { $0.id == id }
            
            return result
        } catch {
            // 실패 시 롤백
            rollback()
            updateQueue.removeAll { $0.id == id }
            throw error
        }
    }
    
    /// 낙관적 업데이트 실행 (결과를 사용하지 않는 경우)
    func execute(
        id: String,
        optimisticUpdate: @escaping () -> Void,
        apiCall: @escaping () async throws -> Void,
        rollback: @escaping () -> Void
    ) async throws {
        optimisticUpdate()
        
        let update = OptimisticUpdate(
            id: id,
            rollback: rollback
        )
        updateQueue.append(update)
        
        do {
            try await apiCall()
            updateQueue.removeAll { $0.id == id }
        } catch {
            rollback()
            updateQueue.removeAll { $0.id == id }
            throw error
        }
    }
}

// MARK: - Optimistic Update
private struct OptimisticUpdate {
    let id: String
    let rollback: () -> Void
}

// MARK: - Optimistic Update Protocol
/// 낙관적 업데이트를 지원하는 프로토콜
protocol OptimisticUpdatable {
    associatedtype UpdateType
    
    /// 낙관적 업데이트 적용
    func applyOptimisticUpdate(_ update: UpdateType)
    
    /// 롤백
    func rollback()
}

