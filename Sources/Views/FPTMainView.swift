//
//  FPTMainView.swift
//  FTVOS (Apple TV / tvOS)
//
//  Giao diện chuẩn FPT Play V2 Android TV (tham chiếu trực tiếp từ RockTek G2):
//  - Nền tối chuẩn #131314 & Cam FPT #FF6500
//  - Thanh điều hướng dọc bên trái (v2_home_menu_nav_view) kèm Avatar mặt cười xanh FPT + Bảng Điều Khiển Quản Lý (ui-account-open)
//  - Khối Hero Spotlight 16:9 góc trên bên phải (block__highlight) tự động cập nhật theo mục đang trỏ trên điều khiển Apple TV:
//    + Với Kênh Truyền Hình: Sân khấu đa giác tối kèm Logo kênh lớn bên phải & Tên kênh lớn bên trái (screen-menu.png / screen-back.png)
//    + Với Thể Thao / Phim Bộ / Phim Lẻ: Poster 16:9 toàn cảnh bên phải hòa trộn Gradient #131314 + Thông tin chi tiết bên trái (screen-football.png)
//  - Các dải ngang (Horizontal Rails) chuẩn G2 + Lịch thi đấu & kết quả + Bảng Kênh Đánh Số 3 Cột (screen-dpad.png)
//  - Màn hình Chi Tiết Phim Bộ & Phim Lẻ chuẩn vod_detail_item_v2.xml + Chọn nhóm tập (Tập 1-20, 21-40...)
//

import SwiftUI

public struct FPTMainView: View {
    @StateObject private var service = FPTService.shared
    @Environment(\.scenePhase) private var scenePhase

    // Các mục trên thanh điều hướng dọc bên trái chuẩn G2:
    // "search", "home", "tv_guide", "live_football", "vod_series", "vod_movies", "intl_channels", "vn_channels", "library"
    @State private var selectedNavId: String = "home"
    @State private var tvGuideFilter: String = "all" // "suggested", "all", "vn", "intl"
    @State private var showAccountPanel: Bool = false
    @State private var showAuthSheet: Bool = false

    @State private var focusedChannel: FPTChannel? = nil
    @State private var activeStream: FPTResolvedStream? = nil
    @State private var activeStreamResumeSeconds: Double = 0
    @State private var activeVodDetail: FPTVodDetail? = nil
    @State private var autoPlayEpisodeOnOpen: String? = nil
    @State private var isResolving: Bool = false
    @State private var resolvingName: String = ""
    @State private var errorMessage: String? = nil

    @State private var searchText: String = ""
    @State private var searchFilter: String = "all"

    private let g2Bg = FPTTheme.bg
    private let g2Surface = Color(red: 0.125, green: 0.13, blue: 0.145)   // #202125
    private let fptOrange = FPTTheme.accent
    private let scheduleAutoRefreshTimer = Timer.publish(every: 120, on: .main, in: .common).autoconnect()

    private let fourColumns = [
        GridItem(.flexible(), spacing: 26),
        GridItem(.flexible(), spacing: 26),
        GridItem(.flexible(), spacing: 26),
        GridItem(.flexible(), spacing: 26)
    ]

    private let threeColumns = [
        GridItem(.flexible(), spacing: 18),
        GridItem(.flexible(), spacing: 18),
        GridItem(.flexible(), spacing: 18)
    ]

    public init() {}

    // MARK: - Danh sách kênh theo từng nhóm
    private var liveEventsList: [FPTChannel] {
        service.categories.first(where: { $0.id == "live_football" })?.channels ?? []
    }

    private var vodSeriesList: [FPTChannel] {
        service.categories.first(where: { $0.id == "vod_series" })?.channels ?? []
    }

    private var vodMoviesList: [FPTChannel] {
        service.categories.first(where: { $0.id == "vod_movies" })?.channels ?? []
    }

    private var intlChannelsList: [FPTChannel] {
        service.categories.first(where: { $0.id == "intl_channels" || $0.id == "intl_drm" || $0.id == "intl_open" })?.channels ?? []
    }

    private var vnChannelsList: [FPTChannel] {
        service.categories.first(where: { $0.id == "vn_channels" || $0.id == "vn_tv" })?.channels ?? []
    }

    private var allTvChannelsList: [FPTChannel] {
        vnChannelsList + intlChannelsList
    }

    private var suggestedTvChannelsList: [FPTChannel] {
        let priorityIds = ["vtv1-hd", "vinh-long-1", "thvl1", "vinh-long-2", "vinh-long-3", "vinh-long-4-hd", "vinh-long-5", "htv9-hd", "htv7-hd", "vtv3-hd", "vtv2-hd", "antv", "dong-thap", "hbo", "max-by-hbo", "cnn", "bbc-news", "axn"]
        var picked: [FPTChannel] = []
        var seen: Set<String> = []
        for pid in priorityIds {
            if let found = allTvChannelsList.first(where: { $0.channelId.lowercased().contains(pid) }) {
                if !seen.contains(found.id) {
                    seen.insert(found.id)
                    picked.append(found)
                }
            }
        }
        for ch in allTvChannelsList where picked.count < 16 {
            if !seen.contains(ch.id) {
                seen.insert(ch.id)
                picked.append(ch)
            }
        }
        return picked
    }

    private var heroChannel: FPTChannel? {
        if let focused = focusedChannel {
            return focused
        }
        switch selectedNavId {
        case "home":
            return liveEventsList.first ?? vodMoviesList.first ?? vodSeriesList.first ?? suggestedTvChannelsList.first
        case "tv_guide", "vn_channels":
            return vnChannelsList.first ?? suggestedTvChannelsList.first
        case "intl_channels":
            return intlChannelsList.first
        case "live_football":
            return liveEventsList.first
        case "vod_series":
            return vodSeriesList.first
        case "vod_movies":
            return vodMoviesList.first
        case "library":
            return service.watchHistory.first?.channel ?? vodSeriesList.first
        case "search":
            return filteredSearchResults.first ?? vodMoviesList.first
        default:
            return liveEventsList.first ?? vnChannelsList.first
        }
    }

