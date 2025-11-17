//
//  NetworkManager.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation
import Moya

class NetworkManager {
    static let shared = NetworkManager()
    
    // MARK: - Encoder & Decoder
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    
    // MARK: - Plugins
    private let plugins: [PluginType] = [
        AuthTokenPlugin()
    ]
    
    lazy var userProvider = MoyaProvider<UserAPI>(plugins: plugins)
    lazy var authProvider = MoyaProvider<AuthAPI>(plugins: plugins)
    lazy var deviceProvider = MoyaProvider<DeviceAPI>(plugins: plugins)
    lazy var chatProvider = MoyaProvider<ChatAPI>(plugins: plugins)
    lazy var friendProvider = MoyaProvider<FriendAPI>(plugins: plugins)
    lazy var fileUploadProvider = MoyaProvider<FileUploadAPI>(plugins: plugins)
    
    lazy var authService: AuthService = {
        AuthService(provider: authProvider, decoder: decoder)
    }()
    
    lazy var userService: UserService = {
        UserService(provider: userProvider, authService: authService, decoder: decoder)
    }()
    
    lazy var deviceService: DeviceService = {
        DeviceService(provider: deviceProvider, authService: authService, decoder: decoder)
    }()
    
    lazy var chatService: ChatService = {
        ChatService(provider: chatProvider, authService: authService, decoder: decoder)
    }()
    
    lazy var friendService: FriendService = {
        FriendService(provider: friendProvider, authService: authService, decoder: decoder)
    }()
    
    lazy var fileUploadService: FileUploadService = {
        FileUploadService(provider: fileUploadProvider, authService: authService, decoder: decoder)
    }()
    
    private init() {}
}
