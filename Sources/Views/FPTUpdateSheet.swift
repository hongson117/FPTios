//
//  FPTUpdateSheet.swift
//  FTVOS (Apple TV / tvOS)
//
//  Màn hình Cập Nhật Tự Động & Đồng Bộ Cơ Chế Đổi Luồng Trực Tiếp Qua GitHub (hongson117/FPTios):
//  1. Đồng bộ nóng (Hot-Update) file remote_stream_config.json từ GitHub để đổi cổng API / ưu tiên luồng 4K ngay lập tức mà KHÔNG cần cài lại IPA.
//  2. Tự động kiểm tra bản phát hành FTVOS.ipa mới nhất trên GitHub Releases kèm mã QR tải trực tiếp link cố định (/releases/latest/download/FTVOS.ipa).
//

import SwiftUI
import CoreImage

public struct FPTUpdateSheet: View {
    @ObservedObject private var service = FPTService.shared
    @Environment(\.dismiss) private var dismiss

    private let fptOrange = FPTTheme.accent
    private let ciContext = CIContext()

    public init() {}

    private var activeDownloadUrl: String {
        if let rel = service.latestGitHubRelease, !rel.ipaDownloadUrl.isEmpty {
            return rel.ipaDownloadUrl
        }
        return service.remoteStreamConfig.latestIpaUrl
    }

