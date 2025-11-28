//
//  HomeScreen.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import SwiftUI

struct HomeScreen: View {
    @Environment(Router.self) private var router
    @StateObject private var notificationManager = NotificationManager.shared
    
    var body: some View {
        FriendListView()
    }
}

#Preview {
    NavigationStack {
        HomeScreen()
            .environment(Router())
    }
}

