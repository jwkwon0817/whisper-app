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
    
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    
    private var urlSessionConfiguration: URLSessionConfiguration {
        let config = URLSessionConfiguration.default
        #if os(macOS)
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        config.allowsCellularAccess = true
        #endif
        return config
    }
    
    private let plugins: [PluginType] = [
        AuthTokenPlugin(),
        NetworkLoggerPlugin()
    ]
    
    private func createProvider<T: TargetType>() -> MoyaProvider<T> {
        MoyaProvider<T>(
            session: Session(configuration: urlSessionConfiguration),
            plugins: plugins
        )
    }
    
    lazy var userProvider: MoyaProvider<UserAPI> = createProvider()
    lazy var authProvider: MoyaProvider<AuthAPI> = createProvider()
    lazy var deviceProvider: MoyaProvider<DeviceAPI> = createProvider()
    lazy var chatProvider: MoyaProvider<ChatAPI> = createProvider()
    lazy var friendProvider: MoyaProvider<FriendAPI> = createProvider()
    lazy var fileUploadProvider: MoyaProvider<FileUploadAPI> = createProvider()
    
    lazy var authService: AuthService = .init(provider: authProvider, decoder: decoder)
    
    lazy var userService: UserService = .init(provider: userProvider, authService: authService, decoder: decoder)
    
    lazy var deviceService: DeviceService = .init(provider: deviceProvider, authService: authService, decoder: decoder)
    
    lazy var chatService: ChatService = .init(provider: chatProvider, authService: authService, decoder: decoder)
    
    lazy var friendService: FriendService = .init(provider: friendProvider, authService: authService, decoder: decoder)
    
    lazy var fileUploadService: FileUploadService = .init(provider: fileUploadProvider, authService: authService, decoder: decoder)
    
    private init() {}
}
