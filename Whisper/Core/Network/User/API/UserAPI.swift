//
//  UserAPI.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation
import Moya
internal import Alamofire

enum UserAPI {
    case me
    case delete(confirmText: String, password: String)
    case getUserPublicKey(userId: String)
}

extension UserAPI: TargetType {
    var baseURL: URL {
        return URL(string: EnvironmentVariables.baseURL)!
    }
    
    var path: String {
        switch self {
        case .me:
            return "/api/me/"
        case .delete:
            return "/api/user/delete/"
        case .getUserPublicKey(let userId):
            return "/api/users/\(userId)/public-key/"
        }
    }
    
    var method: Moya.Method {
        switch self {
        case .me, .getUserPublicKey:
            return .get
        case .delete:
            return .delete
        }
    }
    
    var task: Task {
        switch self {
        case .me, .getUserPublicKey:
            return .requestPlain
        case .delete(let confirmText, let password):
            let request = DeleteAccountRequest(confirmText: confirmText, password: password)
            return .requestJSONEncodable(request)
        }
    }
    
    var headers: [String: String]? {
        return ["Content-Type": "application/json"]
    }
    
    var validationType: ValidationType {
        return .successCodes
    }
}