    private var filteredSearchResults: [FPTChannel] {
        switch searchFilter {
        case "series":
            return service.searchResults.filter { $0.isSeries }
        case "movies":
            return service.searchResults.filter { !$0.isSeries }
        default:
            return service.searchResults
        }
    }

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .leading) {
                FPTGlassBackdrop()

                // Khung nội dung chính bên phải thanh Sidebar (x = 122pt chuẩn G2)
                mainContentArea
                    .padding(.leading, 288)
                    .focusSection()

                // Thanh điều hướng dọc bên trái chuẩn FPT Play Android TV (v2_home_menu_nav_view)
                g2LeftNavigationSidebar
                    .focusSection()

                // Bảng Điều Khiển Quản Lý Tài Khoản trượt từ bên trái (chuẩn ui-account-open.xml trên G2)
                if showAccountPanel {
                    g2AccountControlPanelOverlay
                }

                // Màn hình loading khi đang xin luồng
                if isResolving {
                    ZStack {
                        Color.black.opacity(0.78).ignoresSafeArea()
                        VStack(spacing: 18) {
                            ProgressView()
                                .scaleEffect(1.7)
                            Text("Đang mở \(resolvingName)...")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                            Text(service.prefer4K ? "Chế độ 4K UHD HEVC • FairPlay Hardware DRM" : "Chế độ Full HD • FairPlay Hardware DRM")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(fptOrange)
                        }
                        .padding(42)
                        .fptGlassPanel(cornerRadius: 28)
                    }
                }
            }
            .task {
                await service.refreshAll(forceEvents: true)
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active && activeStream == nil && activeVodDetail == nil {
                    Task {
                        await service.fetchCatalog(forceEvents: true)
                    }
                }
            }
            .onReceive(scheduleAutoRefreshTimer) { _ in
                if activeStream == nil && activeVodDetail == nil && !showAuthSheet && !isResolving {
                    Task {
                        await service.fetchCatalog(forceEvents: true)
                    }
                }
            }
            .sheet(isPresented: $showAuthSheet) {
                FPTAuthSheet()
            }
            .fullScreenCover(item: $activeVodDetail) { detail in
                FPTVodDetailSheet(
                    detail: detail,
                    initialAutoPlayEpisodeId: autoPlayEpisodeOnOpen,
                    onOpenAuth: {
                        activeVodDetail = nil
                        showAuthSheet = true
                    }
                )
            }
            .fullScreenCover(item: $activeStream) { stream in
                FPTPlayerView(
                    resolved: stream,
                    resumeSeconds: activeStreamResumeSeconds
                )
                .ignoresSafeArea()
            }
            .alert("Thông Báo Phát Sóng", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("Đăng Nhập / Đổi Tài Khoản") {
                    showAuthSheet = true
                }
                Button("Đóng", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - 1. Thanh Điều Hướng Dọc Bên Trái Chuẩn FPT Play Android TV (G2)
    private var g2LeftNavigationSidebar: some View {
        let navItems: [(id: String, icon: String, title: String)] = [
            ("search", "magnifyingglass", "Tìm kiếm"),
            ("tv_guide", "tv", "Truyền hình"),
            ("home", "house.fill", "Trang chủ"),
            ("live_football", "sportscourt.fill", "Trực tiếp"),
            ("vod_series", "play.square.stack.fill", "Phim bộ"),
            ("vod_movies", "film.fill", "Phim lẻ"),
            ("intl_channels", "globe.asia.australia.fill", "Nước ngoài"),
            ("vn_channels", "antenna.radiowaves.left.and.right", "Trong nước"),
            ("library", "bookmark.fill", "Thư viện")
        ]

        return VStack(spacing: 14) {
            // Avatar Mặt Cười Xanh FPT Play ở đỉnh thanh điều hướng (giống hệt screen-menu.png trên G2)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showAccountPanel.toggle()
                }
            } label: {
                VStack(spacing: 4) {
                    ZStack(alignment: .bottomTrailing) {
                        Circle()
                            .fill(Color.white.opacity(0.92))
                            .frame(width: 96, height: 96)

                        // Khuôn mặt cười xanh đặc trưng của FPT Play Android TV
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.30, green: 0.38, blue: 0.62),
                                        Color(red: 0.22, green: 0.28, blue: 0.48)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 78, height: 78)
                            .overlay(
                                VStack(spacing: 3) {
                                    HStack(spacing: 8) {
                                        Circle().fill(Color.white).frame(width: 10, height: 10)
                                        Circle().fill(Color.white).frame(width: 10, height: 10)
                                    }
                                    Capsule()
                                        .fill(Color.white.opacity(0.9))
                                        .frame(width: 24, height: 5)
                                }
                            )

                        Circle()
                            .fill(service.isAuthenticated ? Color.green : fptOrange)
                            .frame(width: 22, height: 22)
                            .overlay(Circle().stroke(Color.black, lineWidth: 2))
                    }

                    Text(service.isAuthenticated ? "Tài khoản" : "Đăng nhập")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundColor(service.isAuthenticated ? .green : fptOrange)
                        .lineLimit(1)
                }
            }
            .buttonStyle(FPTG2SidebarAvatarStyle())
            .padding(.top, 24)
            .padding(.bottom, 8)

            // Danh sách các icon điều hướng dọc
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(navItems, id: \.id) { item in
                        let isSelected = (selectedNavId == item.id)
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                selectedNavId = item.id
                                focusedChannel = nil
                            }
                        } label: {
                            FPTG2SidebarNavRow(
                                icon: item.icon,
                                title: item.title,
                                isSelected: isSelected,
                                fptOrange: fptOrange
                            )
                        }
                        .buttonStyle(FPTG2SidebarButtonStyle(isSelected: isSelected, fptOrange: fptOrange))
                    }
                }
                .padding(.vertical, 6)
            }

            Spacer(minLength: 8)

            // Logo FPT Play nhỏ dưới đáy thanh bên trái
            Image("FPTLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 132, height: 50)
                .opacity(0.85)
                .padding(.bottom, 22)
        }
        .frame(width: 284)
        .frame(maxHeight: .infinity)
        .background(
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                LinearGradient(
                    colors: [FPTTheme.violet.opacity(0.18), FPTTheme.accent2.opacity(0.06)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                HStack {
                    Spacer()
                    Rectangle()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 1)
                }
            }
            .ignoresSafeArea()
        )
    }

    // MARK: - 2. Bảng Điều Khiển Quản Lý Tài Khoản (chuẩn ui-account-open.xml trên G2)
    private var g2AccountControlPanelOverlay: some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.68)
                .ignoresSafeArea()
                .onTapGesture {
                    showAccountPanel = false
                }

            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text("QUẢN LÝ")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundColor(.gray)
                    Spacer()
                    Button {
                        showAccountPanel = false
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark")
                            Text("Đóng")
                        }
                        .font(.system(size: 15, weight: .bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.12))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }

                // Danh sách hồ sơ (Người dùng / Trẻ em giống G2)
                HStack(spacing: 18) {
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .stroke(Color.white, lineWidth: 3)
                                .frame(width: 72, height: 72)
                            Circle()
                                .fill(Color(red: 0.28, green: 0.36, blue: 0.60))
                                .frame(width: 62, height: 62)
                            Image(systemName: "checkmark")
                                .font(.system(size: 20, weight: .black))
                                .foregroundColor(.white)
                        }
                        Text("Người dùng")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }

                    VStack(spacing: 8) {
                        ZStack(alignment: .bottom) {
                            Circle()
                                .fill(Color.white.opacity(0.12))
                                .frame(width: 72, height: 72)
                            Image(systemName: "face.smiling.inverse")
                                .font(.system(size: 32))
                                .foregroundColor(fptOrange)
                                .padding(.bottom, 18)
                            Text("KID")
                                .font(.system(size: 10, weight: .black))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(fptOrange)
                                .foregroundColor(.black)
                                .cornerRadius(4)
                        }
                        Text("Thiếu nhi")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.gray)
                    }
                }

                // Hai nút hành động chính: Số điện thoại (OTP) & Cài đặt 4K (giống vgv_menu_actions trên G2)
                HStack(spacing: 14) {
                    Button {
                        showAccountPanel = false
                        showAuthSheet = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(service.isAuthenticated ? .green : fptOrange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(service.isAuthenticated ? (service.userPhone.isEmpty ? "UID: \(service.userId)" : service.userPhone) : "Đăng nhập OTP")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Text(service.isAuthenticated ? "Đổi TK / Thiết bị" : "Tài khoản chính chủ")
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.10))
                        .cornerRadius(12)
                    }
                    .buttonStyle(FPTG2CardButtonStyle())

                    Button {
                        service.togglePrefer4K()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "4k.tv.fill")
                                .font(.system(size: 20))
                                .foregroundColor(service.prefer4K ? fptOrange : .gray)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(service.prefer4K ? "Ưu tiên 4K UHD" : "Chế độ Full HD")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                Text("Bấm để chuyển đổi")
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.10))
                        .cornerRadius(12)
                    }
                    .buttonStyle(FPTG2CardButtonStyle())
                }

                HStack {
                    Text("SỰ KIỆN & THÔNG BÁO NỔI BẬT")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundColor(.gray)
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 1)
                }
                .padding(.top, 6)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 12) {
                        ForEach(liveEventsList.prefix(5)) { ev in
                            Button {
                                showAccountPanel = false
                                openChannel(ev)
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(ev.name)
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        Text(ev.desc)
                                            .font(.system(size: 13))
                                            .foregroundColor(.gray)
                                            .lineLimit(2)
                                        Text(ev.statusText)
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(fptOrange)
                                    }
                                    Spacer()
                                    if let url = URL(string: ev.logo), !ev.logo.isEmpty {
                                        AsyncImage(url: url) { phase in
                                            if let img = phase.image {
                                                img.resizable()
                                                    .scaledToFill()
                                                    .frame(width: 124, height: 70)
                                                    .clipped()
                                                    .cornerRadius(8)
                                            }
                                        }
                                    }
                                }
                                .padding(12)
                                .background(Color.white.opacity(0.06))
                                .cornerRadius(12)
                            }
                            .buttonStyle(FPTG2CardButtonStyle())
                        }
                    }
                }
            }
            .padding(28)
            .frame(width: 540)
            .frame(maxHeight: .infinity)
            .fptGlassPanel(cornerRadius: 32, tint: FPTTheme.violet.opacity(0.08))
            .padding(.leading, 36)
            .padding(.vertical, 28)
        }
    }

    // MARK: - 3. Khu Vực Nội Dung Chính Theo Từng Mục Trên G2
    @ViewBuilder
    private var mainContentArea: some View {
        if service.isLoadingCatalog && service.categories.isEmpty {
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.6)
                Text("Đang tải giao diện FPT Play...")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch selectedNavId {
            case "search":
                g2SearchScreen
            case "tv_guide":
                g2NumberedChannelGuideScreen
            case "home":
                g2HomeScreen
            case "live_football":
                g2LiveSportsScreen
            case "vod_series":
                g2VodCatalogScreen(isSeries: true)
            case "vod_movies":
                g2VodCatalogScreen(isSeries: false)
            case "intl_channels":
                g2TvShowcaseScreen(isInternational: true)
            case "vn_channels":
                g2TvShowcaseScreen(isInternational: false)
            case "library":
                g2LibraryScreen
            default:
                g2HomeScreen
            }
        }
    }

    // MARK: - 4. Khối Hero Spotlight 16:9 Góc Trên Bên Phải Chuẩn G2 (block__highlight.xml — Gọn, Không Đẩy Thụt Thẻ Bài Xuống Dưới & Có Nút Focus Ngang)
    @ViewBuilder
    private func g2HeroSpotlightBanner(for item: FPTChannel?, sectionLabel: String) -> some View {
        let ch = item ?? suggestedTvChannelsList.first
        let isTvChannel = (ch != nil && !ch!.isVod && ch!.categoryId != "live_football")

        ZStack(alignment: .bottomLeading) {
            // Khung nền phải (62% chiều ngang màn hình giống iv_banner trên G2)
            HStack(spacing: 0) {
                Spacer(minLength: 420)

                ZStack {
                    if isTvChannel {
                        // Sân khấu Đa Giác Tối + Logo Kênh Lớn Chính Giữa Bên Phải (giống hệt screen-menu.png & screen-back.png trên G2!)
                        FPTG2PolygonalStageView()
                            .frame(width: 1080, height: 276)

                        if let activeCh = ch {
                            FPTChannelLogoView(
                                channel: activeCh,
                                maxWidth: 280,
                                maxHeight: 150,
                                fallbackFontSize: 26
                            )
                            .shadow(color: .black.opacity(0.6), radius: 16, x: 0, y: 8)
                            .offset(x: 90, y: -8)
                        }
                    } else {
                        // Poster 16:9 toàn cảnh bên phải cho Trực Tiếp / Phim Bộ / Phim Lẻ (giống screen-football.png)
                        if let logoStr = ch?.logo, let url = URL(string: logoStr), !logoStr.isEmpty {
                            AsyncImage(url: url) { phase in
                                if let img = phase.image {
                                    img
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 1120, height: 276)
                                        .clipped()
                                } else {
                                    FPTG2PolygonalStageView()
                                        .frame(width: 1120, height: 276)
                                }
                            }
                        } else {
                            FPTG2PolygonalStageView()
                                .frame(width: 1120, height: 276)
                        }
                    }
                }
                .overlay(
                    // Mặt nạ hòa trộn cạnh trái mượt vào nền #131314
                    LinearGradient(
                        stops: [
                            .init(color: g2Bg, location: 0.0),
                            .init(color: g2Bg.opacity(0.88), location: 0.22),
                            .init(color: g2Bg.opacity(0.28), location: 0.55),
                            .init(color: Color.clear, location: 1.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(
                    // Mặt nạ hòa trộn cạnh dưới mượt vào nền #131314
                    LinearGradient(
                        stops: [
                            .init(color: Color.clear, location: 0.0),
                            .init(color: g2Bg.opacity(0.25), location: 0.58),
                            .init(color: g2Bg, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }

            // Cột thông tin tiêu đề & mô tả bên trái (tv_title, ll_content, tv_des trên G2) kèm nút bấm Focus trực tiếp
            if let active = ch {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Text(sectionLabel.uppercased())
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(FPTTheme.accentGradient))
                            .foregroundColor(.white)
                            .shadow(color: FPTTheme.accent2.opacity(0.5), radius: 8, x: 0, y: 2)

                        if active.is4K {
                            Text("4K UHD")
                                .font(.system(size: 12, weight: .black))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.18))
                                .foregroundColor(.white)
                                .cornerRadius(5)
                        }

                        if !active.statusText.isEmpty {
                            Text(active.statusText)
                                .font(.system(size: 12, weight: .bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.12))
                                .foregroundColor(fptOrange)
                                .cornerRadius(5)
                        }
                    }

                    if isTvChannel {
                        HStack(spacing: 16) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(red: 0.16, green: 0.17, blue: 0.20))
                                    .frame(width: 108, height: 58)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
                                    )
                                FPTChannelLogoView(
                                    channel: active,
                                    maxWidth: 84,
                                    maxHeight: 42,
                                    fallbackFontSize: 13
                                )
                            }

                            Text(active.name)
                                .font(.system(size: 36, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .frame(maxWidth: 580, alignment: .leading)
                        }
                    } else if let tLogo = active.titleLogo.isEmpty ? nil : active.titleLogo, let tUrl = URL(string: tLogo) {
                        AsyncImage(url: tUrl) { phase in
                            if let img = phase.image {
                                img
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: 400, maxHeight: 64, alignment: .leading)
                            } else {
                                Text(active.name)
                                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .frame(maxWidth: 680, alignment: .leading)
                            }
                        }
                    } else {
                        Text(active.name)
                            .font(.system(size: 36, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .frame(maxWidth: 680, alignment: .leading)
                    }

                    // Dòng metadata ngăn cách bởi dấu • chuẩn G2 + Nút Xem ngay có thể Focus khi bấm Sang Phải từ Sidebar
                    HStack(spacing: 16) {
                        Button {
                            openChannel(active)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 14, weight: .black))
                                Text(active.isVod ? "Chi tiết & Xem phim" : "Phát trực tiếp ngay")
                                    .font(.system(size: 15, weight: .bold))
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 9)
                        }
                        .buttonStyle(FPTG2VodActionButtonStyle())

                        HStack(spacing: 8) {
                            Text(active.badge.replacingOccurrences(of: "🎞️ ", with: "").replacingOccurrences(of: "🎬 ", with: ""))
                            Text("•")
                            Text(active.resolution)
                            if !active.fps.isEmpty {
                                Text("•")
                                Text(active.fps)
                            }
                        }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.72))
                        .lineLimit(1)
                    }

                    if !active.desc.isEmpty {
                        Text(active.desc)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(Color.white.opacity(0.85))
                            .lineLimit(1)
                            .frame(maxWidth: 680, alignment: .leading)
                    }
                }
                .padding(.leading, 36)
                .padding(.bottom, 14)
            }
        }
        .frame(height: 268)
        .focusSection()
    }

    // MARK: - 5. Màn Hình TRANG CHỦ Chuẩn FPT Play Android TV (G2)
    private var g2HomeScreen: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                g2HeroSpotlightBanner(for: heroChannel, sectionLabel: "Tâm Điểm FPT Play")

                // Dải 1: Kênh gợi ý (giống hệt screen-menu.png trên G2!)
                if !suggestedTvChannelsList.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Kênh gợi ý")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                            Spacer()
                            Button {
                                selectedNavId = "tv_guide"
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "list.number")
                                    Text("Mở bảng kênh đánh số (3 cột)")
                                }
                                .font(.system(size: 15, weight: .bold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.12))
                                .foregroundColor(fptOrange)
                                .cornerRadius(8)
                            }
                            .buttonStyle(FPTG2CardButtonStyle())
                        }
                        .padding(.horizontal, 36)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 22) {
                                ForEach(suggestedTvChannelsList) { ch in
                                    Button {
                                        openChannel(ch)
                                    } label: {
                                        FPTG2TvChannelTile(channel: ch) {
                                            focusedChannel = ch
                                        }
                                    }
                                    .buttonStyle(FPTG2CardButtonStyle())
                                }
                            }
                            .padding(.horizontal, 36)
                            .padding(.vertical, 8)
                        }
                    }
                    .focusSection()
                }

                // Dải 2: Đang xem tiếp (Watch History)
                if !service.watchHistory.isEmpty {
                    g2WatchHistoryRail
                }

                // Dải 3: Chương trình & Sự kiện trực tiếp nổi bật (giống screen-menu.png & screen-football.png)
                if !liveEventsList.isEmpty {
                    g2HorizontalLandscapeRail(
                        title: "Chương trình & Sự kiện trực tiếp",
                        items: Array(liveEventsList.prefix(14)),
                        showTimePill: true
                    )
                }

                // Dải 4: Bảng Xếp Hạng Top 10 Phim Thịnh Hành (chuẩn block__vertical_rank.xml trên G2)
                if !vodSeriesList.isEmpty {
                    g2Top10VerticalRankedRail(
                        title: "Top 10 Phim Bộ Thịnh Hành Hôm Nay",
                        items: Array(vodSeriesList.prefix(10))
                    )
                }

                // Dải 5: Phim Lẻ & Galaxy Play đặc sắc (Poster dọc 2:3 chuẩn block__vertical.xml trên G2)
                if !vodMoviesList.isEmpty {
                    g2VerticalPosterRail(
                        title: "Phim lẻ & Galaxy Play đặc sắc",
                        items: Array(vodMoviesList.prefix(14))
                    )
                }

                // Dải 6: Phim Bộ Hot Mới Cập Nhật (Poster dọc 2:3 chuẩn block__vertical.xml trên G2)
                if !vodSeriesList.isEmpty {
                    g2VerticalPosterRail(
                        title: "Phim bộ đặc sắc mới cập nhật",
                        items: Array(vodSeriesList.prefix(14))
                    )
                }

                // Dải 7: Lịch thi đấu và kết quả (giống hgv_fr_cards dưới đáy screen-football.png)
                if !liveEventsList.isEmpty {
                    g2MatchScheduleCardsRail(items: Array(liveEventsList.prefix(12)))
                }
            }
            .padding(.bottom, 64)
        }
    }

    // MARK: - 6. Màn Hình BẢNG KÊNH ĐÁNH SỐ 3 CỘT Chuẩn G2 (screen-dpad.png / live_view_channel.xml)
    private var g2NumberedChannelGuideScreen: some View {
        let displayedChannels: [(number: Int, channel: FPTChannel)] = {
            let allIndexed = allTvChannelsList.enumerated().map { (idx, ch) in (number: idx + 1, channel: ch) }
            switch tvGuideFilter {
            case "suggested":
                let sugSet = Set(suggestedTvChannelsList.map { $0.id })
                return allIndexed.filter { sugSet.contains($0.channel.id) }
            case "vn":
                return allIndexed.filter { $0.channel.categoryId == "vn_channels" || $0.channel.categoryId == "vn_tv" }
            case "intl":
                return allIndexed.filter { $0.channel.categoryId == "intl_channels" || $0.channel.categoryId == "intl_drm" || $0.channel.categoryId == "intl_open" }
            default:
                return allIndexed
            }
        }()

        return VStack(alignment: .leading, spacing: 22) {
            // Thanh tiêu đề & bộ lọc nhóm kênh (⭐ Kênh gợi ý | 📺 Tất cả | 🇻🇳 Trong nước | 🌍 Quốc tế)
            HStack(spacing: 16) {
                Text(tvGuideFilter == "suggested" ? "Kênh gợi ý" : (tvGuideFilter == "vn" ? "Kênh trong nước" : (tvGuideFilter == "intl" ? "Kênh quốc tế" : "Danh sách kênh truyền hình")))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)

                Spacer()

                HStack(spacing: 12) {
                    tvGuideFilterPill(id: "all", icon: "square.grid.2x2.fill", title: "Tất cả (\(allTvChannelsList.count))")
                    tvGuideFilterPill(id: "suggested", icon: "star.fill", title: "Kênh gợi ý")
                    tvGuideFilterPill(id: "vn", icon: "tv.fill", title: "Trong nước (\(vnChannelsList.count))")
                    tvGuideFilterPill(id: "intl", icon: "globe", title: "Quốc tế (\(intlChannelsList.count))")
                }
            }
            .padding(.horizontal, 36)
            .padding(.top, 28)

            // Bảng kênh 3 cột đánh số chuẩn G2 (screen-dpad.png)
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: threeColumns, spacing: 14) {
                    ForEach(displayedChannels, id: \.channel.id) { entry in
                        Button {
                            openChannel(entry.channel)
                        } label: {
                            FPTG2NumberedChannelRow(
                                number: entry.number,
                                channel: entry.channel
                            ) {
                                focusedChannel = entry.channel
                            }
                        }
                        .buttonStyle(FPTG2NumberedRowButtonStyle(fptOrange: fptOrange))
                    }
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 8)
                .padding(.bottom, 60)
            }
        }
    }

    private func tvGuideFilterPill(id: String, icon: String, title: String) -> some View {
        let isSel = (tvGuideFilter == id)
        return Button {
            tvGuideFilter = id
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                Text(title)
                    .font(.system(size: 16, weight: .bold))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(isSel ? Color.white : Color(red: 0.18, green: 0.19, blue: 0.22))
            .foregroundColor(isSel ? .black : .white)
            .cornerRadius(10)
        }
        .buttonStyle(FPTG2CardButtonStyle())
    }

    // MARK: - 7. Màn Hình TRỰC TIẾP THỂ THAO & BÓNG ĐÁ Chuẩn G2 (screen-football.png)
    private var g2LiveSportsScreen: some View {
        let liveNow = liveEventsList.filter { $0.isLive }
        let upcoming = liveEventsList.filter { !$0.isLive }

        return ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                g2HeroSpotlightBanner(for: heroChannel ?? liveEventsList.first, sectionLabel: "Trực Tiếp Thể Thao")

                if !liveNow.isEmpty {
                    g2HorizontalLandscapeRail(
                        title: "🔴 Đang diễn ra trực tiếp (\(liveNow.count))",
                        items: liveNow,
                        showTimePill: true
                    )
                }

                if !upcoming.isEmpty {
                    g2HorizontalLandscapeRail(
                        title: "⏳ Sự kiện sắp diễn ra (\(upcoming.count))",
                        items: upcoming,
                        showTimePill: true
                    )
                }

                // Khối "Lịch thi đấu và kết quả" chuẩn screen-football.png
                if !liveEventsList.isEmpty {
                    g2MatchScheduleCardsRail(items: liveEventsList)
                }

                // Lưới toàn bộ sự kiện thể thao
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Tất cả sự kiện thể thao & giải đấu (\(liveEventsList.count))")
                            .font(.system(size: 23, weight: .bold))
                            .foregroundColor(.white)
                        Spacer()
                        Button {
                            Task {
                                await service.fetchCatalog(forceEvents: true)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise")
                                Text("Cập nhật lịch thi đấu")
                            }
                            .font(.system(size: 15, weight: .bold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.12))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .buttonStyle(FPTG2CardButtonStyle())
                    }
                    .padding(.horizontal, 36)

                    LazyVGrid(columns: fourColumns, spacing: 26) {
                        ForEach(liveEventsList) { ev in
                            Button {
                                openChannel(ev)
                            } label: {
                                FPTG2LandscapePosterCard(
                                    channel: ev,
                                    historyItem: nil,
                                    showTimePill: true
                                ) {
                                    focusedChannel = ev
                                }
                            }
                            .buttonStyle(FPTG2CardButtonStyle())
                        }
                    }
                    .padding(.horizontal, 36)
                }
                .focusSection()
            }
            .padding(.bottom, 64)
        }
    }

    // MARK: - 8. Màn Hình PHIM BỘ & PHIM LẺ (Kèm GALAXY PLAY) Chuẩn G2
    private func g2VodCatalogScreen(isSeries: Bool) -> some View {
        let allItems = isSeries ? vodSeriesList : vodMoviesList
        let groupedRails = groupChannelsByBadge(allItems)

        return ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                g2HeroSpotlightBanner(
                    for: heroChannel ?? allItems.first,
                    sectionLabel: isSeries ? "Phim Bộ FPT Play" : "Phim Lẻ & Galaxy Play"
                )

                // Thanh công cụ tìm nhanh ngay đầu trang Phim
                HStack(spacing: 14) {
                    Button {
                        selectedNavId = "search"
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(fptOrange)
                            Text("Tìm tên phim bộ, phim lẻ, Galaxy Play, diễn viên...")
                                .foregroundColor(.white.opacity(0.85))
                        }
                        .font(.system(size: 17, weight: .semibold))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.10))
                        .cornerRadius(24)
                    }
                    .buttonStyle(FPTG2CardButtonStyle())

                    Spacer()
                }
                .padding(.horizontal, 36)
                .focusSection()

                // Dải Top 10 Bảng Xếp Hạng Phim chuẩn block__vertical_rank.xml trên G2 (Số thứ tự 1..10 lớn bên trái Poster dọc)
                if !allItems.isEmpty {
                    g2Top10VerticalRankedRail(
                        title: isSeries ? "Top 10 Phim Bộ Xem Nhiều Nhất" : "Top 10 Phim Lẻ & Điện Ảnh Thịnh Hành",
                        items: Array(allItems.prefix(10))
                    )
                }

                // Các dải ngang Poster Dọc 2:3 phân theo từng chủ đề chuẩn block__vertical.xml trên G2
                ForEach(groupedRails, id: \.title) { rail in
                    g2VerticalPosterRail(
                        title: rail.title,
                        items: rail.items
                    )
                }

                // Toàn bộ danh sách hiển thị dạng lưới 6 cột Poster Dọc 2:3 chuẩn G2
                VStack(alignment: .leading, spacing: 18) {
                    Text(isSeries ? "Tất cả Phim Bộ (\(allItems.count))" : "Tất cả Phim Lẻ & Điện Ảnh (\(allItems.count))")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 36)

                    let sixVerticalColumns = [
                        GridItem(.flexible(), spacing: 24),
                        GridItem(.flexible(), spacing: 24),
                        GridItem(.flexible(), spacing: 24),
                        GridItem(.flexible(), spacing: 24),
                        GridItem(.flexible(), spacing: 24),
                        GridItem(.flexible(), spacing: 24)
                    ]

                    LazyVGrid(columns: sixVerticalColumns, spacing: 32) {
                        ForEach(allItems) { item in
                            Button {
                                openChannel(item)
                            } label: {
                                FPTG2VerticalPosterCard(
                                    channel: item,
                                    historyItem: service.historyItem(forVodOrChannelId: item.vodId),
                                    showTitleBelow: true
                                ) {
                                    focusedChannel = item
                                }
                            }
                            .buttonStyle(FPTG2CardButtonStyle())
                        }
                    }
                    .padding(.horizontal, 36)
                }
                .focusSection()
            }
            .padding(.bottom, 64)
        }
    }

    private func groupChannelsByBadge(_ items: [FPTChannel]) -> [(title: String, items: [FPTChannel])] {
        var order: [String] = []
        var dict: [String: [FPTChannel]] = [:]
        for ch in items {
            let cleanTitle = ch.badge
                .replacingOccurrences(of: "🎞️ ", with: "")
                .replacingOccurrences(of: "🎬 ", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let key = cleanTitle.isEmpty ? "Nổi bật" : cleanTitle
            if dict[key] == nil {
                order.append(key)
                dict[key] = []
            }
            dict[key]?.append(ch)
        }
        return order.compactMap { k in
            guard let arr = dict[k], !arr.isEmpty else { return nil }
            return (title: k, items: arr)
        }
    }

    // MARK: - 9. Màn Hình KÊNH TRONG NƯỚC & KÊNH NƯỚC NGOÀI Chuẩn G2 (screen-menu.png & screen-back.png)
    private func g2TvShowcaseScreen(isInternational: Bool) -> some View {
        let channels = isInternational ? intlChannelsList : vnChannelsList
        let topSuggested = Array(channels.prefix(12))
        let groupedTvRails = groupChannelsByBadge(channels)

        return ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                g2HeroSpotlightBanner(
                    for: heroChannel ?? channels.first,
                    sectionLabel: isInternational ? "Kênh Quốc Tế" : "Truyền Hình Trong Nước"
                )

                // Dải ngang "Kênh gợi ý" giống hệt screen-menu.png trên G2
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(isInternational ? "Kênh quốc tế gợi ý" : "Kênh trong nước gợi ý (VTV • HTV • THVL)")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)

                        Spacer()

                        Button {
                            tvGuideFilter = isInternational ? "intl" : "vn"
                            selectedNavId = "tv_guide"
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "list.number")
                                Text("Xem bảng kênh đánh số 3 cột")
                            }
                            .font(.system(size: 15, weight: .bold))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 9)
                            .background(Color.white.opacity(0.12))
                            .foregroundColor(fptOrange)
                            .cornerRadius(8)
                        }
                        .buttonStyle(FPTG2CardButtonStyle())
                    }
                    .padding(.horizontal, 36)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 22) {
                            ForEach(topSuggested) { ch in
                                Button {
                                    openChannel(ch)
                                } label: {
                                    FPTG2TvChannelTile(channel: ch) {
                                        focusedChannel = ch
                                    }
                                }
                                .buttonStyle(FPTG2CardButtonStyle())
                            }
                        }
                        .padding(.horizontal, 36)
                        .padding(.vertical, 8)
                    }
                }
                .focusSection()

                // Các dải ngang phân theo từng nhóm kênh (VTV, THVL, HTV/HTVC, Kênh Thiết Yếu, Kênh Địa Phương / Quốc Tế VIP, Quốc Tế Mở Rộng) kèm Logo đầy đủ
                ForEach(groupedTvRails, id: \.title) { rail in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Text(rail.title)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white)
                            Text("(\(rail.items.count) kênh)")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(fptOrange)
                        }
                        .padding(.horizontal, 36)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 22) {
                                ForEach(rail.items) { ch in
                                    Button {
                                        openChannel(ch)
                                    } label: {
                                        FPTG2TvChannelTile(channel: ch) {
                                            focusedChannel = ch
                                        }
                                    }
                                    .buttonStyle(FPTG2CardButtonStyle())
                                }
                            }
                            .padding(.horizontal, 36)
                            .padding(.vertical, 8)
                        }
                    }
                    .focusSection()
                }

                // Toàn bộ kênh trong danh mục dạng lưới 4 cột kèm Logo
                VStack(alignment: .leading, spacing: 16) {
                    Text(isInternational ? "Tất cả Kênh Nước Ngoài (\(channels.count) kênh)" : "Tất cả Kênh Trong Nước, THVL & Địa Phương (\(channels.count) kênh)")
                        .font(.system(size: 23, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 36)

                    LazyVGrid(columns: fourColumns, spacing: 24) {
                        ForEach(channels) { ch in
                            Button {
                                openChannel(ch)
                            } label: {
                                FPTG2TvChannelGridCard(channel: ch) {
                                    focusedChannel = ch
                                }
                            }
                            .buttonStyle(FPTG2CardButtonStyle())
                        }
                    }
                    .padding(.horizontal, 36)
                }
                .focusSection()
            }
            .padding(.bottom, 64)
        }
    }

    // MARK: - 10. Màn Hình TÌM KIẾM Chuẩn G2 (search_v2_fragment.xml)
    private var g2SearchScreen: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 26) {
                // Thanh nhập từ khóa chuẩn search_v2_fragment.xml
                HStack(spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(fptOrange)

                        TextField("Nhập tên phim bộ, phim lẻ, Galaxy Play, diễn viên...", text: $searchText)
                            .font(.system(size: 20, weight: .bold))
                            .submitLabel(.search)
                            .onSubmit {
                                Task {
                                    await service.searchVodCatalog(query: searchText)
                                }
                            }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color(red: 0.14, green: 0.15, blue: 0.17))
                    .cornerRadius(12)

                    Button {
                        Task {
                            await service.searchVodCatalog(query: searchText)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if service.isSearching {
                                ProgressView()
                            } else {
                                Image(systemName: "magnifyingglass")
                            }
                            Text("Tìm kiếm")
                                .font(.system(size: 18, weight: .bold))
                        }
                        .padding(.horizontal, 26)
                        .padding(.vertical, 14)
                        .background(fptOrange)
                        .foregroundColor(.black)
                        .cornerRadius(12)
                    }
                    .buttonStyle(FPTG2CardButtonStyle())

                    if !searchText.isEmpty || !service.lastSearchQuery.isEmpty {
                        Button {
                            searchText = ""
                            searchFilter = "all"
                            service.clearSearch()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "xmark.circle.fill")
                                Text("Xóa")
                                    .font(.system(size: 18, weight: .bold))
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                            .background(Color.white.opacity(0.12))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .buttonStyle(FPTG2CardButtonStyle())
                    }
                }
                .padding(.horizontal, 36)
                .padding(.top, 28)

                if !service.lastSearchQuery.isEmpty {
                    let seriesCount = service.searchResults.filter { $0.isSeries }.count
                    let movieCount = service.searchResults.filter { !$0.isSeries }.count

                    HStack(spacing: 14) {
                        Text("Kết quả cho '\(service.lastSearchQuery)' (\(service.searchTotal) phim):")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)

                        searchFilterButton(id: "all", label: "Tất cả (\(service.searchResults.count))")
                        searchFilterButton(id: "series", label: "Phim bộ (\(seriesCount))")
                        searchFilterButton(id: "movies", label: "Phim lẻ (\(movieCount))")
                        Spacer()
                    }
                    .padding(.horizontal, 36)

                    let sixSearchColumns = [
                        GridItem(.flexible(), spacing: 24),
                        GridItem(.flexible(), spacing: 24),
                        GridItem(.flexible(), spacing: 24),
                        GridItem(.flexible(), spacing: 24),
                        GridItem(.flexible(), spacing: 24),
                        GridItem(.flexible(), spacing: 24)
                    ]

                    LazyVGrid(columns: sixSearchColumns, spacing: 32) {
                        ForEach(filteredSearchResults) { ch in
                            Button {
                                openChannel(ch)
                            } label: {
                                FPTG2VerticalPosterCard(
                                    channel: ch,
                                    historyItem: service.historyItem(forVodOrChannelId: ch.vodId),
                                    showTitleBelow: true
                                ) {
                                    focusedChannel = ch
                                }
                            }
                            .buttonStyle(FPTG2CardButtonStyle())
                        }
                    }
                    .padding(.horizontal, 36)

                    if service.searchTotal > service.searchResults.count {
                        HStack {
                            Spacer()
                            Button {
                                Task {
                                    await service.searchVodCatalog(query: service.lastSearchQuery, appendNextPage: true)
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    if service.isSearching {
                                        ProgressView()
                                    } else {
                                        Image(systemName: "plus.circle.fill")
                                    }
                                    Text("Tải thêm phim (\(service.searchResults.count)/\(service.searchTotal))")
                                        .font(.system(size: 18, weight: .bold))
                                }
                                .padding(.horizontal, 30)
                                .padding(.vertical, 14)
                                .background(fptOrange)
                                .foregroundColor(.black)
                                .cornerRadius(24)
                            }
                            .buttonStyle(FPTG2CardButtonStyle())
                            Spacer()
                        }
                    }
                } else {
                    g2VerticalPosterRail(
                        title: "Xu hướng tìm kiếm — Phim Lẻ & Galaxy Play",
                        items: Array(vodMoviesList.prefix(12))
                    )
                    g2VerticalPosterRail(
                        title: "Xu hướng tìm kiếm — Phim Bộ Đặc Sắc",
                        items: Array(vodSeriesList.prefix(12))
                    )
                }
            }
            .padding(.bottom, 64)
        }
    }

    private func searchFilterButton(id: String, label: String) -> some View {
        let isSel = (searchFilter == id)
        return Button {
            searchFilter = id
        } label: {
            Text(label)
                .font(.system(size: 15, weight: .bold))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSel ? fptOrange : Color.white.opacity(0.12))
                .foregroundColor(isSel ? .black : .white)
                .cornerRadius(16)
        }
        .buttonStyle(FPTG2CardButtonStyle())
    }

    // MARK: - 11. Màn Hình THƯ VIỆN & LỊCH SỬ XEM
    private var g2LibraryScreen: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                g2HeroSpotlightBanner(for: heroChannel ?? service.watchHistory.first?.channel, sectionLabel: "Thư Viện & Lịch Sử Xem")

                if !service.watchHistory.isEmpty {
                    g2WatchHistoryRail
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 46))
                            .foregroundColor(fptOrange)
                        Text("Chưa có lịch sử xem gần đây.")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding(.bottom, 64)
        }
    }

    // MARK: - Các Dải Ngang Tái Sử Dụng Chuẩn G2 (IHorizontalGridView)
    private var g2WatchHistoryRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Đang xem tiếp")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Button {
                    service.clearWatchHistory()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                        Text("Xóa lịch sử")
                    }
                    .font(.system(size: 14, weight: .bold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.10))
                    .foregroundColor(.gray)
                    .cornerRadius(8)
                }
                .buttonStyle(FPTG2CardButtonStyle())
            }
            .padding(.horizontal, 36)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 22) {
                    ForEach(service.watchHistory.prefix(12)) { item in
                        Button {
                            openWatchHistoryItem(item)
                        } label: {
                            FPTG2LandscapePosterCard(
                                channel: item.channel,
                                historyItem: item,
                                showTimePill: false
                            ) {
                                focusedChannel = item.channel
                            }
                        }
                        .buttonStyle(FPTG2CardButtonStyle())
                    }
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 8)
            }
        }
        .focusSection()
    }

    private func g2HorizontalLandscapeRail(
        title: String,
        items: [FPTChannel],
        showTimePill: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 36)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 22) {
                    ForEach(items) { item in
                        Button {
                            openChannel(item)
                        } label: {
                            FPTG2LandscapePosterCard(
                                channel: item,
                                historyItem: service.historyItem(forVodOrChannelId: item.isVod ? item.vodId : item.channelId),
                                showTimePill: showTimePill
                            ) {
                                focusedChannel = item
                            }
                        }
                        .buttonStyle(FPTG2CardButtonStyle())
                    }
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 8)
            }
        }
        .focusSection()
    }

    // Dải Poster Dọc 2:3 Chuẩn G2 (block__vertical.xml / block_item_vertical.xml: kèm dòng tiêu đề & thông tin động tv_main + ll_content bên dưới dải)
    private func g2VerticalPosterRail(
        title: String,
        items: [FPTChannel]
    ) -> some View {
        let activeInRail = items.first(where: { $0.id == focusedChannel?.id }) ?? items.first

        return VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(Color(red: 0.90, green: 0.90, blue: 0.90))
                .padding(.horizontal, 36)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    ForEach(items) { item in
                        Button {
                            openChannel(item)
                        } label: {
                            FPTG2VerticalPosterCard(
                                channel: item,
                                historyItem: service.historyItem(forVodOrChannelId: item.vodId),
                                showTitleBelow: false
                            ) {
                                focusedChannel = item
                            }
                        }
                        .buttonStyle(FPTG2CardButtonStyle())
                    }
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 10)
            }

            // Dòng tiêu đề & metadata động dưới dải Poster Dọc (chuẩn tv_main & ll_content trong block__vertical.xml trên G2)
            if let sel = activeInRail {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Text(sel.name)
                            .font(.system(size: 19, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Text(sel.isSeries ? "PHIM BỘ" : "PHIM LẺ")
                            .font(.system(size: 11, weight: .black))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(fptOrange.opacity(0.22))
                            .foregroundColor(fptOrange)
                            .cornerRadius(4)
                    }

                    HStack(spacing: 8) {
                        Text(sel.statusText)
                            .foregroundColor(fptOrange)
                        Text("•")
                        Text(sel.resolution)
                        Text("•")
                        Text(sel.fps)
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.65))
                    .lineLimit(1)
                }
                .padding(.horizontal, 36)
            }
        }
        .focusSection()
    }

    // Dải Bảng Xếp Hạng Top 10 Poster Dọc Kèm Số Thứ Tự Lớn 1..10 Bên Trái (chuẩn block__vertical_rank.xml / block_item_vertical_rank.xml trên G2)
    private func g2Top10VerticalRankedRail(
        title: String,
        items: [FPTChannel]
    ) -> some View {
        let rankedItems = Array(items.prefix(10).enumerated())
        let activeInRail = items.first(where: { $0.id == focusedChannel?.id }) ?? items.first

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(fptOrange)
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 36)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 28) {
                    ForEach(rankedItems, id: \.element.id) { idx, item in
                        Button {
                            openChannel(item)
                        } label: {
                            FPTG2VerticalRankedPosterCard(
                                rank: idx + 1,
                                channel: item,
                                historyItem: service.historyItem(forVodOrChannelId: item.vodId)
                            ) {
                                focusedChannel = item
                            }
                        }
                        .buttonStyle(FPTG2CardButtonStyle())
                    }
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 10)
            }

            if let sel = activeInRail {
                HStack(spacing: 10) {
                    Text(sel.name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text("•")
                        .foregroundColor(.gray)
                    Text(sel.statusText)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(fptOrange)
                    Text("•")
                        .foregroundColor(.gray)
                    Text(sel.resolution)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 36)
            }
        }
        .focusSection()
    }

    // Dải "Lịch thi đấu và kết quả" chuẩn dưới đáy screen-football.png (hgv_fr_cards)
    private func g2MatchScheduleCardsRail(items: [FPTChannel]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Lịch thi đấu và kết quả")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 36)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 22) {
                    ForEach(items) { ev in
                        Button {
                            openChannel(ev)
                        } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.white.opacity(0.12))
                                            .frame(width: 42, height: 42)
                                        Image(systemName: "trophy.fill")
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundColor(fptOrange)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ev.badge)
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        Text(ev.statusText)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.gray)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                }

                                Divider().background(Color.white.opacity(0.12))

                                Text(ev.name)
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)

                                HStack {
                                    Text(ev.isLive ? "🔴 ĐANG TRỰC TIẾP" : ev.statusText)
                                        .font(.system(size: 13, weight: .heavy))
                                        .foregroundColor(ev.isLive ? .red : fptOrange)
                                    Spacer()
                                    Text("Xem ngay ›")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.gray)
                                }
                            }
                            .padding(18)
                            .frame(width: 390, height: 158)
                            .background(Color(red: 0.14, green: 0.15, blue: 0.17))
                            .cornerRadius(14)
                        }
                        .buttonStyle(FPTG2CardButtonStyle())
                    }
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 8)
            }
        }
        .focusSection()
    }

    // MARK: - Điều Phối Mở Kênh / Sự Kiện / Phim Bộ / Phim Lẻ Chuẩn G2 (VodDetailFragment cho mọi phim VOD)
    private func openWatchHistoryItem(_ item: FPTWatchHistoryItem) {
        guard !isResolving else { return }
        if item.channel.isVod {
            isResolving = true
            resolvingName = item.channel.name
            Task {
                do {
                    let detail = try await service.fetchVodDetail(for: item.channel)
                    isResolving = false
                    autoPlayEpisodeOnOpen = item.episodeId.isEmpty ? (detail.episodes.first?.id ?? "0") : item.episodeId
                    activeVodDetail = detail
                } catch {
                    isResolving = false
                    errorMessage = error.localizedDescription
                }
            }
        } else {
            openChannel(item.channel, customResumeSeconds: item.lastPositionSeconds)
        }
    }

    private func openChannel(_ channel: FPTChannel, customResumeSeconds: Double? = nil) {
        guard !isResolving else { return }

        // Trên G2, khi bấm vào bất kỳ bộ phim nào (cả Phim Bộ lẫn Phim Lẻ / Galaxy Play) đều mở màn hình chi tiết phim VodDetailFragment (Xem ngay, Xem từ đầu, Trailer, Tập phim, Diễn viên, Nội dung tương tự)
        if channel.isVod {
            isResolving = true
            resolvingName = channel.name
            Task {
                do {
                    let detail = try await service.fetchVodDetail(for: channel)
                    isResolving = false
                    autoPlayEpisodeOnOpen = nil
                    activeVodDetail = detail
                } catch {
                    isResolving = false
                    errorMessage = error.localizedDescription
                }
            }
            return
        }

        isResolving = true
        resolvingName = channel.name
        let keyId = channel.isVod ? channel.vodId : channel.channelId
        let resumeSec = customResumeSeconds ?? service.historyItem(forVodOrChannelId: keyId)?.lastPositionSeconds ?? 0

        Task {
            do {
                let resolved = try await service.resolveStream(for: channel)
                isResolving = false
                activeStreamResumeSeconds = channel.isVod ? resumeSec : 0
                activeStream = resolved
            } catch {
                isResolving = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Sân Khấu Đa Giác Tối Góc Phải Cho Kênh Truyền Hình (giống hệt screen-menu.png & screen-back.png trên G2)
struct FPTG2PolygonalStageView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    FPTTheme.violet.opacity(0.55),
                    FPTTheme.accent2.opacity(0.30),
                    FPTTheme.bg
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )

            // Các mảng đa giác low-poly nhẹ đặc trưng của FPT Play Android TV
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                Path { p in
                    p.move(to: CGPoint(x: w * 0.25, y: 0))
                    p.addLine(to: CGPoint(x: w * 0.68, y: 0))
                    p.addLine(to: CGPoint(x: w * 0.48, y: h * 0.58))
                    p.closeSubpath()
                }
                .fill(Color.white.opacity(0.035))

                Path { p in
                    p.move(to: CGPoint(x: w * 0.68, y: 0))
                    p.addLine(to: CGPoint(x: w, y: h * 0.35))
                    p.addLine(to: CGPoint(x: w * 0.48, y: h * 0.58))
                    p.closeSubpath()
                }
                .fill(Color.black.opacity(0.18))

                Path { p in
                    p.move(to: CGPoint(x: w * 0.48, y: h * 0.58))
                    p.addLine(to: CGPoint(x: w, y: h * 0.35))
                    p.addLine(to: CGPoint(x: w * 0.85, y: h))
                    p.addLine(to: CGPoint(x: w * 0.30, y: h))
                    p.closeSubpath()
                }
                .fill(Color.white.opacity(0.025))
            }
        }
    }
}

