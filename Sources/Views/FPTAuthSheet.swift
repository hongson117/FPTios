//
//  FPTAuthSheet.swift
//  FTVOS (Apple TV / tvOS)
//
//  Đăng nhập trực tiếp bằng Số Điện Thoại + OTP, Đăng Xuất & Chuyển Đổi Tài Khoản ngay trên Apple TV
//

import SwiftUI

public struct FPTAuthSheet: View {
    @ObservedObject private var service = FPTService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var phoneInput: String = ""
    @State private var otpInput: String = ""
    @State private var selectedTab: Int = 0

    private let fptOrange = FPTTheme.accent

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack(spacing: 16) {
                    Image("FPTLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 46)

                    Text("FTVOS")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(FPTTheme.accentGradient)

                    Text("• ĐĂNG NHẬP & QUẢN LÝ TÀI KHOẢN TRÊN APPLE TV")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)

                    Spacer()

                    Button("Đóng") {
                        dismiss()
                    }
                }

                // Status & Sign Out Banner
                HStack(spacing: 18) {
                    Circle()
                        .fill(service.isAuthenticated ? Color.green : fptOrange)
                        .frame(width: 18, height: 18)

                    VStack(alignment: .leading, spacing: 4) {
                        if service.isAuthenticated {
                            let accountDisplay = service.userPhone.isEmpty
                                ? "UID: \(service.userId)"
                                : "SĐT: \(service.userPhone) • UID: \(service.userId)"
                            Text("ĐANG ĐĂNG NHẬP TÀI KHOẢN FPT PLAY (\(accountDisplay))")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.green)
                        } else {
                            Text("CHƯA ĐĂNG NHẬP TÀI KHOẢN — SẴN SÀNG ĐĂNG NHẬP SĐT + OTP MỚI")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(fptOrange)
                        }

                        Text(service.phoneAuth?.message ?? service.statusMessage)
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.9))
                    }

                    Spacer()

                    if service.isAuthenticated || !service.userId.isEmpty {
                        Button {
                            Task {
                                await service.logoutAccount()
                                phoneInput = ""
                                otpInput = ""
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                Text("Đăng Xuất / Đổi Tài Khoản Khác")
                                    .font(.system(size: 17, weight: .bold))
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Color.red.opacity(0.85)))
                            .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        .disabled(service.isBusyAuth)
                    }
                }
                .padding(20)
                .fptGlassPanel(cornerRadius: 22)

                // Tab Buttons
                HStack(spacing: 18) {
                    tabButton(title: "📱 Đăng Nhập / Đổi Tài Khoản SĐT (OTP)", index: 0)
                    tabButton(title: "📋 Nhật Ký Hệ Thống & FairPlay", index: 1)
                }

                // Content
                ScrollView {
                    if selectedTab == 0 {
                        otpSection
                    } else {
                        logSection
                    }
                }
            }
            .padding(44)
            .background(FPTGlassBackdrop())
        }
    }

    private func tabButton(title: String, index: Int) -> some View {
        Button {
            selectedTab = index
        } label: {
            Text(title)
                .font(.system(size: 19, weight: .bold))
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(
                            selectedTab == index
                                ? AnyShapeStyle(FPTTheme.accentGradient)
                                : AnyShapeStyle(.ultraThinMaterial)
                        )
                )
                .foregroundColor(.white)
        }
        .buttonStyle(.plain)
    }

    private var otpSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            if service.isAuthenticated {
                HStack(spacing: 14) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(fptOrange)
                    Text("Bạn có thể bấm 'Đăng Xuất / Đổi Tài Khoản Khác' ở góc phải phía trên, hoặc nhập trực tiếp số điện thoại mới vào Bước 1 bên dưới — ứng dụng sẽ tự động đăng xuất tài khoản cũ và gửi mã OTP cho số mới.")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.9))
                }
                .padding(16)
                .background(fptOrange.opacity(0.14))
                .cornerRadius(12)
            }

            // Bước 1: Nhập SĐT
            VStack(alignment: .leading, spacing: 12) {
                Text("Bước 1: Nhập số điện thoại đăng ký FPT Play (10 chữ số)")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(fptOrange)

                HStack(spacing: 18) {
                    TextField("Nhập số điện thoại 10 số (VD: 09xxxxxxxx)", text: $phoneInput)
                        .frame(width: 540)

                    Button {
                        Task {
                            otpInput = ""
                            await service.startPhoneOTP(phone: phoneInput)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if service.isBusyAuth {
                                ProgressView()
                            }
                            Text("Gửi Mã OTP")
                                .font(.system(size: 18, weight: .bold))
                        }
                    }
                    .disabled(service.isBusyAuth)
                }
            }

            // Bước 2: Nhập OTP
            VStack(alignment: .leading, spacing: 12) {
                Text("Bước 2: Nhập mã OTP nhận được trên điện thoại")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(fptOrange)

                HStack(spacing: 18) {
                    TextField("Nhập mã OTP (4 - 6 chữ số)", text: $otpInput)
                        .frame(width: 540)

                    Button {
                        Task {
                            await service.verifyPhoneOTP(otp: otpInput)
                            if service.isAuthenticated {
                                dismiss()
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if service.isBusyAuth {
                                ProgressView()
                            }
                            Text("Xác Nhận OTP")
                                .font(.system(size: 18, weight: .bold))
                        }
                    }
                    .disabled(service.isBusyAuth)

                    Button("Gửi Lại Mã OTP") {
                        Task {
                            await service.resendPhoneOTP()
                        }
                    }
                    .disabled(service.isBusyAuth)
                }
            }

            // Bước 3 (Nếu tài khoản đã đủ giới hạn 5 thiết bị - error_code == 7): Cho phép gỡ thiết bị cũ ngay trên Apple TV
            if let devices = service.phoneAuth?.activeDevices, !devices.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text("⚠️ Tài khoản đã đạt giới hạn 5 thiết bị trên FPT Play. Chọn 1 thiết bị cũ bên dưới để gỡ và hoàn tất đăng nhập:")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.yellow)

                    ForEach(devices) { dev in
                        HStack(spacing: 16) {
                            Image(systemName: "tv.and.mediabox")
                                .font(.system(size: 24))
                                .foregroundColor(fptOrange)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(dev.deviceName)
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                                Text("Loại: \(dev.deviceType) • Hoạt động: \(dev.accessTime)")
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray)
                            }

                            Spacer()

                            Button("Gỡ Thiết Bị Này & Đăng Nhập") {
                                Task {
                                    await service.removeDeviceAndLogin(deviceId: dev.id)
                                    if service.isAuthenticated {
                                        dismiss()
                                    }
                                }
                            }
                            .disabled(service.isBusyAuth)
                        }
                        .padding(16)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(12)
                    }
                }
                .padding(18)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(14)
            }

            // Quản lý tối đa 5 thiết bị đang đăng nhập trong tài khoản hiện tại
            if service.isAuthenticated {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("📺 Danh sách thiết bị đang đăng nhập (\(service.loggedInDevices.count)/5 thiết bị)")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(fptOrange)
                        Spacer()
                        Button("Làm Mới Danh Sách 5 Thiết Bị") {
                            Task {
                                await service.fetchLoggedInDevices()
                            }
                        }
                        .disabled(service.isBusyAuth)
                    }

                    if service.loggedInDevices.isEmpty {
                        Text("Bấm 'Làm Mới Danh Sách 5 Thiết Bị' để xem các thiết bị đang đăng nhập cùng tài khoản này.")
                            .font(.system(size: 15))
                            .foregroundColor(.gray)
                    } else {
                        ForEach(service.loggedInDevices) { dev in
                            HStack(spacing: 16) {
                                Image(systemName: "tv")
                                    .font(.system(size: 22))
                                    .foregroundColor(fptOrange)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(dev.deviceName)
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundColor(.white)
                                    Text("\(dev.deviceType) • \(dev.accessTime)")
                                        .font(.system(size: 14))
                                        .foregroundColor(.gray)
                                }

                                Spacer()

                                Button("Gỡ Thiết Bị") {
                                    Task {
                                        await service.deleteLoggedInDevice(deviceId: dev.id)
                                    }
                                }
                                .disabled(service.isBusyAuth)
                            }
                            .padding(14)
                            .background(Color.white.opacity(0.07))
                            .cornerRadius(10)
                        }
                    }
                }
                .padding(18)
                .background(Color.white.opacity(0.04))
                .cornerRadius(14)
                .task {
                    await service.fetchLoggedInDevices()
                }
            }
        }
        .padding(26)
        .background(Color.white.opacity(0.05))
        .cornerRadius(14)
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(service.logs.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .background(Color.black.opacity(0.5))
        .cornerRadius(14)
    }
}
