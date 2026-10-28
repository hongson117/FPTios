//
//  FPTTheme.swift
//  Bảng màu & hiệu ứng kính mờ (glassmorphism) kiểu Apple TV+ dùng chung cho toàn app.
//  Chỉ chứa code giao diện, không đụng logic.
//

import SwiftUI

enum FPTTheme {
    // Nền tối hơi tím than để màu gradient nổi bật
    static let bg = Color(red: 0.055, green: 0.047, blue: 0.105)           // #0E0C1B
    static let surface = Color(red: 0.11, green: 0.10, blue: 0.18)
    // Màu nhấn trẻ trung
    static let accent = Color(red: 1.0, green: 0.42, blue: 0.10)           // cam FPT tươi
    static let accent2 = Color(red: 1.0, green: 0.27, blue: 0.55)          // hồng neon
    static let violet = Color(red: 0.52, green: 0.33, blue: 1.0)           // tím
    static let cyan = Color(red: 0.20, green: 0.78, blue: 1.0)             // xanh ngọc

    static let accentGradient = LinearGradient(
        colors: [accent, accent2],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let glassStroke = LinearGradient(
        colors: [Color.white.opacity(0.35), Color.white.opacity(0.06)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// Phông nền gradient mềm nhiều màu, có các đốm sáng mờ (giống Apple TV+).
struct FPTGlassBackdrop: View {
    var body: some View {
        ZStack {
            FPTTheme.bg

            RadialGradient(
                colors: [FPTTheme.violet.opacity(0.32), Color.clear],
                center: .bottomLeading,
                startRadius: 10,
                endRadius: 900
            )

            RadialGradient(
                colors: [FPTTheme.accent2.opacity(0.20), Color.clear],
                center: .bottomTrailing,
                startRadius: 10,
                endRadius: 820
            )

            RadialGradient(
                colors: [FPTTheme.cyan.opacity(0.12), Color.clear],
                center: .center,
                startRadius: 10,
                endRadius: 700
            )
        }
        .ignoresSafeArea()
    }
}

/// Tấm kính mờ bo góc có viền sáng mảnh.
struct FPTGlassPanel: ViewModifier {
    var cornerRadius: CGFloat = 24
    var tint: Color = Color.white.opacity(0.04)

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(FPTTheme.glassStroke, lineWidth: 1.2)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: Color.black.opacity(0.35), radius: 24, x: 0, y: 12)
    }
}

extension View {
    func fptGlassPanel(cornerRadius: CGFloat = 24, tint: Color = Color.white.opacity(0.04)) -> some View {
        modifier(FPTGlassPanel(cornerRadius: cornerRadius, tint: tint))
    }
}
