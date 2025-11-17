//
//  CreateScreen.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import SwiftUI

struct CreateScreen: View {
    @State private var title = ""
    @State private var content = ""
    
    var body: some View {
        Form {
            Section("게시물 작성") {
                TextField("제목", text: $title)
                
                TextField("내용", text: $content, axis: .vertical)
                    .lineLimit(5...10)
            }
            
            Section {
                Button("작성하기") {
                    // 작성 로직
                }
                .disabled(title.isEmpty || content.isEmpty)
            }
        }
        .navigationTitle("Create")
    }
}

#Preview {
    NavigationStack {
        CreateScreen()
    }
}

