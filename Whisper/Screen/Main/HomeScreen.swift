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
    @State private var showFriendRequests = false
    
    var body: some View {
        FriendListView()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showFriendRequests = true
                    }) {
                        ZStack {
                            Image(systemName: "person.2.badge.gearshape")
                            
                            if notificationManager.friendRequestCount > 0 {
                                Text("\(notificationManager.friendRequestCount)")
                                    .font(.caption2)
                                    .foregroundColor(.white)
                                    .padding(4)
                                    .background(Color.red)
                                    .clipShape(Circle())
                                    .offset(x: 8, y: -8)
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showFriendRequests) {
                FriendRequestListView()
                    .onAppear {
                        // 친구 요청 화면이 열릴 때 카운트 초기화
                        notificationManager.friendRequestCount = 0
                    }
            }
    }
}

#Preview {
    NavigationStack {
        HomeScreen()
            .environment(Router())
    }
}

