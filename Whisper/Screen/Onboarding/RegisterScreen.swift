//
//  RegisterScreen.swift
//  Whisper
//
//  Created by  jwkwon0817 on 11/17/25.
//

import SwiftUI
import PhotosUI

struct RegisterScreen: View {
    @Environment(\.dismiss) private var dismiss
    
    var onRegisterSuccess: (() -> Void)?
    
    @State private var phoneNumber = ""
    @State private var verificationCode = ""
    @State private var isCodeSent = false
    @State private var verifiedToken: String?
    @State private var name = ""
    @State private var password = ""
    @State private var passwordConfirm = ""
    @State private var isVerified = false
    @State private var selectedImageData: Data?
    @State private var selectedImageItem: PhotosPickerItem?
    
    @State private var currentStep = 1
    @State private var isLoading = false
    @State private var error: String?
    
    var body: some View {
        VStack(spacing: 24) {
            HStack(spacing: 8) {
                ForEach(1...3, id: \.self) { step in
                    Rectangle()
                        .fill(step <= currentStep ? Color.blue : Color.gray.opacity(0.3))
                        .frame(height: 4)
                        .animation(.easeInOut, value: currentStep)
                }
            }
            .padding(.horizontal)
            
            ScrollView {
                VStack(spacing: 32) {
                    if currentStep == 1 {
                        stepOneView
                    } else if currentStep == 2 {
                        stepTwoView
                    } else if currentStep == 3 {
                        stepThreeView
                    }
                }
                .padding()
            }
            
            if let error {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }
            
            Button {
                Task {
                    await handleNextStep()
                }
            } label: {
                if isLoading {
                    ProgressView()
                } else {
                    Text(currentStep == 3 ? "가입하기" : "다음")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
            .buttonStyle(.glass)
            .disabled(!canProceed || isLoading || phoneNumber.isEmpty)
        }
        .navigationTitle("회원가입")
        .platformNavigationBarTitleDisplayMode(.inline)
        .padding(.horizontal, 24)
        .hideKeyboardOnTap()
    }
    
    private var stepOneView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("전화번호 입력")
                .font(.title2)
                .bold()
            
            Text("인증번호를 받을 전화번호를 입력해주세요")
                .font(.subheadline)
                .foregroundColor(.gray)
            
            TextField("010-0000-0000", text: $phoneNumber)
                .platformKeyboardType(.phonePad)
                .padding(.vertical, 16)
                .padding(.horizontal, 20)
        }
    }
    
    private var stepTwoView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("인증번호 확인")
                .font(.title2)
                .bold()
            
            Text("\(phoneNumber)로 전송된 인증번호를 입력해주세요")
                .font(.subheadline)
                .foregroundColor(.gray)
            
            TextField("인증번호 6자리", text: $verificationCode)
                .platformKeyboardType(.numberPad)
                .padding(.vertical, 16)
                .padding(.horizontal, 20)
            