// MARK: - Hiển Thị Logo Kênh Truyền Hình Kèm Fallback Tự Động Sang FPT Play CDN
struct FPTChannelLogoView: View {
    let channel: FPTChannel
    let maxWidth: CGFloat
    let maxHeight: CGFloat
    var fallbackFontSize: CGFloat = 16

    private var primaryUrl: URL? {
        let trimmed = channel.logo.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, let u = URL(string: trimmed) {
            return u
        }
        return fallbackUrl
    }

    private var fallbackUrl: URL? {
        let sec = channel.portraitLogo.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sec.isEmpty, let u = URL(string: sec) {
            return u
        }
        let cid = channel.channelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cid.isEmpty else { return nil }
        return URL(string: "https://images.fptplay53.net/media/channels/OTT_ECS/2026/07/10/\(cid).png")
    }

    var body: some View {
        if let pUrl = primaryUrl {
            AsyncImage(url: pUrl) { phase in
                switch phase {
                case .success(let img):
                    img
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: maxWidth, maxHeight: maxHeight)
                case .failure:
                    if let fUrl = fallbackUrl, fUrl != pUrl {
                        AsyncImage(url: fUrl) { subPhase in
                            if let subImg = subPhase.image {
                                subImg
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: maxWidth, maxHeight: maxHeight)
                            } else {
                                fallbackTextBadge
                            }
                        }
                    } else {
                        fallbackTextBadge
                    }
                default:
                    fallbackTextBadge
                }
            }
        } else {
            fallbackTextBadge
        }
    }

    private var fallbackTextBadge: some View {
        Text(channel.name)
            .font(.system(size: fallbackFontSize, weight: .bold))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .padding(.horizontal, 8)
            .frame(maxWidth: maxWidth, maxHeight: maxHeight)
    }
}

