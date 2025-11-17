//
//  ChatAPI.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation
import Moya
internal import Alamofire

enum ChatAPI {
    case fetchChatRooms
    case createDirectChat(userId: String)
    case createGroupChat(name: String, description: String?, memberIds: [String])
    case fetchChatRoomDetail(roomId: String)
    case updateChatRoom(roomId: String, name: String?, description: String?)
    case fetchMessages(roomId: String, page: Int, pageSize: Int)
    case markMessagesAsRead(roomId: String, messageIds: [String])
    case leaveChatRoom(roomId: String)
    case addChatRoomMembers(roomId: String, userIds: [String])
    case removeChatRoomMember(roomId: String, userId: String)
    case sendGroupChatInvitation(roomId: String, userId: String)
    case fetchGroupChatInvitations
    case respondToGroupChatInvitation(invitationId: String, action: String)
    case fetchChatFolders
    case createChatFolder(name: String, color: String)
    case updateChatFolder(folderId: String, name: String?, color: String?)
    case deleteChatFolder(folderId: String)
    case addRoomToFolder(folderId: String, roomId: String)
    case removeRoomFromFolder(folderId: String, roomId: String)
}

extension ChatAPI: TargetType {
    var baseURL: URL {
        return URL(string: EnvironmentVariables.baseURL)!
    }

    var path: String {
        switch self {
        case .fetchChatRooms:
            return "/api/chat/rooms/"
        case .createDirectChat:
            return "/api/chat/rooms/direct/"
        case .createGroupChat:
            return "/api/chat/rooms/group/"
        case .fetchChatRoomDetail(let roomId), .updateChatRoom(let roomId, _, _):
            return "/api/chat/rooms/\(roomId)/"
        case .fetchMessages(let roomId, _, _):
            return "/api/chat/rooms/\(roomId)/messages/"
        case .markMessagesAsRead(let roomId, _):
            return "/api/chat/rooms/\(roomId)/messages/read/"
        case .leaveChatRoom(let roomId):
            return "/api/chat/rooms/\(roomId)/leave/"
        case .addChatRoomMembers(let roomId, _):
            return "/api/chat/rooms/\(roomId)/members/"
        case .removeChatRoomMember(let roomId, let userId):
            return "/api/chat/rooms/\(roomId)/members/\(userId)/"
        case .sendGroupChatInvitation(let roomId, _):
            return "/api/chat/rooms/\(roomId)/invitations/"
        case .fetchGroupChatInvitations:
            return "/api/chat/invitations/"
        case .respondToGroupChatInvitation(let invitationId, _):
            return "/api/chat/invitations/\(invitationId)/"
        case .fetchChatFolders:
            return "/api/chat/folders/"
        case .createChatFolder:
            return "/api/chat/folders/"
        case .updateChatFolder(let folderId, _, _), .deleteChatFolder(let folderId):
            return "/api/chat/folders/\(folderId)/"
        case .addRoomToFolder(let folderId, _):
            return "/api/chat/folders/\(folderId)/rooms/"
        case .removeRoomFromFolder(let folderId, let roomId):
            return "/api/chat/folders/\(folderId)/rooms/\(roomId)/"
        }
    }

    var method: Moya.Method {
        switch self {
        case .fetchChatRooms, .fetchChatRoomDetail, .fetchMessages, .fetchGroupChatInvitations, .fetchChatFolders:
            return .get
        case .createDirectChat, .createGroupChat, .markMessagesAsRead, .leaveChatRoom, .addChatRoomMembers, .sendGroupChatInvitation, .respondToGroupChatInvitation, .createChatFolder, .addRoomToFolder:
            return .post
        case .updateChatRoom, .updateChatFolder:
            return .patch
        case .removeChatRoomMember, .deleteChatFolder, .removeRoomFromFolder:
            return .delete
        }
    }

    var task: Task {
        switch self {
        case .fetchChatRooms, .fetchChatRoomDetail, .fetchGroupChatInvitations, .fetchChatFolders, .leaveChatRoom, .removeChatRoomMember, .deleteChatFolder, .removeRoomFromFolder:
            return .requestPlain
        case .createDirectChat(let userId):
            let request = CreateDirectChatRequest(userId: userId)
            return .requestJSONEncodable(request)
        case .createGroupChat(let name, let description, let memberIds):
            let request = CreateGroupChatRequest(name: name, description: description, memberIds: memberIds)
            return .requestJSONEncodable(request)
        case .updateChatRoom(_, let name, let description):
            var body: [String: Any] = [:]
            if let name = name {
                body["name"] = name
            }
            if let description = description {
                body["description"] = description
            }
            return .requestParameters(parameters: body, encoding: JSONEncoding.default)
        case .fetchMessages(_, let page, let pageSize):
            return .requestParameters(
                parameters: [
                    "page": page,
                    "page_size": pageSize
                ],
                encoding: URLEncoding.queryString
            )
        case .markMessagesAsRead(_, let messageIds):
            let request = MarkMessagesReadRequest(messageIds: messageIds)
            return .requestJSONEncodable(request)
        case .addChatRoomMembers(_, let userIds):
            let body: [String: Any] = ["user_ids": userIds]
            return .requestParameters(parameters: body, encoding: JSONEncoding.default)
        case .sendGroupChatInvitation(_, let userId):
            let body: [String: Any] = ["user_id": userId]
            return .requestParameters(parameters: body, encoding: JSONEncoding.default)
        case .respondToGroupChatInvitation(_, let action):
            let body: [String: Any] = ["action": action]
            return .requestParameters(parameters: body, encoding: JSONEncoding.default)
        case .createChatFolder(let name, let color):
            let body: [String: Any] = ["name": name, "color": color]
            return .requestParameters(parameters: body, encoding: JSONEncoding.default)
        case .updateChatFolder(_, let name, let color):
            var body: [String: Any] = [:]
            if let name = name {
                body["name"] = name
            }
            if let color = color {
                body["color"] = color
            }
            return .requestParameters(parameters: body, encoding: JSONEncoding.default)
        case .addRoomToFolder(_, let roomId):
            let body: [String: Any] = ["room_id": roomId]
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
