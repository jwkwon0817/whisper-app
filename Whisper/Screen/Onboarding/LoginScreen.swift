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
        
        // 비밀번호를 Keychain에 저장 (복호화용)
        // 보안 참고: 실제 프로덕션에서는 더 안전한 방법(예: 개인키를 메모리에만 보관)을 사용해야 함
        KeychainHelper.setItem(token: password, forAccount: "user_password")
        
        // 사용자 정보 가져오기 및 CurrentUser 업데이트
        do {
            let user = try await NetworkManager.shared.userService.fetchMe()
            CurrentUser.shared.update(user: user)
        } catch {
            print("⚠️ 사용자 정보 가져오기 실패: \(error)")
            // 로그인은 성공했으므로 계속 진행
        }
        
        // 3. 기기 등록 여부 확인 및 키 동기화
        if loginResponse.deviceRegistered == true {
            // 기존 기기 - 로컬에 키가 있는지 확인
            if E2EEKeyManager.shared.getEncryptedPrivateKey() != nil {
                print("기존 기기에서 로그인 - 키 존재함")
                DeviceManager.shared.saveDeviceFingerprint(deviceFingerprint)
                return
            }
            
            print("기존 기기에서 로그인 - 키 없음 (복구 시도)")
            
            // 키가 없으면 서버에서 가져와야 함
            // deviceId가 있으면 그것을 사용, 없으면 현재 기기 지문으로 찾기
            let targetDeviceId: String
            if let responseDeviceId = loginResponse.deviceId {
                targetDeviceId = responseDeviceId
            } else {
                // deviceId가 없으면 목록에서 찾기
                let devices = try await NetworkManager.shared.deviceService.getDevices()
                if let device = devices.first(where: { $0.deviceFingerprint == deviceFingerprint }) {
                    targetDeviceId = device.id
                } else {
                    // 기기를 찾을 수 없음 - 재등록 필요?
                    // 하지만 deviceRegistered가 true이므로 이상한 상황
                    // 일단 주 기기에서 가져오기 시도
                    print("기기 ID를 찾을 수 없어 주 기기에서 키 가져오기 시도")
                    if let primaryDevice = devices.first(where: { $0.isPrimary }) {
                        targetDeviceId = primaryDevice.id
                    } else if let firstDevice = devices.first {
                        targetDeviceId = firstDevice.id
                    } else {
                        throw NSError(domain: "LoginError", code: -1, userInfo: [NSLocalizedDescriptionKey: "등록된 기기 정보를 찾을 수 없습니다."])
                    }
                }
            }
            
            // 키 가져오기 및 복구
            try await recoverPrivateKey(deviceId: targetDeviceId, password: password)
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
        // 주 기기가 없으면 아무 기기나 사용
        let primaryDevice = devices.first(where: { $0.isPrimary }) ?? devices[0]
        
        // 키 가져오기 및 복구 (새 기기 등록 포함)
        try await registerNewDevice(sourceDeviceId: primaryDevice.id, password: password, deviceFingerprint: deviceFingerprint)
        
        print("새 기기 등록 및 키 동기화 완료!")
    }
    
    // 개인키 복구 (기존 기기)
    private func recoverPrivateKey(deviceId: String, password: String) async throws {
        print("개인키 복구 시도 - Device ID: \(deviceId)")
        
        let keyResponse = try await NetworkManager.shared.deviceService.getDevicePrivateKey(deviceId: deviceId)
        
        // 비밀번호로 개인키 복호화 확인
        let decoder = JSONDecoder()
        guard let encryptedPrivateKeyJSON = keyResponse.encryptedPrivateKey.data(using: .utf8),
              let encryptedPrivateKey = try? decoder.decode(EncryptedPrivateKey.self, from: encryptedPrivateKeyJSON)
        else {
            throw NSError(domain: "LoginError", code: -1, userInfo: [NSLocalizedDescriptionKey: "암호화된 개인키 파싱 실패"])
        }
        
        // 복호화 테스트 (비밀번호가 맞는지 확인)
        _ = try E2EEKeyManager.shared.decryptPrivateKey(
            encryptedPrivateKey: encryptedPrivateKey,
            password: password
        )
        
        // 로컬에 저장
        E2EEKeyManager.shared.saveEncryptedPrivateKey(encryptedPrivateKey)
        print("개인키 복구 완료")
    }
    
    // 새 기기 등록
    private func registerNewDevice(sourceDeviceId: String, password: String, deviceFingerprint: String) async throws {
        print("새 기기 등록 시도 - Source Device ID: \(sourceDeviceId)")
        
        let keyResponse = try await NetworkManager.shared.deviceService.getDevicePrivateKey(deviceId: sourceDeviceId)
        
        // 비밀번호로 개인키 복호화
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
        
        // 새 기기용으로 다시 암호화
        let newEncryptedPrivateKey = try E2EEKeyManager.shared.encryptPrivateKey(
            privateKey: privateKey,
            password: password
        )
        
        // 로컬에 저장
        E2EEKeyManager.shared.saveEncryptedPrivateKey(newEncryptedPrivateKey)
        
        // 새 기기를 서버에 등록
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
