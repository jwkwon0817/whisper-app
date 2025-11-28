//
//  OptimisticUpdateManager.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/24/25.
//

import Foundation
import Combine

@MainActor
class OptimisticUpdateManager {
    static let shared = OptimisticUpdateManager()
    
    private var updateQueue: [OptimisticUpdate] = []
    private var cancellables = Set<AnyCancellable>()
    
    private init() {}
    
    func execute<T>(
        id: String,
        optimisticUpdate: @escaping () -> Void,
        apiCall: @escaping () async throws -> T,
        rollback: @escaping () -> Void
    ) async throws -> T {
        optimisticUpdate()
        
        let update = OptimisticUpdate(
            id: id,
            rollback: rollback
        )
        updateQueue.append(update)
        
        do {
            let result = try await apiCall()
            
            updateQueue.removeAll { $0.id == id }
            
            return result
        } catch {
            rollback()
            updateQueue.removeAll { $0.id == id }
            throw error
        }
    }
    
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

private struct OptimisticUpdate {
    let id: String
    let rollback: () -> Void
}

protocol OptimisticUpdatable {
    associatedtype UpdateType
    
    func applyOptimisticUpdate(_ update: UpdateType)
    
    func rollback()
}

