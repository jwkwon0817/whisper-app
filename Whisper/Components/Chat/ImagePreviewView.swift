//
//  ImagePreviewView.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/27/25.
//

import SwiftUI

struct ImagePreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage
    let onSend: () -> Void
    
    @State private var isSending = false
    
    var body: some View {
        NavigationStack {
            VStack {
                Spacer()
                
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.8))
                
                Spacer()
            }
            .navigationTitle("이미지 전송")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        dismiss()
                    }
                    .disabled(isSending)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        isSending = true
                        onSend()
                    } label: {
                        if isSending {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("전송")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(isSending)
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

