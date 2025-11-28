//
//  NetworkManager.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation
import Moya
internal import Alamofire

class NetworkManager {
    static let shared = NetworkManager()
    
    // MARK: - Encoder & Decoder

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    
    // MARK: - URLSession Configuration

    /// macOS와 iOS 모두에서 작동하는 URLSession 설정
    private var urlSessionConfiguration: URLSessionConfiguration {
        let config = URLSessionConfiguration.default
        #if os(macOS)
        // macOS에서 네트워크 요청을 위한 설정
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        config.allowsCellularAccess = true
        #endif
        return config
    }
    
    // MARK: - Plugins

    private let plugins: [PluginType] = [
        AuthTokenPlugin(),
        NetworkLoggerPlugin()
    ]
    
    // MARK: - Moya Providers (macOS 호환)

    lazy var userProvider: MoyaProvider<UserAPI> = .init(
        session: Session(configuration: urlSessionConfiguration),
        plugins: plugins
    )
    
    lazy var authProvider: MoyaProvider<AuthAPI> = .init(
        session: Session(configuration: urlSessionConfiguration),
        plugins: plugins
    )
    
    lazy var deviceProvider: MoyaProvider<DeviceAPI> = .init(
        session: Session(configuration: urlSessionConfiguration),
        plugins: plugins
    )
    
    lazy var chatProvider: MoyaProvider<ChatAPI> = .init(
        session: Session(configuration: urlSessionConfiguration),
        plugins: plugins
    )
    
    lazy var friendProvider: MoyaProvider<FriendAPI> = .init(
        session: Session(configuration: urlSessionConfiguration),
        plugins: plugins
    )
    
    lazy var fileUploadProvider: MoyaProvider<FileUploadAPI> = .init(
        session: Session(configuration: urlSessionConfiguration),
        plugins: plugins
    )
    
    lazy var authService: AuthService = .init(provider: authProvider, decoder: decoder)
    
    lazy var userService: UserService = .init(provider: userProvider, authService: authService, decoder: decoder)
    
    lazy var deviceService: DeviceService = .init(provider: deviceProvider, authService: authService, decoder: decoder)
    
    lazy var chatService: ChatService = .init(provider: chatProvider, authService: authService, decoder: decoder)
    
    lazy var friendService: FriendService = .init(provider: friendProvider, authService: authService, decoder: decoder)
    
    lazy var fileUploadService: FileUploadService = .init(provider: fileUploadProvider, authService: authService, decoder: decoder)
    
    private init() {}
}
