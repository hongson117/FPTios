//
//  FPTUpdateSheet.swift
//  FTVOS (Apple TV / tvOS)
//
//  Màn hình Tự Động Cập Nhật Luồng Trực Tiếp Mới Nhất Cho Tài Khoản Chính Chủ Qua Cloudflare MCP (fptstream):
//  - Không dùng cơ chế tự cập nhật file IPA (do cài qua chứng chỉ miễn phí).
//  - Tập trung 100% vào việc dò & cập nhật link trực tiếp (4K UHD 2160p50 / Full HD 1080p50) mới nhất của tài khoản chính chủ.
//  - Kết nối hai chiều với Cloudflare MCP (https://fptstream.hongson1812.workers.dev) để nhận tín hiệu từ app và trả về cấu hình luồng mới nhất tức thì.
//

import SwiftUI

public struct FPTUpdateSheet: View {
    @ObservedObject private var service = FPTService.shared
    @Environment(\.dismiss) private var dismiss

    public var onOpenChannel: ((FPTChannel) -> Void)?
    public var onOpenAuth: (() -> Void)?

    private let fptOrange = FPTTheme.accent

    public init(
        onOpenChannel: ((FPTChannel) -> Void)? = nil,
        onOpenAuth: (() -> Void)? = nil
    ) {
        self.onOpenChannel = onOpenChannel
        self.onOpenAuth = onOpenAuth
    }

    private var accountDisplayText: String {
        if !service.isAuthenticated {
            return "Chưa đăng nhập tài khoản chính chủ"
        }
        if !service.userPhone.isEmpty && !service.userId.isEmpty {
            return "SĐT: \(service.userPhone) • UID: \(service.userId)"
        } else if !service.userPhone.isEmpty {
            return "SĐT: \(service.userPhone)"
        }
        return "UID: \(service.userId)"
    }

