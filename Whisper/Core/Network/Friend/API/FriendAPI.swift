//
//  FriendAPI.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation
import Moya
internal import Alamofire

enum FriendAPI {
    case sendFriendRequest(phoneNumber: String)
    case fetchFriends
    case fetchReceivedFriendRequests
    case respondToFriendRequest(friendId: String, action: String)
    case deleteFriend(friendId: String)
}

extension FriendAPI: TargetType {
    var baseURL: URL {
        return URL(string: EnvironmentVariables.baseURL)!
    }
    
    var path: String {
        switch self {
        case .sendFriendRequest:
            return "/api/friends/requests/"
        case .fetchFriends:
            return "/api/friends/"
        case .fetchReceivedFriendRequests:
            return "/api/friends/requests/received/"
        case .respondToFriendRequest(let friendId, _):
            return "/api/friends/requests/\(friendId)/"
        case .deleteFriend(let friendId):
            return "/api/friends/\(friendId)/"
        }
    }
    
    var method: Moya.Method {
        switch self {
        case .sendFriendRequest, .respondToFriendRequest:
            return .post
        case .fetchFriends, .fetchReceivedFriendRequests:
            return .get
        case .deleteFriend:
            return .delete
        }
    }
    
    var task: Task {
        switch self {
        case .sendFriendRequest(let phoneNumber):
            let body: [String: Any] = ["phone_number": phoneNumber]
            return .requestParameters(parameters: body, encoding: JSONEncoding.default)
        case .fetchFriends, .fetchReceivedFriendRequests, .deleteFriend:
            return .requestPlain
        case .respondToFriendRequest(_, let action):
            let body: [String: Any] = ["action": action]
            return .requestParameters(parameters: body, encoding: JSONEncoding.default)
        }
    }
    
    var headers: [String: String]? {
        return ["Content-Type": "application/json"]
    }
    
    var validationType: ValidationType {
        return .successCodes
    }
}