// MARK: - Ô Kênh Truyền Hình Gợi Ý Chuẩn G2 (screen-menu.png & screen-back.png: Nền xám đậm ánh tâm + Logo kênh + Tên kênh + Icon Timeshift góc dưới phải)
struct FPTG2TvChannelTile: View {
    let channel: FPTChannel
    var onFocused: (() -> Void)? = nil
    @Environment(\.isFocused) private var isFocused

    private let fptOrange = FPTTheme.accent

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.25, green: 0.20, blue: 0.42),
                            Color(red: 0.12, green: 0.10, blue: 0.22)
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 135
                    )
                )
                .frame(width: 245, height: 144)

            // Logo kênh chính giữa hơi nhích lên để nhường chỗ cho thanh tên kênh bên dưới
            FPTChannelLogoView(
                channel: channel,
                maxWidth: 162,
                maxHeight: 76,
                fallbackFontSize: 17
            )
            .offset(y: -12)

            // Nhãn VIP / Quốc tế hoặc HD ở góc trên bên trái
            VStack {
                HStack {
                    if channel.isDRM {
                        Text("VIP")
                            .font(.system(size: 10, weight: .black))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(fptOrange)
                            .foregroundColor(.black)
                            .cornerRadius(4)
                    }
                    Spacer()
                }
                Spacer()
                // Thanh đáy: Tên kênh bên trái + Đồng hồ xem lại 24/48 bên phải
                HStack(spacing: 6) {
                    Text(channel.name
                        .replacingOccurrences(of: " — Vĩnh Long 1", with: "")
                        .replacingOccurrences(of: " — Vĩnh Long 2", with: "")
                        .replacingOccurrences(of: " — Vĩnh Long 3", with: "")
                        .replacingOccurrences(of: " — Vĩnh Long 4", with: "")
                        .replacingOccurrences(of: " — Vĩnh Long 5", with: ""))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white.opacity(0.92))
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.75), lineWidth: 1.5)
                            .frame(width: 22, height: 22)
                        Text(channel.isDRM ? "24" : "48")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
            }
            .padding(10)
        }
        .frame(width: 245, height: 144)
        .onChange(of: isFocused) { newVal in
            if newVal {
                onFocused?()
            }
        }
    }
}

