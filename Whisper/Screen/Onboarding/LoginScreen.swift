//
//  LoginScreen.swift
//  Whisper
//
//  Created by  jwkwon0817 on 11/17/25.
//

import SwiftUI

struct LoginScreen: View {
    @Environment(Router.self) private var router
    
    @State private var phoneNumber: String = ""
    @State private var password: String = ""
    @State private var isLoading: Bool = false
    @State private var isError: Bool = false
    @State private var errorMessage: String = ""
    
    var onLoginSuccess: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 36) {
            Spacer()
            
            Text("로그인")
                .font(.largeTitle)
                .bold()

            Spacer()
            
            VStack(spacing: 12) {
                TextField("전화번호", text: $phoneNumber)
                #if os(iOS)
                    .keyboardType(.numberPad)
                #endif
                    .padding(.vertical, 16)
                    .padding(.horizontal, 20)
                
                SecureField("비밀번호", text: $password)
                    .padding(.vertical, 16)
                    .padding(.horizontal, 20)
            }
            
            VStack(spacing: 8) {
                Button(action: {
                    isLoading = true
                    isError = false
                    errorMessage = ""
                    
                    Task {
                        do {
                            try await handleLogin()
                            
                            // 로그인 성공 시 WebSocket 연결
                            NotificationManager.shared.connect()
                            #if DEBUG
                                print("✅ [LoginScreen] 로그인 성공 - WebSocket 연결")
                            #endif
                            
                            isError = false
                            isLoading = false
                            
                            onLoginSuccess?()
                        } catch {
                            isError = true
                            errorMessage = error.localizedDescription
                            print("로그인 실패: \(error)")
                            isLoading = false
                        }
                    }
                }) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Text("로그인")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                }
                .buttonStyle(.glass)
                
                if isError {
                    VStack(spacing: 4) {
                        Text("로그인에 실패했습니다.")
                            .foregroundColor(.red)
                            .font(.footnote)
                        if !errorMessage.isEmpty {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .font(.caption)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
            }
            
            Button {
                router.navigate(to: .register)
            } label: {
                Text("계정이 없으신가요? 회원가입")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            .padding(.top)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .hideKeyboardOnTap()
        .onAppear {
            isError = false
            errorMessage = ""
        }
    }
    
    private func handleLogin() async throws {
        guard !phoneNumber.isEmpty else {
            throw NSError(domain: "LoginError", code: -1, userInfo: [NSLocalizedDescriptionKey: "전화번호를 입력해주세요."])
        }
        
        guard !password.isEmpty else {
            throw NSError(domain: "LoginError", code: -1, userInfo: [NSLocalizedDescriptionKey: "비밀번호를 입력해주세요."])
        }
        
        let deviceFingerprint = DeviceManager.shared.generateDeviceFingerprint()
        
        let loginResponse: LoginResponse
        do {
            loginResponse = try await NetworkManager.shared.authService.login(
                phoneNumber: phoneNumber,
                password: password,
                deviceFingerprint: deviceFingerprint
            )
        } catch {
            throw error
        }
        
        guard KeychainHelper.getItem(forAccount: "accessToken") != nil else {
            throw NSError(domain: "LoginError", code: -1, userInfo: [NSLocalizedDescriptionKey: "로그인 토큰 저장 실패"])
        }
        print("토큰 저장 확인 완료")
        
        KeychainHelper.setItem(token: password, forAccount: "user_password")
        
        do {
            let user = try await NetworkManager.shared.userService.fetchMe()
            CurrentUser.shared.update(user: user)
        } catch {}
        
        if loginResponse.deviceRegistered == true {
            if E2EEKeyManager.shared.getEncryptedPrivateKey() != nil {
                DeviceManager.shared.saveDeviceFingerprint(deviceFingerprint)
                return
            }
            
            let targetDeviceId: String
            if let responseDeviceId = loginResponse.deviceId {
                targetDeviceId = responseDeviceId
            } else {
                let devices = try await NetworkManager.shared.deviceService.getDevices()
                if let device = devices.first(where: { $0.deviceFingerprint == deviceFingerprint }) {
                    targetDeviceId = device.id
                } else {
                    if let primaryDevice = devices.first(where: { $0.isPrimary }) {
                        targetDeviceId = primaryDevice.id
                    } else if let firstDevice = devices.first {
                        targetDeviceId = firstDevice.id
                    } else {
                        throw NSError(domain: "LoginError", code: -1, userInfo: [NSLocalizedDescriptionKey: "등록된 기기 정보를 찾을 수 없습니다."])
                    }
                }
            }
            
            try await recoverPrivateKey(deviceId: targetDeviceId, password: password)
            DeviceManager.shared.saveDeviceFingerprint(deviceFingerprint)
            return
        }
        
        let devices = try await NetworkManager.shared.deviceService.getDevices()
        
        if devices.isEmpty {
            throw NSError(domain: "LoginError", code: -1, userInfo: [NSLocalizedDescriptionKey: "첫 기기는 회원가입을 통해 등록해주세요."])
        }
        
        let primaryDevice = devices.first(where: { $0.isPrimary }) ?? devices[0]
        
        try await registerNewDevice(sourceDeviceId: primaryDevice.id, password: password, deviceFingerprint: deviceFingerprint)
    }
    
    private func recoverPrivateKey(deviceId: String, password: String) async throws {
        let keyResponse = try await NetworkManager.shared.deviceService.getDevicePrivateKey(deviceId: deviceId)
        
        let decoder = JSONDecoder()
        guard let encryptedPrivateKeyJSON = keyResponse.encryptedPrivateKey.data(using: .utf8),
              let encryptedPrivateKey = try? decoder.decode(EncryptedPrivateKey.self, from: encryptedPrivateKeyJSON)
        else {
            throw NSError(domain: "LoginError", code: -1, userInfo: [NSLocalizedDescriptionKey: "암호화된 개인키 파싱 실패"])
        }
        
        _ = try E2EEKeyManager.shared.decryptPrivateKey(
            encryptedPrivateKey: encryptedPrivateKey,
            password: password
        )
        
        E2EEKeyManager.shared.saveEncryptedPrivateKey(encryptedPrivateKey)
        print("개인키 복구 완료")
    }
    
    private func registerNewDevice(sourceDeviceId: String, password: String, deviceFingerprint: String) async throws {
        let keyResponse = try await NetworkManager.shared.deviceService.getDevicePrivateKey(deviceId: sourceDeviceId)
        
        let decoder = JSONDecoder()
        guard let encryptedPrivateKeyJSON = keyResponse.encryptedPrivateKey.data(using: .utf8),
              let encryptedPrivateKey = try? decoder.decode(EncryptedPrivateKey.self, from: encryptedPrivateKeyJSON)
        else {
            throw NSError(domain: "LoginError", code: -1, userInfo: [NSLocalizedDescriptionKey: "암호화된 개인키 파싱 실패"])
        }
        
        let privateKey = try E2EEKeyManager.shared.decryptPrivateKey(
            encryptedPrivateKey: encryptedPrivateKey,
            password: password
        )
        
        let newEncryptedPrivateKey = try E2EEKeyManager.shared.encryptPrivateKey(
            privateKey: privateKey,
            password: password
        )
        
        E2EEKeyManager.shared.saveEncryptedPrivateKey(newEncryptedPrivateKey)
        
        let deviceName = DeviceManager.shared.getDeviceName()
        let encoder = JSONEncoder()
        guard let encryptedPrivateKeyJSON = try? encoder.encode(newEncryptedPrivateKey),
              let encryptedPrivateKeyString = String(data: encryptedPrivateKeyJSON, encoding: .utf8)
        else {
            throw NSError(domain: "LoginError", code: -1, userInfo: [NSLocalizedDescriptionKey: "암호화된 개인키 직렬화 실패"])
        }
        
        _ = try await NetworkManager.shared.deviceService.registerDevice(
            deviceName: deviceName,
            deviceFingerprint: deviceFingerprint,
            encryptedPrivateKey: encryptedPrivateKeyString
        )
    }
}

#Preview {
    NavigationStack {
        LoginScreen()
            .environment(Router())
    }
}