            Button {
                Task {
                    await resendCode()
                }
            } label: {
                Text("인증번호 재전송")
                    .font(.caption)
            }
        }
    }
    
    private var stepThreeView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("회원정보 입력")
                .font(.title2)
                .bold()
            
            Text("사용하실 이름과 비밀번호를 입력해주세요")
                .font(.subheadline)
                .foregroundColor(.gray)
            
            VStack(spacing: 12) {
                if let imageData = selectedImageData,
                   let platformImage = PlatformImage(data: imageData) {
                    platformImage.image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 100, height: 100)
                        .overlay(
                            Image(systemName: "camera.fill")
                                .foregroundColor(.gray)
                        )
                }
                
                PhotosPicker(selection: $selectedImageItem, matching: .images) {
                    Text(selectedImageData == nil ? "프로필 이미지 선택" : "이미지 변경")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            
            TextField("이름", text: $name)
                .padding(.vertical, 16)
                .padding(.horizontal, 20)
            
            SecureField("비밀번호", text: $password)
                .padding(.vertical, 16)
                .padding(.horizontal, 20)
            
            SecureField("비밀번호 확인", text: $passwordConfirm)
                .padding(.vertical, 16)
                .padding(.horizontal, 20)
            
            if !password.isEmpty && !passwordConfirm.isEmpty && password != passwordConfirm {
                Text("비밀번호가 일치하지 않습니다")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .onChange(of: selectedImageItem) { oldValue, newValue in
            Task {
                if let data = try? await newValue?.loadTransferable(type: Data.self) {
                    selectedImageData = data
                }
            }
        }
    }
    
    private var canProceed: Bool {
        switch currentStep {
        case 1:
            return !phoneNumber.isEmpty
        case 2:
            return verificationCode.count == 6
        case 3:
            return !name.isEmpty && !password.isEmpty && password == passwordConfirm
        default:
            return false
        }
    }
    
    private func handleNextStep() async {
        error = nil
        
        switch currentStep {
        case 1:
            await sendCode()
        case 2:
            await verifyCode()
        case 3:
            await register()
        default:
            break
        }
    }
    
    private func sendCode() async {
        isLoading = true
        
        do {
            try await NetworkManager.shared.authService.sendVerificationCode(phoneNumber: phoneNumber)
            isCodeSent = true
            currentStep = 2
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func resendCode() async {
        isLoading = true
        
        do {
            try await NetworkManager.shared.authService.sendVerificationCode(phoneNumber: phoneNumber)
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func verifyCode() async {
        isLoading = true
        
        do {
            let response = try await NetworkManager.shared.authService.verifyCode(phoneNumber: phoneNumber, code: verificationCode)
            verifiedToken = response.verifiedToken
            isVerified = true
            currentStep = 3
        } catch {
            self.error = "인증번호가 올바르지 않습니다"
        }
        
        isLoading = false
    }
    
    private func register() async {
        guard let verifiedToken = verifiedToken else {
            error = "인증이 완료되지 않았습니다"
            return
        }
        
        isLoading = true
        
        do {
            // 1. RSA-OAEP 키 페어 생성
            let (privateKey, publicKey) = try E2EEKeyManager.shared.generateRSAKeyPair()
            
            // 2. 공개키를 PEM 형식으로 내보내기
            let publicKeyPEM = try E2EEKeyManager.shared.exportPublicKeyToPEM(publicKey: publicKey)
            
            // 3. 개인키를 사용자 비밀번호로 암호화
            let encryptedPrivateKey = try E2EEKeyManager.shared.encryptPrivateKey(
                privateKey: privateKey,
                password: password
            )
            
            // 4. 암호화된 개인키를 JSON 문자열로 직렬화
            let encoder = JSONEncoder()
            let encryptedPrivateKeyJSON = try encoder.encode(encryptedPrivateKey)
            let encryptedPrivateKeyString = String(data: encryptedPrivateKeyJSON, encoding: .utf8)!
            
            // 5. 기기 정보 생성
            let deviceFingerprint = DeviceManager.shared.generateDeviceFingerprint()
            let deviceName = DeviceManager.shared.getDeviceName()
            
            // 6. 프로필 이미지를 Data로 변환 (JPEG 압축)
            var profileImageData: Data? = selectedImageData
            if let imageData = selectedImageData,
               let platformImage = PlatformImage(data: imageData) {
                profileImageData = platformImage.jpegData(quality: 0.8) ?? imageData
            }
            
            // 7. 서버에 회원가입 요청
            _ = try await NetworkManager.shared.authService.register(
                phoneNumber: phoneNumber,
                password: password,
                name: name,
                verifiedToken: verifiedToken,
                profileImage: profileImageData,
                publicKey: publicKeyPEM,
                encryptedPrivateKey: encryptedPrivateKeyString,
                deviceName: deviceName,
                deviceFingerprint: deviceFingerprint
            )
            
            // 8. 로컬에 암호화된 개인키 저장
            E2EEKeyManager.shared.saveEncryptedPrivateKey(encryptedPrivateKey)
            
            // 9. 기기 지문 저장
            DeviceManager.shared.saveDeviceFingerprint(deviceFingerprint)
            
            // 10. 비밀번호를 Keychain에 저장 (복호화용)
            KeychainHelper.setItem(token: password, forAccount: "user_password")
            
            // 11. 사용자 정보 가져오기 및 CurrentUser 업데이트
            do {
                let user = try await NetworkManager.shared.userService.fetchMe()
                CurrentUser.shared.update(user: user)
            } catch {
                print("⚠️ 사용자 정보 가져오기 실패: \(error)")
                // 회원가입은 성공했으므로 계속 진행
            }
            
            // 12. WebSocket 연결 (알림 수신용)
            NotificationManager.shared.connect()
            #if DEBUG
            print("✅ [RegisterScreen] 회원가입 성공 - WebSocket 연결")
            #endif
            
            dismiss()
            onRegisterSuccess?()
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
    
    // MARK: - Helper Methods
    // PlatformImage를 사용하도록 변경됨
}

#Preview {
    NavigationStack {
        RegisterScreen()
    }
}
