//
//  BaseService.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation
import Moya

class BaseService<Target: TargetType> {
    let provider: MoyaProvider<Target>
    let authService: AuthService
    let decoder: JSONDecoder
    
    init(provider: MoyaProvider<Target>, authService: AuthService, decoder: JSONDecoder) {
        self.provider = provider
        self.authService = authService
        self.decoder = decoder
    }
    
    func request<T: Decodable>(_ target: Target, as type: T.Type) async throws -> T {
        do {
            return try await performRequest(target, as: type)
        } catch {
            if let moyaError = error as? MoyaError,
               case .statusCode(let response) = moyaError,
               response.statusCode == 401 {
                
                do {
                    _ = try await authService.refresh()
                    return try await performRequest(target, as: type)
                } catch {
                    throw TokenError.refreshFailed
                }
            }
            throw error
        }
    }
    
    private func performRequest<T: Decodable>(_ target: Target, as type: T.Type) async throws -> T {
        return try await withCheckedThrowingContinuation { continuation in
            provider.request(target) { result in
                switch result {
                case .success(let response):
                    // 빈 응답 처리 (EmptyResponse인 경우)
                    if response.data.isEmpty {
                        if type == EmptyResponse.self {
                            continuation.resume(returning: EmptyResponse() as! T)
                            return
                        } else {
                            continuation.resume(throwing: NSError(domain: "BaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "서버가 빈 응답을 반환했습니다."]))
                            return
                        }
                    }
                    
                    do {
                        let decoded = try self.decoder.decode(type, from: response.data)
                        continuation.resume(returning: decoded)
                    } catch {
                        // 디코딩 오류 상세 정보 출력 (디버깅용)
                        #if DEBUG
                        if let jsonString = String(data: response.data, encoding: .utf8) {
                            print("디코딩 실패 - 응답 데이터: \(jsonString)")
                        }
                        print("디코딩 오류: \(error)")
                        #endif
                        continuation.resume(throwing: error)
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

