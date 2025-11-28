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
    case updateMessage(roomId: String, messageId: String, content: String?, encryptedContent: String?, encryptedSessionKey: String?, selfEncryptedSessionKey: String?)
    case deleteMessage(roomId: String, messageId: String)
    case markMessagesAsRead(roomId: String, messageIds: [String])
    case leaveChatRoom(roomId: String)
    case addChatRoomMembers(roomId: String, userIds: [String])
    case removeChatRoomMember(roomId: String, userId: String)
    case sendGroupChatInvitation(roomId: String, userId: String)
    case fetchAllChatInvitations  // 통합 초대 목록 (1:1 + 그룹)
    case fetchDirectChatInvitations  // 1:1 초대 목록만
    case fetchGroupChatInvitations  // 그룹 초대 목록만
    case respondToDirectChatInvitation(invitationId: String, action: String)
    case respondToGroupChatInvitation(invitationId: String, action: String)
    case fetchChatFolders
    case createChatFolder(name: String, color: String, icon: String)
    case updateChatFolder(folderId: String, name: String?, color: String?, icon: String?)
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
        case .updateMessage(let roomId, let messageId, _, _, _, _), .deleteMessage(let roomId, let messageId):
            return "/api/chat/rooms/\(roomId)/messages/\(messageId)/"
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
        case .fetchAllChatInvitations:
            return "/api/chat/invitations/"
        case .fetchDirectChatInvitations:
            return "/api/chat/invitations/direct/"
        case .fetchGroupChatInvitations:
            return "/api/chat/invitations/group/"
        case .respondToDirectChatInvitation(let invitationId, _):
            return "/api/chat/invitations/direct/\(invitationId)/"
        case .respondToGroupChatInvitation(let invitationId, _):
            return "/api/chat/invitations/group/\(invitationId)/"
        case .fetchChatFolders:
            return "/api/chat/folders/"
        case .createChatFolder:
            return "/api/chat/folders/"
        case .updateChatFolder(let folderId, _, _, _), .deleteChatFolder(let folderId):
            return "/api/chat/folders/\(folderId)/"
        case .addRoomToFolder(let folderId, _):
            return "/api/chat/folders/\(folderId)/rooms/"
        case .removeRoomFromFolder(let folderId, let roomId):
            return "/api/chat/folders/\(folderId)/rooms/\(roomId)/"
        }
    }

    var method: Moya.Method {
        switch self {
        case .fetchChatRooms, .fetchChatRoomDetail, .fetchMessages, .fetchAllChatInvitations, .fetchDirectChatInvitations, .fetchGroupChatInvitations, .fetchChatFolders:
            return .get
        case .createDirectChat, .createGroupChat, .markMessagesAsRead, .leaveChatRoom, .addChatRoomMembers, .sendGroupChatInvitation, .respondToDirectChatInvitation, .respondToGroupChatInvitation, .createChatFolder, .addRoomToFolder:
            return .post
        case .updateChatRoom, .updateChatFolder, .updateMessage:
            return .patch
        case .removeChatRoomMember, .deleteChatFolder, .removeRoomFromFolder, .deleteMessage:
            return .delete
        }
    }

    var task: Task {
        switch self {
        case .fetchChatRooms, .fetchChatRoomDetail, .fetchAllChatInvitations, .fetchDirectChatInvitations, .fetchGroupChatInvitations, .fetchChatFolders, .leaveChatRoom, .removeChatRoomMember, .deleteChatFolder, .removeRoomFromFolder:
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
        case .updateMessage(_, _, let content, let encryptedContent, let encryptedSessionKey, let selfEncryptedSessionKey):
            var body: [String: Any] = [:]
            if let content = content {
                body["content"] = content
            }
            if let encryptedContent = encryptedContent {
                body["encrypted_content"] = encryptedContent
            }
            if let encryptedSessionKey = encryptedSessionKey {
                body["encrypted_session_key"] = encryptedSessionKey
            }
            if let selfEncryptedSessionKey = selfEncryptedSessionKey {
                body["self_encrypted_session_key"] = selfEncryptedSessionKey
            }
            return .requestParameters(parameters: body, encoding: JSONEncoding.default)
        case .deleteMessage:
            return .requestPlain
        case .markMessagesAsRead(_, let messageIds):
            let request = MarkMessagesReadRequest(messageIds: messageIds)
            return .requestJSONEncodable(request)
        case .addChatRoomMembers(_, let userIds):
            let body: [String: Any] = ["user_ids": userIds]
            return .requestParameters(parameters: body, encoding: JSONEncoding.default)
        case .sendGroupChatInvitation(_, let userId):
            let body: [String: Any] = ["user_id": userId]
            return .requestParameters(parameters: body, encoding: JSONEncoding.default)
        case .respondToDirectChatInvitation(_, let action), .respondToGroupChatInvitation(_, let action):
            let body: [String: Any] = ["action": action]
            return .requestParameters(parameters: body, encoding: JSONEncoding.default)
        case .createChatFolder(let name, let color, let icon):
            let body: [String: Any] = ["name": name, "color": color, "icon": icon]
            return .requestParameters(parameters: body, encoding: JSONEncoding.default)
        case .updateChatFolder(_, let name, let color, let icon):
            var body: [String: Any] = [:]
            if let name = name {
                body["name"] = name
            }
            if let color = color {
                body["color"] = color
            }
            if let icon = icon {
                body["icon"] = icon
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