// MARK: - Ô Kênh Truyền Hình Trong Lưới Danh Mục (Kèm Logo + Nhãn Nhóm Kênh + Tên Kênh)
struct FPTG2TvChannelGridCard: View {
    let channel: FPTChannel
    var onFocused: (() -> Void)? = nil
    @Environment(\.isFocused) private var isFocused

    private let fptOrange = FPTTheme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.25, green: 0.20, blue: 0.42),
                                Color(red: 0.12, green: 0.10, blue: 0.22)
                            ],
                            center: .center,
                            startRadius: 12,
                            endRadius: 150
                        )
                    )
                    .frame(height: 152)

                FPTChannelLogoView(
                    channel: channel,
                    maxWidth: 184,
                    maxHeight: 84,
                    fallbackFontSize: 18
                )

                VStack {
                    HStack {
                        if channel.isDRM {
                            Text("VIP")
                                .font(.system(size: 10, weight: .black))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(fptOrange)
                                .foregroundColor(.black)
                                .cornerRadius(4)
                        }
                        Spacer()
                        if channel.is4K {
                            Text("4K")
                                .font(.system(size: 11, weight: .black))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(fptOrange)
                                .foregroundColor(.black)
                                .cornerRadius(4)
                        }
                    }
                    Spacer()
                    HStack {
                        Text(channel.badge)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.68))
                            .lineLimit(1)
                        Spacer()
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.70), lineWidth: 1.4)
                                .frame(width: 22, height: 22)
                            Text(channel.isDRM ? "24" : "48")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white.opacity(0.88))
                        }
                    }
                }
                .padding(10)
            }

            Text(channel.name)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(isFocused ? .white : .white.opacity(0.85))
                .lineLimit(1)
                .padding(.horizontal, 4)
        }
        .onChange(of: isFocused) { newVal in
            if newVal {
                onFocused?()
            }
        }
    }
}

// MARK: - Thẻ Poster 16:9 Ngang Chuẩn G2 (screen-football.png: Poster 16:9 tràn viền + Pill thời gian góc dưới trái + Badge 4K góc dưới phải)
struct FPTG2LandscapePosterCard: View {
    let channel: FPTChannel
    let historyItem: FPTWatchHistoryItem?
    let showTimePill: Bool
    var onFocused: (() -> Void)? = nil
    @Environment(\.isFocused) private var isFocused

    private let fptOrange = FPTTheme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(FPTTheme.surface)
                    .frame(width: 312, height: 176)

                if let url = URL(string: channel.logo), !channel.logo.isEmpty {
                    AsyncImage(url: url) { phase in
                        if let img = phase.image {
                            img
                                .resizable()
                                .scaledToFill()
                                .frame(width: 312, height: 176)
                                .clipped()
                                .cornerRadius(12)
                        } else {
                            fallbackPoster
                        }
                    }
                } else {
                    fallbackPoster
                }

                // Pill thời gian ở góc dưới bên trái & Badge 4K góc dưới phải (giống hệt screen-football.png trên G2!)
                HStack(alignment: .bottom) {
                    if let hist = historyItem {
                        Text(hist.progressLabel)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(0.84))
                            .cornerRadius(6)
                    } else if showTimePill || !channel.statusText.isEmpty {
                        Text(channel.statusText)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(red: 0.08, green: 0.08, blue: 0.09).opacity(0.88))
                            .cornerRadius(6)
                    }

                    Spacer()

                    if channel.is4K {
                        Text("4K")
                            .font(.system(size: 12, weight: .black))
                            .foregroundColor(Color(red: 0.95, green: 0.80, blue: 0.45))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.82))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color(red: 0.95, green: 0.80, blue: 0.45).opacity(0.6), lineWidth: 1)
                            )
                            .cornerRadius(4)
                    }
                }
                .padding(10)

                // Thanh tiến độ màu cam FPT dưới đáy nếu đang xem dở
                if let hist = historyItem, hist.durationSeconds > 0 {
                    let ratio = min(1.0, max(0.05, hist.lastPositionSeconds / hist.durationSeconds))
                    VStack {
                        Spacer()
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.white.opacity(0.28))
                                    .frame(height: 4)
                                Rectangle()
                                    .fill(fptOrange)
                                    .frame(width: geo.size.width * ratio, height: 4)
                            }
                        }
                        .frame(height: 4)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .frame(width: 312, height: 176)

            Text(channel.name)
                .font(.system(size: 16, weight: isFocused ? .bold : .medium))
                .foregroundColor(isFocused ? .white : .white.opacity(0.80))
                .lineLimit(1)
                .frame(width: 312, alignment: .leading)
        }
        .onChange(of: isFocused) { newVal in
            if newVal {
                onFocused?()
            }
        }
    }

    private var fallbackPoster: some View {
        VStack(spacing: 8) {
            Image("FPTLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 36)
            Text(channel.name)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 12)
        }
        .frame(width: 312, height: 176)
    }
}

// MARK: - Hàng Kênh Đánh Số Trong Bảng Kênh 3 Cột Chuẩn G2 (screen-dpad.png / live_item_channel.xml — Kèm Logo Kênh Sắc Nét)
struct FPTG2NumberedChannelRow: View {
    let number: Int
    let channel: FPTChannel
    var onFocused: (() -> Void)? = nil
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: 14) {
            Text(String(format: "%02d", number))
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundColor(isFocused ? Color(red: 0.08, green: 0.08, blue: 0.09) : Color.white.opacity(0.75))
                .frame(width: 40, alignment: .leading)

            // Khung Logo Kênh nền tối chống chói khi hàng chuyển sang nền trắng lúc Focus
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(FPTTheme.surface)
                    .frame(width: 78, height: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )

                FPTChannelLogoView(
                    channel: channel,
                    maxWidth: 64,
                    maxHeight: 34,
                    fallbackFontSize: 10
                )
            }

            Text(channel.name.replacingOccurrences(of: " — Vĩnh Long 1", with: "")
                .replacingOccurrences(of: " — Vĩnh Long 2", with: "")
                .replacingOccurrences(of: " — Vĩnh Long 3", with: "")
                .replacingOccurrences(of: " — Vĩnh Long 4", with: "")
                .replacingOccurrences(of: " — Vĩnh Long 5", with: ""))
                .font(.system(size: 19, weight: isFocused ? .bold : .medium))
                .foregroundColor(isFocused ? Color(red: 0.08, green: 0.08, blue: 0.09) : .white)
                .lineLimit(1)

            Spacer(minLength: 6)

            ZStack {
                Circle()
                    .stroke(isFocused ? Color.black.opacity(0.55) : Color.white.opacity(0.55), lineWidth: 1.5)
                    .frame(width: 26, height: 26)
                Text(channel.isDRM ? "24" : "48")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(isFocused ? .black : .white.opacity(0.85))
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 16)
        .frame(height: 66)
        .onChange(of: isFocused) { newVal in
            if newVal {
                onFocused?()
            }
        }
    }
}