    public var body: some View {
        ZStack {
            FPTGlassBackdrop()

            VStack(alignment: .leading, spacing: 24) {
                // Thanh tiêu đề trên cùng
                HStack(spacing: 16) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundColor(fptOrange)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("CẬP NHẬT LUỒNG TRỰC TIẾP MỚI NHẤT • TÀI KHOẢN CHÍNH CHỦ")
                            .font(.system(size: 27, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text(service.lastUpdateCheckStatus)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.green)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark.circle.fill")
                            Text("Đóng")
                        }
                        .font(.system(size: 18, weight: .bold))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.14))
                        .foregroundColor(.white)
                        .cornerRadius(14)
                    }
                    .buttonStyle(.plain)
                }

                // Nội dung 2 cột:
                // - Cột trái: Nút cập nhật link trực tiếp mới nhất cho tài khoản chính chủ & Thông số kết nối Cloudflare MCP (fptstream)
                // - Cột phải: Kết quả dò luồng trực tiếp thời gian thực của tài khoản chính chủ (Ngoại Hạng Anh 4K, Thể Thao Trực Tiếp, VTV1 HD, HBO HD)
                HStack(alignment: .top, spacing: 28) {
                    // CỘT TRÁI: ĐIỀU KHIỂN CẬP NHẬT LINK TRỰC TIẾP TÀI KHOẢN CHÍNH CHỦ QUA CLOUDFLARE MCP
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 10) {
                            Image(systemName: "bolt.horizontal.icloud.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.green)
                            Text("1. ĐỒNG BỘ LUỒNG TRỰC TIẾP TÀI KHOẢN CHÍNH CHỦ (MCP)")
                                .font(.system(size: 18, weight: .heavy))
                                .foregroundColor(.white)
                        }

                        Text("Bấm nút bên dưới để Apple TV dùng trực tiếp phiên đăng nhập Tài Khoản Chính Chủ của bạn dò link phát trực tiếp mới nhất (Ngoại Hạng Anh 4K UHD 50fps, Sự kiện Thể thao đang diễn ra, Truyền hình), gửi tín hiệu lên Cloudflare MCP (fptstream) và nhận về luồng tối ưu ngay lập tức.")
                            .font(.system(size: 15))
                            .foregroundColor(.white.opacity(0.84))
                            .lineSpacing(4)

                        // Khối thông số tài khoản chính chủ & máy chủ MCP fptstream
                        VStack(alignment: .leading, spacing: 10) {
                            configRow(
                                label: "Tài khoản chính chủ đang dùng:",
                                value: accountDisplayText,
                                valueColor: service.isAuthenticated ? .green : fptOrange
                            )
                            configRow(
                                label: "Máy chủ Cloudflare MCP:",
                                value: "fptstream.hongson1812.workers.dev",
                                valueColor: .cyan
                            )
                            configRow(
                                label: "Phiên bản cấu hình luồng MCP:",
                                value: "#\(service.remoteStreamConfig.configVersion)",
                                valueColor: .green
                            )
                            configRow(
                                label: "Thứ tự cổng Trực Tiếp (Live 4K/FHD):",
                                value: service.remoteStreamConfig.liveGatewayOrder.map { $0.uppercased() }.joined(separator: " → "),
                                valueColor: fptOrange
                            )
                            configRow(
                                label: "Khóa nét & Đa luồng âm thanh 4K:",
                                value: service.remoteStreamConfig.keepAllTopTierAudioVariants
                                    ? "2160p50 / 1080p50 (Stereo + Dolby 5.1)"
                                    : "Khóa biến thể băng thông cao nhất",
                                valueColor: .white
                            )
                            configRow(
                                label: "Đồng bộ MCP gần nhất:",
                                value: service.remoteStreamConfig.updatedAt,
                                valueColor: .gray
                            )
                        }
                        .padding(18)
                        .background(Color.black.opacity(0.34))
                        .cornerRadius(16)

                        // NÚT CHÍNH: CẬP NHẬT LINK TRỰC TIẾP MỚI NHẤT CHO TÀI KHOẢN CHÍNH CHỦ
                        Button {
                            Task {
                                await service.syncLiveStreamsWithMCP(manual: true)
                            }
                        } label: {
                            HStack(spacing: 14) {
                                if service.isCheckingUpdate {
                                    ProgressView()
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                                        .font(.system(size: 26, weight: .bold))
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(service.isCheckingUpdate
                                         ? "Đang dò link trực tiếp mới nhất & đồng bộ MCP..."
                                         : "Cập Nhật Link Trực Tiếp Mới Nhất (Tài Khoản Chính Chủ)")
                                        .font(.system(size: 18, weight: .black))
                                    Text("Dò luồng 4K/FHD trực tiếp từ tài khoản đang đăng nhập • Gửi tín hiệu & nhận cấu hình từ MCP fptstream")
                                        .font(.system(size: 13, weight: .semibold))
                                        .opacity(0.88)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 22)
                            .padding(.vertical, 16)
                            .frame(maxWidth: .infinity)
                            .background(fptOrange)
                            .foregroundColor(.black)
                            .cornerRadius(16)
                        }
                        .buttonStyle(.plain)
                        .disabled(service.isCheckingUpdate)

                        HStack(spacing: 14) {
                            // Nút bật/tắt ưu tiên 4K UHD
                            Button {
                                service.togglePrefer4K()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: service.prefer4K ? "4k.tv.fill" : "tv.fill")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(fptOrange)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(service.prefer4K ? "Ưu tiên 4K UHD 50fps" : "Chế độ Full HD 1080p50")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundColor(.white)
                                        Text("Khóa nét trực tiếp")
                                            .font(.system(size: 12))
                                            .foregroundColor(.gray)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity)
                                .background(Color.white.opacity(0.10))
                                .cornerRadius(14)
                            }
                            .buttonStyle(.plain)

                            if !service.isAuthenticated {
                                Button {
                                    dismiss()
                                    onOpenAuth?()
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "person.badge.key.fill")
                                            .font(.system(size: 20, weight: .bold))
                                            .foregroundColor(.green)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Đăng Nhập SĐT (OTP)")
                                                .font(.system(size: 16, weight: .bold))
                                                .foregroundColor(.white)
                                            Text("Tài khoản chính chủ")
                                                .font(.system(size: 12))
                                                .foregroundColor(.gray)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.green.opacity(0.20))
                                    .cornerRadius(14)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .fptGlassPanel(cornerRadius: 24)

                    // CỘT PHẢI: TRẠNG THÁI LINK TRỰC TIẾP MỚI NHẤT CỦA TÀI KHOẢN CHÍNH CHỦ
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 10) {
                            Image(systemName: "waveform.path.ecg.rectangle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(fptOrange)
                            Text("2. KẾT QUẢ DÒ LINK TRỰC TIẾP (TÀI KHOẢN CHÍNH CHỦ)")
                                .font(.system(size: 18, weight: .heavy))
                                .foregroundColor(.white)
                        }

                        if !service.isAuthenticated {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("🔒 Bạn chưa đăng nhập tài khoản FPT Play chính chủ trên Apple TV.")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(fptOrange)
                                Text("Để dò và mở khóa link trực tiếp Ngoại Hạng Anh 4K UHD (2160p50 HEVC) cũng như các sự kiện thể thao trực tiếp theo gói cước chính chủ, vui lòng đăng nhập bằng Số Điện Thoại + OTP trước.")
                                    .font(.system(size: 15))
                                    .foregroundColor(.white.opacity(0.85))
                                    .lineSpacing(4)
                            }
                            .padding(20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.34))
                            .cornerRadius(16)
                        } else if let report = service.lastLiveSyncReport, !report.probedItems.isEmpty {
                            ScrollView(.vertical, showsIndicators: false) {
                                VStack(spacing: 12) {
                                    ForEach(report.probedItems) { item in
                                        HStack(spacing: 14) {
                                            Circle()
                                                .fill(item.isReachable ? Color.green : Color.yellow)
                                                .frame(width: 12, height: 12)

                                            VStack(alignment: .leading, spacing: 4) {
                                                HStack(spacing: 8) {
                                                    Text(item.title)
                                                        .font(.system(size: 16, weight: .bold))
                                                        .foregroundColor(.white)
                                                        .lineLimit(1)
                                                    if item.has4K {
                                                        Text("4K UHD")
                                                            .font(.system(size: 11, weight: .black))
                                                            .padding(.horizontal, 7)
                                                            .padding(.vertical, 2)
                                                            .background(fptOrange)
                                                            .foregroundColor(.black)
                                                            .cornerRadius(5)
                                                    }
                                                }
                                                Text("\(item.statusText) • Mã kênh: \(item.channelId)")
                                                    .font(.system(size: 13, weight: .medium))
                                                    .foregroundColor(item.isReachable ? .green : .gray)
                                                    .lineLimit(1)
                                            }

                                            Spacer()

                                            if let ch = item.channel, let openCb = onOpenChannel {
                                                Button {
                                                    dismiss()
                                                    openCb(ch)
                                                } label: {
                                                    HStack(spacing: 6) {
                                                        Image(systemName: "play.fill")
                                                        Text("Phát Ngay")
                                                    }
                                                    .font(.system(size: 14, weight: .bold))
                                                    .padding(.horizontal, 14)
                                                    .padding(.vertical, 8)
                                                    .background(fptOrange)
                                                    .foregroundColor(.black)
                                                    .cornerRadius(10)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                        .padding(14)
                                        .background(Color.black.opacity(0.34))
                                        .cornerRadius(14)
                                    }
                                }
                            }
                            .frame(maxHeight: 330)
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Nhấn nút 'Cập Nhật Link Trực Tiếp Mới Nhất' ở cột bên trái để bắt đầu kiểm tra và nạp toàn bộ link trực tiếp 4K/FHD mới nhất cho tài khoản chính chủ của bạn.")
                                    .font(.system(size: 15))
                                    .foregroundColor(.white.opacity(0.85))
                                    .lineSpacing(4)
                            }
                            .padding(20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.34))
                            .cornerRadius(16)
                        }

                        Spacer(minLength: 4)

                        // Khối ghi chú từ Cloudflare MCP
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Ghi chú điều phối luồng từ Cloudflare MCP (fptstream):")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.gray)
                            Text(service.remoteStreamConfig.updateNotes)
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.9))
                                .lineLimit(3)
                                .lineSpacing(3)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(14)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .fptGlassPanel(cornerRadius: 24)
                }
            }
            .padding(44)
        }
        .task {
            if service.lastLiveSyncReport == nil {
                await service.syncLiveStreamsWithMCP(manual: false)
            }
        }
    }

    @ViewBuilder
    private func configRow(label: String, value: String, valueColor: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(valueColor)
                .lineLimit(1)
        }
    }
}
