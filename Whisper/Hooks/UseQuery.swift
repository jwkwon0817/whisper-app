//
//  UseQuery.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import SwiftUI

@Observable
class UseQuery<T> {
    var data: T?
    var isLoading: Bool = false
    var error: String?
    
    var isSuccess: Bool { data != nil && error == nil }
    var isError: Bool { error != nil }
    
    private let fetchHandler: () async throws -> T
    
    init(autoFetch: Bool = false, fetch: @escaping () async throws -> T) {
        self.fetchHandler = fetch
        
        if autoFetch {
            Task {
                await self.fetch()
            }
        }
    }
    
    @MainActor
    func fetch() async {
        isLoading = true
        error = nil
        
        do {
            data = try await fetchHandler()
        } catch TokenError.refreshFailed {
            error = "로그인이 만료되었습니다. 다시 로그인해주세요."
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
    
    @MainActor
    func refetch() async {
        await fetch()
    }
    
    @MainActor
    func invalidate() async {
        data = nil
        error = nil
        await fetch()
    }
}

