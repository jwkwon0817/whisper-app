//
//  SearchScreen.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import SwiftUI

struct SearchScreen: View {
    @State private var searchText = ""
    
    var body: some View {
        VStack {
            TextField("검색", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding()
            
            if searchText.isEmpty {
                Text("검색어를 입력하세요")
                    .foregroundColor(.gray)
            } else {
                List {
                    ForEach(0..<10) { i in
                        Text("검색 결과 \(i + 1)")
                    }
                }
            }
        }
        .navigationTitle("Search")
    }
}

#Preview {
    NavigationStack {
        SearchScreen()
    }
}