// MARK: - Các ButtonStyle Chuẩn Giao Diện FPT Play Android TV (G2)
struct FPTG2CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FPTG2CardButtonWrapper(configuration: configuration)
    }

    private struct FPTG2CardButtonWrapper: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: isFocused ? [Color.white, FPTTheme.accent2.opacity(0.9)] : [Color.clear, Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 3
                        )
                )
                .scaleEffect(configuration.isPressed ? 0.97 : (isFocused ? 1.07 : 1.0))
                .shadow(color: isFocused ? FPTTheme.accent2.opacity(0.45) : Color.clear, radius: 22, x: 0, y: 0)
                .shadow(color: isFocused ? Color.black.opacity(0.55) : Color.clear, radius: 18, x: 0, y: 14)
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isFocused)
        }
    }
}

// Style cho hàng kênh đánh số trong screen-dpad.png: Khi focus có nền Trắng #F1F3F5 + vạch đứng Cam FPT #FF6500 dày 7pt bên phải!
struct FPTG2NumberedRowButtonStyle: ButtonStyle {
    let fptOrange: Color

    func makeBody(configuration: Configuration) -> some View {
        FPTG2NumberedRowWrapper(configuration: configuration, fptOrange: fptOrange)
    }

    private struct FPTG2NumberedRowWrapper: View {
        let configuration: Configuration
        let fptOrange: Color
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isFocused ? Color(red: 0.97, green: 0.96, blue: 1.0) : Color.white.opacity(0.08))
                )
                .overlay(alignment: .trailing) {
                    if isFocused {
                        Rectangle()
                            .fill(FPTTheme.accentGradient)
                            .frame(width: 8)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .scaleEffect(isFocused ? 1.02 : 1.0)
                .animation(.easeOut(duration: 0.14), value: isFocused)
        }
    }
}

struct FPTG2SidebarNavRow: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let fptOrange: Color
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: (isSelected || isFocused) ? .bold : .regular))
                .frame(width: 44)
                .foregroundColor(isFocused ? .white : (isSelected ? .white : Color.white.opacity(0.6)))

            Text(title)
                .font(.system(size: 23, weight: (isSelected || isFocused) ? .bold : .semibold, design: .rounded))
                .foregroundColor(isFocused ? .white : (isSelected ? .white : Color.white.opacity(0.6)))
                .lineLimit(1)
        }
        .padding(.horizontal, 20)
        .frame(width: 252, height: 80, alignment: .leading)
    }
}

struct FPTG2SidebarButtonStyle: ButtonStyle {
    let isSelected: Bool
    let fptOrange: Color

    func makeBody(configuration: Configuration) -> some View {
        Wrapper(configuration: configuration, isSelected: isSelected, fptOrange: fptOrange)
    }

    private struct Wrapper: View {
        let configuration: Configuration
        let isSelected: Bool
        let fptOrange: Color
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            isFocused
                                ? AnyShapeStyle(FPTTheme.accentGradient)
                                : AnyShapeStyle(isSelected ? Color.white.opacity(0.14) : Color.clear)
                        )
                )
                .shadow(color: isFocused ? FPTTheme.accent2.opacity(0.55) : Color.clear, radius: 14, x: 0, y: 4)
                .overlay(alignment: .leading) {
                    if isSelected && !isFocused {
                        Capsule()
                            .fill(FPTTheme.accentGradient)
                            .frame(width: 5, height: 40)
                    }
                }
                .scaleEffect(isFocused ? 1.06 : 1.0)
                .animation(.easeOut(duration: 0.14), value: isFocused)
        }
    }
}

struct FPTG2SidebarAvatarStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Wrapper(configuration: configuration)
    }

    private struct Wrapper: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isFocused ? Color.white.opacity(0.22) : Color.clear)
                )
                .shadow(color: isFocused ? FPTTheme.violet.opacity(0.6) : Color.clear, radius: 14, x: 0, y: 0)
                .scaleEffect(isFocused ? 1.08 : 1.0)
                .animation(.easeOut(duration: 0.14), value: isFocused)
        }
    }
}

// MARK: - Thẻ Poster Dọc 2:3 Chuẩn Phim Bộ & Phim Lẻ Trên G2 (block_item_vertical.xml: @dimen/_68sdp x @dimen/_101sdp)
struct FPTG2VerticalPosterCard: View {
    let channel: FPTChannel
    let historyItem: FPTWatchHistoryItem?
    var showTitleBelow: Bool = false
    var onFocused: (() -> Void)? = nil
    @Environment(\.isFocused) private var isFocused

    private let fptOrange = FPTTheme.accent

    private var posterUrlString: String {
        !channel.portraitLogo.isEmpty ? channel.portraitLogo : channel.logo
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(FPTTheme.surface)
                    .frame(width: 212, height: 316)

                if let url = URL(string: posterUrlString), !posterUrlString.isEmpty {
                    AsyncImage(url: url) { phase in
                        if let img = phase.image {
                            img
                                .resizable()
                                .scaledToFill()
                                .frame(width: 212, height: 316)
                                .clipped()
                                .cornerRadius(12)
                        } else {
                            fallbackVerticalPoster
                        }
                    }
                } else {
                    fallbackVerticalPoster
                }

                // Lớp phủ viền & huy hiệu chuẩn vt_ribbon_overlay + vt_playlist + vt_history trong block_item_vertical.xml
                VStack {
                    HStack {
                        Spacer()
                        // Nhãn góc trên bên phải (VIP / FPT PLAY / GALAXY PLAY)
                        Text(channel.badge.uppercased().contains("GALAXY") ? "GALAXY" : "FPT PLAY")
                            .font(.system(size: 10, weight: .black))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                LinearGradient(
                                    colors: [fptOrange, Color(red: 0.90, green: 0.22, blue: 0.0)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    }
                    .padding(8)

                    Spacer()

                    // Nhãn số tập / trạng thái ở góc dưới bên phải (vt_playlist)
                    HStack {
                        Spacer()
                        if let hist = historyItem {
                            Text(hist.progressLabel)
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.84))
                                .foregroundColor(fptOrange)
                                .cornerRadius(5)
                        } else if !channel.statusText.isEmpty {
                            Text(channel.statusText)
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.82))
                                .foregroundColor(.white)
                                .cornerRadius(5)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, historyItem != nil ? 10 : 8)

                    // Thanh tiến độ xem màu cam dưới đáy (vt_history / block_item_progress)
                    if let hist = historyItem, hist.durationSeconds > 0 {
                        let ratio = min(1.0, max(0.06, hist.lastPositionSeconds / hist.durationSeconds))
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.white.opacity(0.28))
                                    .frame(height: 4)
                                Rectangle()
                                    .fill(fptOrange)
                                    .frame(width: geo.size.width * ratio, height: 4)
                            }
                        }
                        .frame(height: 4)
                    }
                }
                .frame(width: 212, height: 316)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .frame(width: 212, height: 316)

            if showTitleBelow {
                Text(channel.name)
                    .font(.system(size: 16, weight: isFocused ? .bold : .medium))
                    .foregroundColor(isFocused ? .white : Color.white.opacity(0.82))
                    .lineLimit(1)
                    .frame(width: 212, alignment: .leading)
            }
        }
        .onChange(of: isFocused) { newVal in
            if newVal {
                onFocused?()
            }
        }
    }

    private var fallbackVerticalPoster: some View {
        VStack(spacing: 10) {
            Image("FPTLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 36)
            Text(channel.name)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 12)
        }
        .frame(width: 212, height: 316)
    }
}

// MARK: - Thẻ Bảng Xếp Hạng Top 10 Poster Dọc Kèm Số Thứ Tự Lớn Bên Trái Chuẩn G2 (block_item_vertical_rank.xml)
struct FPTG2VerticalRankedPosterCard: View {
    let rank: Int
    let channel: FPTChannel
    let historyItem: FPTWatchHistoryItem?
    var onFocused: (() -> Void)? = nil
    @Environment(\.isFocused) private var isFocused

    private let fptOrange = FPTTheme.accent

    var body: some View {
        HStack(alignment: .bottom, spacing: -14) {
            // Số thứ tự lớn (iv_rank @dimen/_43sdp x @dimen/_35sdp căn đáy bên trái)
            Text("\(rank)")
                .font(.system(size: 110, weight: .black, design: .rounded))
                .italic()
                .foregroundStyle(
                    LinearGradient(
                        colors: rank <= 3
                            ? [fptOrange, Color(red: 1.0, green: 0.78, blue: 0.25), fptOrange.opacity(0.25)]
                            : [Color.white.opacity(0.92), Color.white.opacity(0.45), Color.white.opacity(0.12)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: .black.opacity(0.85), radius: 8, x: 2, y: 4)
                .frame(width: rank == 10 ? 118 : 84, alignment: .trailing)
                .padding(.bottom, -10)
                .zIndex(0)

            FPTG2VerticalPosterCard(
                channel: channel,
                historyItem: historyItem,
                showTitleBelow: false,
                onFocused: onFocused
            )
            .zIndex(1)
        }
        .onChange(of: isFocused) { newVal in
            if newVal {
                onFocused?()
            }
        }
    }
}

// MARK: - Style Nút Bấm Hình Viên Nhộng Chuẩn Trang Chi Tiết Phim G2 (vod_button_control_circle.xml: Chưa chọn #393A3C chữ #E5E5E5 -> Khi Focus nền Trắng #E5E5E5 chữ Đen #131314)
struct FPTG2VodActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Wrapper(configuration: configuration)
    }

    private struct Wrapper: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 26)
                .padding(.vertical, 13)
                .background(
                    Capsule()
                        .fill(
                            isFocused
                                ? AnyShapeStyle(FPTTheme.accentGradient)
                                : AnyShapeStyle(.ultraThinMaterial)
                        )
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(isFocused ? 0.0 : 0.18), lineWidth: 1)
                )
                .scaleEffect(configuration.isPressed ? 0.97 : (isFocused ? 1.08 : 1.0))
                .shadow(color: isFocused ? FPTTheme.accent2.opacity(0.55) : Color.clear, radius: 18, x: 0, y: 6)
                .animation(.easeOut(duration: 0.14), value: isFocused)
        }
    }
}

// MARK: - Style Nút Chọn Nhóm Tập Chuẩn G2 (vod_episode_group_background_item_v2.xml)
struct FPTG2EpisodeGroupPillStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        Wrapper(configuration: configuration, isSelected: isSelected)
    }

    private struct Wrapper: View {
        let configuration: Configuration
        let isSelected: Bool
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor((isFocused || isSelected) ? FPTTheme.bg : Color(red: 0.92, green: 0.92, blue: 0.96))
                .padding(.horizontal, 22)
                .padding(.vertical, 9)
                .background(
                    Capsule()
                        .fill(isFocused ? Color.white : (isSelected ? Color(red: 0.90, green: 0.90, blue: 0.90) : Color.clear))
                )
                .scaleEffect(isFocused ? 1.04 : 1.0)
                .animation(.easeOut(duration: 0.14), value: isFocused)
        }
    }
}

// MARK: - Thẻ Tập Phim 16:9 Kèm Tóm Tắt Tập Chuẩn G2 (vod_item_episode_preview_v2.xml: @dimen/_107sdp x @dimen/_60sdp + tv_title + tv_des 3 dòng)
struct FPTG2EpisodePreviewCard: View {
    let episode: FPTEpisode
    let fallbackPoster: String
    let isCurrent: Bool
    let watchProgressRatio: Double?
    @Environment(\.isFocused) private var isFocused

    private let fptOrange = FPTTheme.accent

