//
//  DeviceListView.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import SwiftUI

struct DeviceListView: View {
    @State private var devices: [Device] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    
    var body: some View {
        ZStack {
            if isLoading && devices.isEmpty {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("기기 목록을 불러오는 중...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else if devices.isEmpty {
                EmptyDeviceListView()
            } else {
                deviceList
            }
        }
        .navigationTitle("내 기기")
        .platformNavigationBarTitleDisplayMode(.large)
        .toolbar {
            PlatformToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    Task {
                        await loadDevices()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
        .task {
            await loadDevices()
        }
        .alert("오류", isPresented: $showError) {
            Button("확인", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "알 수 없는 오류가 발생했습니다.")
        }
    }
    
    private var deviceList: some View {
        List {
            ForEach(devices) { device in
                DeviceRowView(device: device)
            }
        }
        .refreshable {
            await loadDevices()
        }
    }
    
    private func loadDevices() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let fetchedDevices = try await NetworkManager.shared.deviceService.getDevices()
            devices = fetchedDevices.sorted { device1, device2 in
                // 주 기기 우선, 그 다음 마지막 활동 시간 순
                if device1.isPrimary != device2.isPrimary {
                    return device1.isPrimary
                }
                // lastActive가 nil인 경우 뒤로
                if device1.lastActive == nil && device2.lastActive != nil {
                    return false
                }
                if device1.lastActive != nil && device2.lastActive == nil {
                    return true
                }
                // 둘 다 nil이면 createdAt으로 정렬
                if device1.lastActive == nil && device2.lastActive == nil {
                    return device1.createdAt > device2.createdAt
                }
                return (device1.lastActive ?? "") > (device2.lastActive ?? "")
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        
        isLoading = false
    }
}

// MARK: - Device Row View

struct DeviceRowView: View {
    let device: Device
    
    var body: some View {
        HStack(spacing: 16) {
            // 기기 아이콘
            Image(systemName: deviceIcon)
                .font(.system(size: 32))
                .foregroundColor(deviceColor)
                .frame(width: 50, height: 50)
                .background(deviceColor.opacity(0.1))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(device.deviceName)
                        .font(.headline)
                    
                    // 주 기기 배지
                    if device.isPrimary {
                        Text("주 기기")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }
                    
                    // 현재 기기 배지
                    if device.isCurrentDevice {
                        Text("현재 기기")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.2))
                            .foregroundColor(.green)
                            .cornerRadius(4)
                    }
                }
                
                Text("마지막 활동: \(device.lastActiveFormatted)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("등록일: \(device.createdAtFormatted)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
    
    private var deviceIcon: String {
        let name = device.deviceName.lowercased()
        if name.contains("iphone") {
            return "iphone"
        } else if name.contains("ipad") {
            return "ipad"
        } else if name.contains("mac") || name.contains("macbook") {
            return "macbook"
        } else {
            return "iphone"
        }
    }
    
    private var deviceColor: Color {
        let name = device.deviceName.lowercased()
        if name.contains("iphone") {
            return .blue
        } else if name.contains("ipad") {
            return .purple
        } else if name.contains("mac") || name.contains("macbook") {
            return .gray
        } else {
            return .primary
        }
    }
}

// MARK: - Empty Device List View

struct EmptyDeviceListView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "iphone")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            Text("등록된 기기가 없습니다")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("첫 기기는 회원가입 시 자동으로 등록됩니다.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

#Preview {
    NavigationStack {
        DeviceListView()
    }
}