    public var body: some View {
        ZStack {
            FPTGlassBackdrop()

            VStack(alignment: .leading, spacing: 24) {
                // Thanh tiêu đề trên cùng
                HStack(spacing: 16) {
                    Image(systemName: "arrow.triangle.2.circlepath.icloud.fill")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(fptOrange)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("CẬP NHẬT TỰ ĐỘNG & ĐỔI LUỒNG QUA GITHUB")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text(service.lastUpdateCheckStatus)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(service.hasNewerGitHubUpdate ? .green : fptOrange)
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

                // Nội dung 2 cột: Cột trái = Đồng bộ nóng cấu hình luồng (Không cần cài lại IPA), Cột phải = Tải IPA mới nhất qua GitHub Release
                HStack(alignment: .top, spacing: 28) {
                    // CỘT TRÁI: HOT-UPDATE ĐỔI LUỒNG TỪ GITHUB
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 10) {
                            Image(systemName: "bolt.horizontal.icloud.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.green)
                            Text("1. ĐỔI LUỒNG TỰ ĐỘNG TỪ XA (KHÔNG CẦN CÀI LẠI IPA)")
                                .font(.system(size: 18, weight: .heavy))
                                .foregroundColor(.white)
                        }

                        Text("Khi FPT Play thay đổi cổng phát 4K/FHD hoặc cấu trúc link HLS, bạn chỉ cần bấm nút đồng bộ bên dưới (hoặc mở lại ứng dụng). FTVOS sẽ tự động nạp cấu hình luồng mới nhất từ GitHub ngay lập tức.")
                            .font(.system(size: 15))
                            .foregroundColor(.white.opacity(0.82))
                            .lineSpacing(4)

                        // Khối thông số cấu hình luồng đang kích hoạt
                        VStack(alignment: .leading, spacing: 10) {
                            configRow(
                                label: "Mã cấu hình Cloud GitHub:",
                                value: "#\(service.remoteStreamConfig.configVersion)",
                                valueColor: .green
                            )
                            configRow(
                                label: "Thứ tự cổng Trực Tiếp (Live 4K/FHD):",
                                value: service.remoteStreamConfig.liveGatewayOrder.map { $0.uppercased() }.joined(separator: " → "),
                                valueColor: fptOrange
                            )
                            configRow(
                                label: "Thứ tự cổng Phim & Xem Lại 4K (VOD):",
                                value: service.remoteStreamConfig.vodGatewayOrder.map { $0.uppercased() }.joined(separator: " → "),
                                valueColor: .cyan
                            )
                            configRow(
                                label: "Khóa nét & Đa luồng âm thanh 4K:",
                                value: service.remoteStreamConfig.keepAllTopTierAudioVariants
                                    ? "2160p50 / 1080p50 (Stereo + Dolby 5.1)"
                                    : "Khóa biến thể băng thông cao nhất",
                                valueColor: .white
                            )
                            configRow(
                                label: "Cập nhật cấu hình gần nhất:",
                                value: service.remoteStreamConfig.updatedAt,
                                valueColor: .gray
                            )
                        }
                        .padding(18)
                        .background(Color.black.opacity(0.32))
                        .cornerRadius(16)

                        // Nút bấm đồng bộ ngay từ GitHub
                        Button {
                            Task {
                                await service.checkAndSyncGitHubUpdate(manual: true)
                            }
                        } label: {
                            HStack(spacing: 14) {
                                if service.isCheckingUpdate {
                                    ProgressView()
                                } else {
                                    Image(systemName: "arrow.clockwise.icloud.fill")
                                        .font(.system(size: 22, weight: .bold))
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(service.isCheckingUpdate ? "Đang đồng bộ từ GitHub..." : "Đồng Bộ Cấu Hình Luồng Mới Nhất Ngay")
                                        .font(.system(size: 18, weight: .bold))
                                    Text("Tải lại remote_stream_config.json & làm mới toàn bộ danh sách kênh")
                                        .font(.system(size: 13))
                                        .opacity(0.85)
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

                        // Nút bật/tắt ưu tiên 4K UHD
                        Button {
                            service.togglePrefer4K()
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: service.prefer4K ? "4k.tv.fill" : "tv.fill")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundColor(fptOrange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(service.prefer4K ? "Đang BẬT: Ưu tiên luồng 4K UHD 50fps (Khóa nét 2160p)" : "Đang BẬT: Chế độ Full HD 1080p 50fps")
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundColor(.white)
                                    Text("Bấm để chuyển đổi chế độ mặc định khi mở kênh 4K")
                                        .font(.system(size: 13))
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity)
                            .background(Color.white.opacity(0.10))
                            .cornerRadius(16)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .fptGlassPanel(cornerRadius: 24)

                    // CỘT PHẢI: CẬP NHẬT FILE FTVOS.IPA QUA GITHUB RELEASES
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 10) {
                            Image(systemName: "shippingbox.and.arrow.backward.fill")
                                .font(.system(size: 22))
                                .foregroundColor(fptOrange)
                            Text("2. CẬP NHẬT ỨNG DỤNG FTVOS.IPA TỪ GITHUB")
                                .font(.system(size: 18, weight: .heavy))
                                .foregroundColor(.white)
                        }

                        HStack(alignment: .top, spacing: 20) {
                            // Mã QR quét tải trực tiếp bản mới nhất
                            VStack(spacing: 8) {
                                if let qrImg = makeQRCodeImage(from: activeDownloadUrl) {
                                    Image(uiImage: qrImg)
                                        .interpolation(.none)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 176, height: 176)
                                        .padding(12)
                                        .background(Color.white)
                                        .cornerRadius(16)
                                }
                                Text("Quét QR tải FTVOS.ipa")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(fptOrange)
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                versionBadgeRow(
                                    title: "Bản đang cài trên TV:",
                                    val: service.currentAppVersionLabel,
                                    color: .white
                                )
                                versionBadgeRow(
                                    title: "Bản mới nhất trên GitHub:",
                                    val: service.latestGitHubRelease?.tagName ?? "v\(service.remoteStreamConfig.latestAppVersion)-\(service.remoteStreamConfig.latestBuildNumber)",
                                    color: service.hasNewerGitHubUpdate ? .green : fptOrange
                                )
                                versionBadgeRow(
                                    title: "Dung lượng gói IPA:",
                                    val: service.latestGitHubRelease?.fileSizeText ?? "~1.7 MB",
                                    color: .cyan
                                )

                                Text(service.hasNewerGitHubUpdate
                                     ? "🟢 Đã có bản IPA mới hơn trên GitHub! Bạn có thể tải qua link cố định bên dưới."
                                     : "✅ Phiên bản ứng dụng trên Apple TV của bạn đang là bản mới nhất.")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(service.hasNewerGitHubUpdate ? .green : .white.opacity(0.85))
                                    .padding(.top, 4)
                            }
                        }

                        // Ghi chú phát hành (Release notes)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Nội dung bản cập nhật mới nhất:")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.gray)
                            Text(service.latestGitHubRelease?.notes ?? service.remoteStreamConfig.updateNotes)
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.9))
                                .lineLimit(4)
                                .lineSpacing(3)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.32))
                        .cornerRadius(14)

                        // Link cố định luôn trỏ về bản mới nhất
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Link tải tự động bản mới nhất (luôn cố định cho bạn bè):")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.gray)
                            Text("https://github.com/hongson117/FPTios/releases/latest/download/FTVOS.ipa")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundColor(fptOrange)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
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
            await service.checkAndSyncGitHubUpdate(manual: false)
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

    @ViewBuilder
    private func versionBadgeRow(title: String, val: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(.gray)
            Text(val)
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundColor(color)
        }
    }

    private func makeQRCodeImage(from string: String) -> UIImage? {
        guard let data = string.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else {
            return nil
        }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let transformed = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImg = ciContext.createCGImage(transformed, from: transformed.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImg)
    }
}
