//
//  Route.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import SwiftUI

enum Route: Hashable {
    case login
    case signup
    case register
    
    case home
    case profile
    case settings
    case deviceList
    
    case userDetail(userId: String)
}

extension Route {
    @ViewBuilder
    var destination: some View {
        switch self {
        case .login:
            LoginScreen()
        case .signup:
            Text("회원가입")
        case .register:
            RegisterScreen(onRegisterSuccess: {
            })
            
        case .home:
            HomeScreen()
        case .profile:
            ProfileScreen()
        case .settings:
            SettingsScreen()
        case .deviceList:
            DeviceListView()
            
        case .userDetail(let userId):
            Text("유저디테일 \(userId)")
        }
    }
}