    private var thumbUrlString: String {
        !episode.thumb.isEmpty ? episode.thumb : fallbackPoster
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(FPTTheme.surface)
                    .frame(width: 316, height: 178)

                if let url = URL(string: thumbUrlString), !thumbUrlString.isEmpty {
                    AsyncImage(url: url) { phase in
                        if let img = phase.image {
                            img
                                .resizable()
                                .scaledToFill()
                                .frame(width: 316, height: 178)
                                .clipped()
                                .cornerRadius(10)
                        }
                    }
                }

                // Lớp thông tin trên ảnh tập (iv_vip góc trên trái + tv_duration góc dưới trái + pb_history đáy ảnh)
                VStack {
                    HStack {
                        if isCurrent {
                            Text("▶ ĐANG CHỌN")
                                .font(.system(size: 11, weight: .black))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(fptOrange)
                                .foregroundColor(.black)
                                .cornerRadius(4)
                        } else if episode.isVip {
                            Text("VIP")
                                .font(.system(size: 11, weight: .black))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(fptOrange)
                                .foregroundColor(.white)
                                .cornerRadius(4)
                        }
                        Spacer()
                    }
                    .padding(8)

                    Spacer()

                    HStack {
                        if !episode.durationText.isEmpty {
                            Text(episode.durationText)
                                .font(.system(size: 12, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.82))
                                .foregroundColor(.white)
                                .cornerRadius(4)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, watchProgressRatio != nil ? 10 : 8)

                    if let ratio = watchProgressRatio {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.white.opacity(0.28))
                                    .frame(height: 4)
                                Rectangle()
                                    .fill(fptOrange)
                                    .frame(width: geo.size.width * min(1.0, max(0.08, ratio)), height: 4)
                            }
                        }
                        .frame(height: 4)
                    }
                }
                .frame(width: 316, height: 178)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isFocused ? Color.white : (isCurrent ? fptOrange : Color.clear), lineWidth: isFocused ? 3.0 : 2.0)
            )

            // Tiêu đề tập (tv_title)
            Text(episode.title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(isCurrent ? fptOrange : Color(red: 0.90, green: 0.90, blue: 0.90))
                .lineLimit(1)
                .frame(width: 316, alignment: .leading)

            // Mô tả ngắn của tập (tv_des maxLines=3 trong vod_item_episode_preview_v2.xml)
            if !episode.desc.isEmpty {
                Text(episode.desc)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.62))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(width: 316, alignment: .leading)
            }
        }
        .frame(width: 316, alignment: .topLeading)
    }
}

