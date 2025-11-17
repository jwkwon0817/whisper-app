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

            Text("URL: \(EnvironmentVariables.baseURL)")
            
            Spacer()
            
            VStack(spacing: 12) {
                TextField("전화번호", text: $phoneNumber)
                    .platformKeyboardType(.numberPad)
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
            // 화면이 나타날 때 에러 상태 초기화
            isError = false
            errorMessage = ""
        }
    }
    
    private func handleLogin() async throws {
        // 입력 검증
        guard !phoneNumber.isEmpty else {
            throw NSError(domain: "LoginError", code: -1, userInfo: [NSLocalizedDescriptionKey: "전화번호를 입력해주세요."])
        }
        
        guard !password.isEmpty else {
            throw NSError(domain: "LoginError", code: -1, userInfo: [NSLocalizedDescriptionKey: "비밀번호를 입력해주세요."])
        }
        
        // 1. 현재 기기 지문 생성
        let deviceFingerprint = DeviceManager.shared.generateDeviceFingerprint()
        print("기기 지문 생성: \(deviceFingerprint)")
        
        // 2. 로그인 요청 (기기 지문 포함)
        print("로그인 요청 시작...")
        let loginResponse: LoginResponse
        do {
            loginResponse = try await NetworkManager.shared.authService.login(
                phoneNumber: phoneNumber,
                password: password,
                deviceFingerprint: deviceFingerprint
            )
            print("로그인 성공: device_registered = \(loginResponse.deviceRegistered ?? false)")
        } catch {
            print("로그인 요청 실패: \(error)")
            print("에러 타입: \(type(of: error))")
            throw error
        }
        
        // 토큰 저장 확인
        guard KeychainHelper.getItem(forAccount: "accessToken") != nil else {
            print("토큰 저장 실패")
            throw NSError(domain: "LoginError", code: -1, userInfo: [NSLocalizedDescriptionKey: "로그인 토큰 저장 실패"])
        }
        print("토큰 저장 확인 완료")
        
        // 3. 기기 등록 여부 확인
        if loginResponse.deviceRegistered == true {
            // 기존 기기 - 로그인 완료
            print("기존 기기에서 로그인")
            DeviceManager.shared.saveDeviceFingerprint(deviceFingerprint)
            return
        }
        
        // 4. 새 기기 - 키 동기화 필요
        print("새 기기에서 로그인 - 키 동기화 필요")
        
        // 5. 기기 목록 조회 (토큰이 저장된 후 실행)
        let devices = try await NetworkManager.shared.deviceService.getDevices()
        
        if devices.isEmpty {
            // 첫 기기 - 회원가입을 통해 등록해야 함
            throw NSError(domain: "LoginError", code: -1, userInfo: [NSLocalizedDescriptionKey: "첫 기기는 회원가입을 통해 등록해주세요."])
        }
        
        // 6. 주 기기에서 암호화된 개인키 가져오기
        let primaryDevice = devices.first(where: { $0.isPrimary }) ?? devices[0]
        let keyResponse = try await NetworkManager.shared.deviceService.getDevicePrivateKey(deviceId: primaryDevice.id)
        
        // 7. 비밀번호로 개인키 복호화
        let decoder = JSONDecoder()
        guard let encryptedPrivateKeyJSON = keyResponse.encryptedPrivateKey.data(using: .utf8),
              let encryptedPrivateKey = try? decoder.decode(EncryptedPrivateKey.self, from: encryptedPrivateKeyJSON) else {
            throw NSError(domain: "LoginError", code: -1, userInfo: [NSLocalizedDescriptionKey: "암호화된 개인키 파싱 실패"])
        }
        
        let privateKey = try E2EEKeyManager.shared.decryptPrivateKey(
            encryptedPrivateKey: encryptedPrivateKey,
            password: password
        )
        
        // 8. 새 기기용으로 다시 암호화
        let newEncryptedPrivateKey = try E2EEKeyManager.shared.encryptPrivateKey(
            privateKey: privateKey,
            password: password
        )
        
        // 9. 로컬에 저장
        E2EEKeyManager.shared.saveEncryptedPrivateKey(newEncryptedPrivateKey)
        DeviceManager.shared.saveDeviceFingerprint(deviceFingerprint)
        
        // 10. 새 기기를 서버에 등록
        let deviceName = DeviceManager.shared.getDeviceName()
        let encoder = JSONEncoder()
        guard let encryptedPrivateKeyJSON = try? encoder.encode(newEncryptedPrivateKey),
              let encryptedPrivateKeyString = String(data: encryptedPrivateKeyJSON, encoding: .utf8) else {
            throw NSError(domain: "LoginError", code: -1, userInfo: [NSLocalizedDescriptionKey: "암호화된 개인키 직렬화 실패"])
        }
        
        _ = try await NetworkManager.shared.deviceService.registerDevice(
            deviceName: deviceName,
            deviceFingerprint: deviceFingerprint,
            encryptedPrivateKey: encryptedPrivateKeyString
        )
        
        print("새 기기 등록 및 키 동기화 완료!")
    }
}

#Preview {
    NavigationStack {
        LoginScreen()
            .environment(Router())
    }
}