// MARK: - Màn Hình Chi Tiết Bộ Phim & Chọn Tập Chuẩn FPT Play Android TV (G2 - vod_detail_fragment.xml + vod_detail_item_v2.xml + vod_detail_block_episode_v2.xml + vod_detail_block_actor.xml + block__horizontal_detail_v2.xml)
struct FPTVodDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var service = FPTService.shared

    let detail: FPTVodDetail
    let initialAutoPlayEpisodeId: String?
    let onOpenAuth: () -> Void

    @State private var currentDetail: FPTVodDetail? = nil
    @State private var activeSession: FPTVodPlaybackSession? = nil
    @State private var currentEpisodeId: String = "0"
    @State private var selectedGroupIndex: Int = 0
    @State private var isResolvingEp: Bool = false
    @State private var resolvingEpTitle: String = ""
    @State private var sheetError: String? = nil
    @State private var didRunInitialAutoPlay: Bool = false
    @State private var isFollowed: Bool = false
    @State private var showFullDescriptionDialog: Bool = false

    private let g2Bg = FPTTheme.bg
    private let fptOrange = FPTTheme.accent
    private let groupChunkSize = 20

    private var activeDetail: FPTVodDetail {
        currentDetail ?? detail
    }

    private var savedHistory: FPTWatchHistoryItem? {
        service.historyItem(forVodOrChannelId: activeDetail.vodId)
    }

    private var currentEpisode: FPTEpisode {
        let targetId = !currentEpisodeId.isEmpty ? currentEpisodeId : (savedHistory?.episodeId ?? activeDetail.episodes.first?.id ?? "0")
        return activeDetail.episodes.first(where: { $0.id == targetId }) ?? activeDetail.episodes.first ?? FPTEpisode(id: "0", title: "Tập 1")
    }

    private var nextEpisode: FPTEpisode? {
        guard let idx = activeDetail.episodes.firstIndex(where: { $0.id == currentEpisode.id }),
              idx + 1 < activeDetail.episodes.count else {
            return nil
        }
        return activeDetail.episodes[idx + 1]
    }

    private var episodeGroups: [(label: String, episodes: [FPTEpisode])] {
        let total = activeDetail.episodes.count
        guard total > groupChunkSize else {
            return [("Tập 1 - \(total)", activeDetail.episodes)]
        }
        var groups: [(String, [FPTEpisode])] = []
        var start = 0
        while start < total {
            let end = min(start + groupChunkSize, total)
            let slice = Array(activeDetail.episodes[start..<end])
            groups.append(("Tập \(start + 1) - \(end)", slice))
            start = end
        }
        return groups
    }

    private var infoBulletTokens: [String] {
        var tokens: [String] = []
        tokens.append(activeDetail.isSeries ? "Phim bộ" : "Phim lẻ")
        for m in activeDetail.metaData {
            if !tokens.contains(m) {
                tokens.append(m)
            }
        }
        if !activeDetail.yearText.isEmpty && !tokens.contains(activeDetail.yearText) {
            tokens.append(activeDetail.yearText)
        }
        if !activeDetail.country.isEmpty && !tokens.contains(activeDetail.country) {
            tokens.append(activeDetail.country)
        }
        if !activeDetail.ageRating.isEmpty && !tokens.contains(activeDetail.ageRating) {
            tokens.append(activeDetail.ageRating)
        }
        if activeDetail.isSeries {
            let epText = "\(activeDetail.episodes.count) tập"
            if !tokens.contains(where: { $0.lowercased().contains("tập") }) {
                tokens.append(epText)
            }
        }
        tokens.append("FHD / 4K")
        return tokens
    }

    var body: some View {
        ZStack {
            FPTGlassBackdrop()

            // Lớp nền 16:9 cố định toàn màn hình phía sau (vt_banner + vod_detail_background_item_v2.xml trên G2)
            GeometryReader { geo in
                ZStack(alignment: .topTrailing) {
                    if let url = URL(string: activeDetail.poster), !activeDetail.poster.isEmpty {
                        AsyncImage(url: url) { phase in
                            if let img = phase.image {
                                img
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: geo.size.width * 0.72, height: geo.size.height * 0.76)
                                    .clipped()
                            } else {
                                FPTG2PolygonalStageView()
                                    .frame(width: geo.size.width * 0.72, height: geo.size.height * 0.76)
                            }
                        }
                    } else {
                        FPTG2PolygonalStageView()
                            .frame(width: geo.size.width * 0.72, height: geo.size.height * 0.76)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .overlay(
                    // Gradient ngang từ #131314 bên trái sang trong suốt bên phải
                    LinearGradient(
                        stops: [
                            .init(color: g2Bg, location: 0.0),
                            .init(color: g2Bg.opacity(0.95), location: 0.34),
                            .init(color: g2Bg.opacity(0.50), location: 0.65),
                            .init(color: g2Bg.opacity(0.12), location: 1.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(
                    // Gradient dọc từ trong suốt phía trên xuống #131314 phía dưới
                    LinearGradient(
                        stops: [
                            .init(color: Color.clear, location: 0.0),
                            .init(color: g2Bg.opacity(0.45), location: 0.48),
                            .init(color: g2Bg.opacity(0.94), location: 0.72),
                            .init(color: g2Bg, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .ignoresSafeArea()

            // Lưới cuộn dọc chính (IVerticalGridView vgv_item trong vod_detail_fragment.xml trên G2)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 34) {
                    // 1. Khối Thông Tin Phim & Cụm Nút Điều Khiển (vod_detail_item_v2.xml)
                    VStack(alignment: .leading, spacing: 14) {
                        // Logo nghệ thuật của phim (iv_title) hoặc Tên phim chữ lớn (tv_title)
                        if !activeDetail.titleLogo.isEmpty, let tUrl = URL(string: activeDetail.titleLogo) {
                            AsyncImage(url: tUrl) { phase in
                                if let img = phase.image {
                                    img
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxWidth: 480, maxHeight: 92, alignment: .leading)
                                } else {
                                    Text(activeDetail.title)
                                        .font(.system(size: 42, weight: .heavy))
                                        .foregroundColor(.white)
                                        .lineLimit(2)
                                        .frame(maxWidth: 780, alignment: .leading)
                                }
                            }
                        } else {
                            Text(activeDetail.title)
                                .font(.system(size: 42, weight: .heavy))
                                .foregroundColor(.white)
                                .lineLimit(2)
                                .frame(maxWidth: 780, alignment: .leading)
                        }

                        // Phụ đề ngắn / Tên tiếng Anh (tv_short_des)
                        if !activeDetail.shortDesc.isEmpty && activeDetail.shortDesc != activeDetail.title {
                            Text(activeDetail.shortDesc)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(Color(red: 0.90, green: 0.90, blue: 0.90))
                                .lineLimit(1)
                                .frame(maxWidth: 740, alignment: .leading)
                        }

                        // Dòng thông tin tổng hợp ngăn cách bằng dấu • (ll_infor)
                        HStack(spacing: 8) {
                            ForEach(Array(infoBulletTokens.enumerated()), id: \.offset) { idx, token in
                                if idx > 0 {
                                    Text("•")
                                        .foregroundColor(Color.white.opacity(0.45))
                                }
                                Text(token)
                                    .foregroundColor(idx == 0 ? fptOrange : Color(red: 0.90, green: 0.90, blue: 0.90))
                            }
                        }
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1)

                        // Khung mô tả 3 dòng có thể bấm vào để xem toàn bộ nội dung & diễn viên (tv_des + item_vod_des_background.xml -> VodInfoAndDescriptionDialog)
                        Button {
                            showFullDescriptionDialog = true
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(activeDetail.desc.isEmpty ? "Phim bản quyền phát sóng trên FPT Play. Hỗ trợ Thuyết minh & Phụ đề Tiếng Việt." : activeDetail.desc)
                                    .font(.system(size: 17, weight: .regular))
                                    .foregroundColor(Color(red: 0.90, green: 0.90, blue: 0.90))
                                    .lineLimit(3)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: 740, alignment: .leading)

                                HStack(spacing: 6) {
                                    Image(systemName: "info.circle")
                                    Text("Bấm để xem đầy đủ nội dung & thông tin diễn viên")
                                }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(fptOrange)
                            }
                            .padding(12)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(8)
                        }
                        .buttonStyle(FPTG2CardButtonStyle())

                        // Dòng thể loại phim (ll_type: Tâm lý • Tình cảm • Cổ trang...)
                        if !activeDetail.genres.isEmpty {
                            HStack(spacing: 8) {
                                Text("Thể loại:")
                                    .foregroundColor(.gray)
                                Text(activeDetail.genres.joined(separator: " • "))
                                    .foregroundColor(Color(red: 0.90, green: 0.90, blue: 0.90))
                            }
                            .font(.system(size: 16, weight: .medium))
                            .lineLimit(1)
                        }

                        // Thanh tiến độ xem màu cam FPT (pb_history @dimen/_185sdp x @dimen/_2sdp)
                        if let hist = savedHistory, hist.lastPositionSeconds >= 10 {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Đang xem: \(hist.progressLabel)")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(fptOrange)
                                let ratio = hist.durationSeconds > 0 ? min(1.0, max(0.08, hist.lastPositionSeconds / hist.durationSeconds)) : 0.35
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.white.opacity(0.22)).frame(width: 520, height: 5)
                                    Capsule().fill(fptOrange).frame(width: 520 * ratio, height: 5)
                                }
                            }
                        }

                        // Cụm nút điều khiển viên nhộng chuẩn f_button trong vod_detail_item_v2.xml (Nền #393A3C -> Khi Focus nền Trắng #E5E5E5 chữ Đen #131314)
                        HStack(spacing: 16) {
                            // Nút 1: bt_play (Xem ngay / Xem tiếp)
                            Button {
                                let resumeSec = (savedHistory?.episodeId == currentEpisode.id) ? (savedHistory?.lastPositionSeconds ?? 0) : 0
                                startEpisodePlayback(currentEpisode, resumeSeconds: resumeSec)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "play.fill")
                                    if let hist = savedHistory, hist.episodeId == currentEpisode.id, hist.lastPositionSeconds >= 10 {
                                        Text(activeDetail.isSeries ? "Xem tiếp \(currentEpisode.title)" : "Xem tiếp")
                                    } else {
                                        Text(activeDetail.isSeries ? "Xem ngay \(currentEpisode.title)" : "Xem ngay")
                                    }
                                }
                            }
                            .buttonStyle(FPTG2VodActionButtonStyle())

                            // Nút 2: bt_replay (Xem từ đầu — chuẩn text_replay_v2 trên G2)
                            if (savedHistory?.lastPositionSeconds ?? 0) >= 10 || (activeDetail.isSeries && currentEpisode.id != activeDetail.episodes.first?.id) {
                                Button {
                                    if let firstEp = activeDetail.episodes.first {
                                        startEpisodePlayback(firstEp, resumeSeconds: 0)
                                    }
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "arrow.counterclockwise")
                                        Text("Xem từ đầu")
                                    }
                                }
                                .buttonStyle(FPTG2VodActionButtonStyle())
                            }

                            // Nút 3: Tập tiếp theo (cho Phim bộ nhiều tập)
                            if let nxt = nextEpisode {
                                Button {
                                    startEpisodePlayback(nxt, resumeSeconds: 0)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "forward.end.fill")
                                        Text("Tập tiếp: \(nxt.title)")
                                    }
                                }
                                .buttonStyle(FPTG2VodActionButtonStyle())
                            }

                            // Nút 4: Trailer (nếu có)
                            if !activeDetail.trailerUrl.isEmpty {
                                Button {
                                    let trailerStream = FPTResolvedStream(
                                        ok: true,
                                        channelId: activeDetail.vodId,
                                        eventId: "trailer",
                                        title: "\(activeDetail.title) (Trailer)",
                                        hlsUrl: activeDetail.trailerUrl,
                                        fallbackHlsUrl: nil,
                                        hls4KUrl: nil,
                                        hlsH264Url: activeDetail.trailerUrl,
                                        is4K: false,
                                        mediaHeaders: nil,
                                        drm: nil
                                    )
                                    activeSession = FPTVodPlaybackSession(
                                        detail: activeDetail,
                                        episode: FPTEpisode(id: "trailer", title: "Trailer"),
                                        resolved: trailerStream,
                                        resumeSeconds: 0
                                    )
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "film")
                                        Text("Trailer")
                                    }
                                }
                                .buttonStyle(FPTG2VodActionButtonStyle())
                            }

                            // Nút 5: bt_follow (Theo dõi — chuẩn vod_detail_item_v2.xml trên G2)
                            Button {
                                isFollowed.toggle()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: isFollowed ? "heart.fill" : "heart")
                                        .foregroundColor(isFollowed ? fptOrange : nil)
                                    Text(isFollowed ? "Đã theo dõi" : "Theo dõi")
                                }
                            }
                            .buttonStyle(FPTG2VodActionButtonStyle())

                            // Nút 6: Quay lại
                            Button {
                                dismiss()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "chevron.backward")
                                    Text("Quay lại")
                                }
                            }
                            .buttonStyle(FPTG2VodActionButtonStyle())
                        }
                        .padding(.top, 8)
                    }
                    .padding(.top, 46)
                    .padding(.horizontal, 56)

                    // 2. Khối Danh Sách Tập Cuộn Ngang & Thanh Nhóm Tập Bên Dưới (chuẩn vod_detail_block_episode_v2.xml + vod_item_episode_preview_v2.xml trên G2)
                    VStack(alignment: .leading, spacing: 18) {
                        Text(activeDetail.isSeries ? "Danh sách tập (\(activeDetail.episodes.count) tập)" : "Bản phát sóng (\(activeDetail.episodes.count) phần)")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(Color(red: 0.90, green: 0.90, blue: 0.90))
                            .padding(.horizontal, 56)

                        let safeIdx = min(max(0, selectedGroupIndex), max(0, episodeGroups.count - 1))
                        let visibleEps = episodeGroups.isEmpty ? activeDetail.episodes : episodeGroups[safeIdx].episodes

                        // Dải cuộn ngang thẻ tập phim 16:9 (hgv_item trong vod_detail_block_episode_v2.xml)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 22) {
                                ForEach(visibleEps) { ep in
                                    let isCurrent = (ep.id == currentEpisode.id)
                                    let epProgress: Double? = {
                                        guard let hist = savedHistory, hist.episodeId == ep.id, hist.durationSeconds > 0 else { return nil }
                                        return hist.lastPositionSeconds / hist.durationSeconds
                                    }()

                                    Button {
                                        let resumeSec = (savedHistory?.episodeId == ep.id) ? (savedHistory?.lastPositionSeconds ?? 0) : 0
                                        startEpisodePlayback(ep, resumeSeconds: resumeSec)
                                    } label: {
                                        FPTG2EpisodePreviewCard(
                                            episode: ep,
                                            fallbackPoster: activeDetail.poster,
                                            isCurrent: isCurrent,
                                            watchProgressRatio: epProgress
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 56)
                            .padding(.vertical, 8)
                        }

                        // Thanh chọn nhóm tập (Tập 1 - 20, Tập 21 - 40...) nằm NGAY BÊN DƯỚI dải tập (ll_group_episode / vod_background_episode_group.xml trên G2)
                        if episodeGroups.count > 1 {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(Array(episodeGroups.enumerated()), id: \.offset) { idx, grp in
                                        Button {
                                            selectedGroupIndex = idx
                                        } label: {
                                            Text(grp.label)
                                        }
                                        .buttonStyle(FPTG2EpisodeGroupPillStyle(isSelected: selectedGroupIndex == idx))
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .stroke(Color.white.opacity(0.14), lineWidth: 2)
                                        .background(Capsule().fill(Color.white.opacity(0.04)))
                                )
                                .padding(.horizontal, 56)
                            }
                        }
                    }

                    // 3. Khối Diễn Viên & Đạo Diễn Chuẩn G2 (vod_detail_block_actor.xml — Dải Avatar Tròn)
                    if !activeDetail.actors.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Diễn viên & Đạo diễn")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(Color(red: 0.90, green: 0.90, blue: 0.90))
                                .padding(.horizontal, 56)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 28) {
                                    ForEach(activeDetail.actors) { actor in
                                        Button {
                                            showFullDescriptionDialog = true
                                        } label: {
                                            VStack(spacing: 10) {
                                                ZStack {
                                                    Circle()
                                                        .fill(Color(red: 0.18, green: 0.19, blue: 0.22))
                                                        .frame(width: 104, height: 104)

                                                    if let url = URL(string: actor.avatar), !actor.avatar.isEmpty {
                                                        AsyncImage(url: url) { phase in
                                                            if let img = phase.image {
                                                                img
                                                                    .resizable()
                                                                    .scaledToFill()
                                                                    .frame(width: 104, height: 104)
                                                                    .clipShape(Circle())
                                                            } else {
                                                                Image(systemName: "person.fill")
                                                                    .font(.system(size: 36))
                                                                    .foregroundColor(.gray)
                                                            }
                                                        }
                                                    } else {
                                                        Image(systemName: "person.fill")
                                                            .font(.system(size: 36))
                                                            .foregroundColor(.gray)
                                                    }
                                                }

                                                Text(actor.name)
                                                    .font(.system(size: 16, weight: .bold))
                                                    .foregroundColor(.white)
                                                    .lineLimit(1)
                                                    .frame(width: 130)

                                                Text(actor.role)
                                                    .font(.system(size: 13, weight: .medium))
                                                    .foregroundColor(.gray)
                                                    .lineLimit(1)
                                                    .frame(width: 130)
                                            }
                                        }
                                        .buttonStyle(FPTG2CardButtonStyle())
                                    }
                                }
                                .padding(.horizontal, 56)
                                .padding(.vertical, 8)
                            }
                        }
                    }

                    // 4. Khối Nội Dung Tương Tự / Phim Đề Xuất Chuẩn G2 (block__horizontal_detail_v2.xml)
                    if !activeDetail.relatedVods.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Nội dung tương tự")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(Color(red: 0.90, green: 0.90, blue: 0.90))
                                .padding(.horizontal, 56)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 24) {
                                    ForEach(activeDetail.relatedVods) { rel in
                                        Button {
                                            switchToRelatedVod(rel)
                                        } label: {
                                            FPTG2VerticalPosterCard(
                                                channel: rel,
                                                historyItem: service.historyItem(forVodOrChannelId: rel.vodId),
                                                showTitleBelow: true
                                            )
                                        }
                                        .buttonStyle(FPTG2CardButtonStyle())
                                    }
                                }
                                .padding(.horizontal, 56)
                                .padding(.vertical, 10)
                            }
                        }
                    }
                }
                .padding(.bottom, 72)
            }

            // Hộp thoại Xem đầy đủ Nội dung & Diễn viên chuẩn VodInfoAndDescriptionDialog trên G2
            if showFullDescriptionDialog {
                ZStack {
                    Color.black.opacity(0.84).ignoresSafeArea()

                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Text(activeDetail.title)
                                .font(.system(size: 36, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                            Spacer()
                            Button {
                                showFullDescriptionDialog = false
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "xmark.circle.fill")
                                    Text("Đóng")
                                }
                            }
                            .buttonStyle(FPTG2VodActionButtonStyle())
                        }

                        HStack(spacing: 10) {
                            ForEach(Array(infoBulletTokens.enumerated()), id: \.offset) { idx, token in
                                if idx > 0 {
                                    Text("•").foregroundColor(.gray)
                                }
                                Text(token).foregroundColor(idx == 0 ? fptOrange : .white)
                            }
                        }
                        .font(.system(size: 17, weight: .semibold))

                        Divider().background(Color.white.opacity(0.15))

                        ScrollView(.vertical, showsIndicators: true) {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("TÓM TẮT NỘI DUNG")
                                    .font(.system(size: 15, weight: .heavy))
                                    .foregroundColor(fptOrange)

                                Text(activeDetail.desc)
                                    .font(.system(size: 20, weight: .regular))
                                    .foregroundColor(.white.opacity(0.92))
                                    .lineSpacing(6)

                                if !activeDetail.genres.isEmpty {
                                    Text("Thể loại: \(activeDetail.genres.joined(separator: ", "))")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundColor(.gray)
                                        .padding(.top, 6)
                                }

                                if !activeDetail.actors.isEmpty {
                                    Text("DIỄN VIÊN & ĐẠO DIỄN")
                                        .font(.system(size: 15, weight: .heavy))
                                        .foregroundColor(fptOrange)
                                        .padding(.top, 8)

                                    Text(activeDetail.actors.map { $0.name }.joined(separator: ", "))
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundColor(.white)
                                }
                            }
                        }
                    }
                    .padding(42)
                    .frame(width: 1060, height: 640)
                    .background(Color(red: 0.11, green: 0.115, blue: 0.13))
                    .cornerRadius(22)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1.5)
                    )
                }
            }

            if isResolvingEp {
                ZStack {
                    Color.black.opacity(0.75).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView().scaleEffect(1.6)
                        Text("Đang mở \(resolvingEpTitle)...")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(36)
                    .background(Color(red: 0.11, green: 0.12, blue: 0.14))
                    .cornerRadius(18)
                }
            }
        }
        .onAppear {
            configureInitialEpisodeSelection(for: activeDetail)

            if !didRunInitialAutoPlay, let autoEpId = initialAutoPlayEpisodeId, !autoEpId.isEmpty {
                didRunInitialAutoPlay = true
                if let ep = activeDetail.episodes.first(where: { $0.id == autoEpId }) ?? activeDetail.episodes.first {
                    let resumeSec = (savedHistory?.episodeId == ep.id) ? (savedHistory?.lastPositionSeconds ?? 0) : 0
                    startEpisodePlayback(ep, resumeSeconds: resumeSec)
                }
            }
        }
        .fullScreenCover(item: $activeSession) { session in
            FPTPlayerView(
                resolved: session.resolved,
                vodDetail: session.detail,
                initialEpisode: session.episode,
                resumeSeconds: session.resumeSeconds,
                onEpisodeChanged: { newEp in
                    currentEpisodeId = newEp.id
                    if let epIdx = activeDetail.episodes.firstIndex(where: { $0.id == newEp.id }) {
                        selectedGroupIndex = epIdx / groupChunkSize
                    }
                }
            )
            .ignoresSafeArea()
        }
        .alert("Thông Báo Phát Phim", isPresented: Binding(
            get: { sheetError != nil },
            set: { if !$0 { sheetError = nil } }
        )) {
            Button("Đăng Nhập / Đổi Tài Khoản") {
                onOpenAuth()
            }
            Button("Đóng", role: .cancel) {}
        } message: {
            Text(sheetError ?? "")
        }
    }

    private func configureInitialEpisodeSelection(for target: FPTVodDetail) {
        if let savedEp = service.historyItem(forVodOrChannelId: target.vodId)?.episodeId, !savedEp.isEmpty {
            currentEpisodeId = savedEp
            if let epIdx = target.episodes.firstIndex(where: { $0.id == savedEp }) {
                selectedGroupIndex = epIdx / groupChunkSize
            } else {
                selectedGroupIndex = 0
            }
        } else if let firstId = target.episodes.first?.id {
            currentEpisodeId = firstId
            selectedGroupIndex = 0
        }
    }

    private func switchToRelatedVod(_ relChannel: FPTChannel) {
        guard !isResolvingEp else { return }
        isResolvingEp = true
        resolvingEpTitle = relChannel.name
        Task {
            do {
                let newDetail = try await service.fetchVodDetail(for: relChannel)
                isResolvingEp = false
                currentDetail = newDetail
                configureInitialEpisodeSelection(for: newDetail)
            } catch {
                isResolvingEp = false
                sheetError = error.localizedDescription
            }
        }
    }

    private func startEpisodePlayback(_ ep: FPTEpisode, resumeSeconds: Double) {
        guard !isResolvingEp else { return }
        currentEpisodeId = ep.id
        isResolvingEp = true
        resolvingEpTitle = "\(activeDetail.title) — \(ep.title)"

        Task {
            do {
                let resolved = try await service.resolveVodEpisode(vodDetail: activeDetail, episode: ep)
                isResolvingEp = false
                activeSession = FPTVodPlaybackSession(
                    detail: activeDetail,
                    episode: ep,
                    resolved: resolved,
                    resumeSeconds: resumeSeconds
                )
            } catch {
                isResolvingEp = false
                sheetError = error.localizedDescription
            }
        }
    }
}
