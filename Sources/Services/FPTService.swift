//
//  FPTService.swift
//  FTVOS (Apple TV / tvOS)
//
//  Điều phối chế độ Độc Lập 100% Trên Apple TV:
//  - Khởi tạo trực tiếp trên Apple TV (không đồng bộ ngầm từ Laptop để tránh khóa cứng tài khoản cũ)
//  - Hỗ trợ Đăng nhập Số Điện Thoại + OTP, Đổi Tài Khoản, Đăng Xuất thực sự (POST account/user/logout)
//  - Hỗ trợ gỡ thiết bị cũ trực tiếp trên Apple TV khi tài khoản vượt quá 3 thiết bị (error_code = 7)
//  - Tự động cập nhật lịch thi đấu Ngoại Hạng Anh & Thể Thao trực tiếp từ máy chủ FPT Play
//

import Foundation
import Combine

@MainActor
public final class FPTService: ObservableObject {
    public static let shared = FPTService()

    @Published public var prefer4K: Bool = true
    @Published public var isStandaloneReady: Bool = true
    @Published public var isAuthenticated: Bool = false
    @Published public var userId: String = ""
    @Published public var userPhone: String = ""
    @Published public var isBusyAuth: Bool = false
    @Published public var statusMessage: String = "Đang khởi tạo FTVOS trên Apple TV..."
    @Published public var phoneAuth: FPTPhoneAuthStatus? = nil
    @Published public var loggedInDevices: [FPTActiveDevice] = []

    @Published public var categories: [FPTCategory] = []
    @Published public var watchHistory: [FPTWatchHistoryItem] = []
    @Published public var searchResults: [FPTChannel] = []
    @Published public var searchTotal: Int = 0
    @Published public var searchPage: Int = 1
    @Published public var isSearching: Bool = false
    @Published public var lastSearchQuery: String = ""
    @Published public var isLoadingCatalog: Bool = false
    @Published public var logs: [String] = []

    public private(set) var bootstrapConfig: FPTBootstrapConfig

    private let defaults = UserDefaults.standard
    private let prefer4KKey = "ftvos_appletv_prefer_4k"
    private let watchHistoryKey = "ftvos_appletv_watch_history_v1"

    private init() {
        if defaults.object(forKey: prefer4KKey) != nil {
            self.prefer4K = defaults.bool(forKey: prefer4KKey)
        }
        if let historyData = defaults.data(forKey: watchHistoryKey),
           let decoded = try? JSONDecoder().decode([FPTWatchHistoryItem].self, from: historyData) {
            self.watchHistory = decoded
        }

        if let savedBootstrap = FPTKeychain.load(), savedBootstrap.isProvisioned {
            self.bootstrapConfig = savedBootstrap
        } else {
            let initial = FPTDirectClient.defaultBootstrapConfig()
            FPTKeychain.save(initial)
            self.bootstrapConfig = initial
        }

        self.isStandaloneReady = true
        self.isAuthenticated = self.bootstrapConfig.isAuthenticated
        self.userId = self.bootstrapConfig.userId
        self.userPhone = self.bootstrapConfig.phone ?? ""

        if self.bootstrapConfig.isAuthenticated {
            let phoneLabel = (self.bootstrapConfig.phone ?? "").isEmpty ? "UID: \(self.bootstrapConfig.userId)" : "SĐT: \(self.bootstrapConfig.phone!) • UID: \(self.bootstrapConfig.userId)"
            self.statusMessage = "🟢 Đã đăng nhập FTVOS (\(phoneLabel))"
            appendLog("🔐 Đã nạp phiên đăng nhập từ Keychain Apple TV (\(phoneLabel))")
        } else {
            self.statusMessage = "🟡 Chưa đăng nhập • Bấm 'Đăng Nhập SĐT (OTP)' để đăng nhập trực tiếp trên Apple TV"
            appendLog("🚀 Khởi động FTVOS (Sẵn sàng đăng nhập SĐT + OTP trực tiếp trên Apple TV)")
        }
    }

    public func togglePrefer4K() {
        prefer4K.toggle()
        defaults.set(prefer4K, forKey: prefer4KKey)
        appendLog("🎞️ Chế độ ưu tiên 4K UHD HEVC: \(prefer4K ? "BẬT" : "TẮT")")
    }

    public func appendLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let line = "[\(formatter.string(from: Date()))] \(message)"
        logs.insert(line, at: 0)
        if logs.count > 120 {
            logs.removeLast(logs.count - 120)
        }
    }

    public func refreshAll(forceEvents: Bool = false) async {
        await fetchCatalog(forceEvents: forceEvents)
        if bootstrapConfig.isAuthenticated {
            await fetchLoggedInDevices()
        }
    }

    public func fetchLoggedInDevices() async {
        guard bootstrapConfig.isAuthenticated else {
            self.loggedInDevices = []
            return
        }
        let devices = await FPTDirectClient.shared.fetchLoggedInDevices(config: bootstrapConfig)
        self.loggedInDevices = devices
        appendLog("📱 Đã tải danh sách \(devices.count)/5 thiết bị đang đăng nhập")
    }

    public func deleteLoggedInDevice(deviceId: String) async {
        isBusyAuth = true
        defer { isBusyAuth = false }
        do {
            let msg = try await FPTDirectClient.shared.deleteLoggedInDevice(config: bootstrapConfig, deviceId: deviceId)
            appendLog("🗑️ \(msg)")
            await fetchLoggedInDevices()
        } catch {
            appendLog("❌ Lỗi gỡ thiết bị: \(error.localizedDescription)")
        }
    }

    public func fetchCatalog(forceEvents: Bool = false) async {
        isLoadingCatalog = true
        defer { isLoadingCatalog = false }

        do {
            let directCatalog = try await FPTDirectClient.shared.fetchCatalog(config: bootstrapConfig, forceEvents: forceEvents)
            if !directCatalog.categories.isEmpty {
                self.categories = directCatalog.categories
                self.isAuthenticated = bootstrapConfig.isAuthenticated
                self.userId = bootstrapConfig.userId
                self.userPhone = bootstrapConfig.phone ?? ""
                let total = directCatalog.categories.reduce(0) { $0 + $1.channels.count }
                let matchCount = directCatalog.categories.first(where: { $0.id == "live_football" })?.channels.count ?? 0
                let seriesCount = directCatalog.categories.first(where: { $0.id == "vod_series" })?.channels.count ?? 0
                let movieCount = directCatalog.categories.first(where: { $0.id == "vod_movies" })?.channels.count ?? 0
                appendLog("📺 [FTVOS] Đã cập nhật \(matchCount) trận đấu, \(seriesCount) phim bộ, \(movieCount) phim lẻ & \(total - matchCount - seriesCount - movieCount) kênh truyền hình")
                return
            }
        } catch {
            appendLog("❌ Lỗi tải danh mục trực tiếp từ FPT Play: \(error.localizedDescription)")
        }
    }

    // MARK: - Quản lý Lịch Sử Xem (Watch History) trên Apple TV
    private func saveWatchHistoryToDisk() {
        if let data = try? JSONEncoder().encode(watchHistory) {
            defaults.set(data, forKey: watchHistoryKey)
        }
    }

    public func historyItem(forVodOrChannelId id: String) -> FPTWatchHistoryItem? {
        let clean = id.trimmingCharacters(in: .whitespacesAndNewlines)
        return watchHistory.first(where: {
            $0.id == clean || $0.channel.vodId == clean || $0.channel.channelId == clean
        })
    }

    public func recordWatchHistory(
        channel: FPTChannel,
        episodeId: String = "0",
        episodeTitle: String = "",
        positionSeconds: Double? = nil,
        durationSeconds: Double? = nil
    ) {
        let keyId = (channel.isVod && !channel.vodId.isEmpty) ? channel.vodId : channel.channelId
        guard !keyId.isEmpty else { return }

        let existing = historyItem(forVodOrChannelId: keyId)
        let savedPos: Double
        if let pos = positionSeconds {
            savedPos = pos
        } else if let ex = existing, ex.episodeId == episodeId {
            savedPos = ex.lastPositionSeconds
        } else {
            savedPos = 0
        }
        let savedDur = durationSeconds ?? existing?.durationSeconds ?? 0

        var updatedChannel = channel
        if channel.isVod {
            updatedChannel = FPTChannel(
                id: channel.id,
                channelId: channel.channelId,
                eventId: channel.eventId,
                name: channel.name,
                badge: channel.badge,
                categoryId: channel.categoryId,
                category: channel.category,
                logo: channel.logo,
                desc: channel.desc,
                is4K: channel.is4K,
                isDRM: channel.isDRM,
                isLive: channel.isLive,
                statusText: channel.statusText,
                resolution: channel.resolution,
                fps: channel.fps,
                isVod: true,
                isSeries: channel.isSeries,
                vodId: keyId,
                episodeId: episodeId
            )
        }

        let item = FPTWatchHistoryItem(
            id: keyId,
            channel: updatedChannel,
            episodeId: episodeId,
            episodeTitle: episodeTitle,
            lastPositionSeconds: savedPos,
            durationSeconds: savedDur,
            updatedAt: Date().timeIntervalSince1970
        )

        watchHistory.removeAll(where: { $0.id == keyId })
        watchHistory.insert(item, at: 0)
        if watchHistory.count > 18 {
            watchHistory.removeLast(watchHistory.count - 18)
        }
        saveWatchHistoryToDisk()
    }

    public func updatePlaybackProgress(
        vodOrChannelId: String,
        episodeId: String,
        episodeTitle: String = "",
        positionSeconds: Double,
        durationSeconds: Double
    ) {
        guard positionSeconds >= 3 else { return }
        let clean = vodOrChannelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let idx = watchHistory.firstIndex(where: {
            $0.id == clean || $0.channel.vodId == clean || $0.channel.channelId == clean
        }) else { return }

        var item = watchHistory[idx]
        item.episodeId = episodeId
        if !episodeTitle.isEmpty {
            item.episodeTitle = episodeTitle
        }
        item.lastPositionSeconds = positionSeconds
        if durationSeconds > 0 {
            item.durationSeconds = durationSeconds
        }
        item.updatedAt = Date().timeIntervalSince1970
        watchHistory.remove(at: idx)
        watchHistory.insert(item, at: 0)
        saveWatchHistoryToDisk()
    }

    public func clearWatchHistory() {
        watchHistory.removeAll()
        defaults.removeObject(forKey: watchHistoryKey)
        appendLog("🗑️ Đã xóa lịch sử xem")
    }

    public func searchVodCatalog(query: String, appendNextPage: Bool = false) async {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else {
            clearSearch()
            return
        }

        let targetPage = appendNextPage ? (searchPage + 1) : 1
        isSearching = true
        defer { isSearching = false }

        do {
            appendLog("🔍 Đang tìm kiếm kho phim FPT Play với từ khóa '\(cleanQuery)' (trang \(targetPage))...")
            let (total, results) = try await FPTDirectClient.shared.searchVod(
                config: bootstrapConfig,
                query: cleanQuery,
                page: targetPage,
                pageSize: 36
            )
            self.lastSearchQuery = cleanQuery
            self.searchPage = targetPage
            self.searchTotal = total
            if appendNextPage {
                let existingIds = Set(self.searchResults.map { $0.channelId })
                let newItems = results.filter { !existingIds.contains($0.channelId) }
                self.searchResults.append(contentsOf: newItems)
            } else {
                self.searchResults = results
            }
            appendLog("✅ Tìm thấy \(self.searchResults.count)/\(total) phim cho từ khóa '\(cleanQuery)'")
        } catch {
            appendLog("❌ Lỗi tìm kiếm phim: \(error.localizedDescription)")
        }
    }

    public func clearSearch() {
        searchResults.removeAll()
        searchTotal = 0
        searchPage = 1
        lastSearchQuery = ""
    }

    public func fetchVodDetail(for channel: FPTChannel) async throws -> FPTVodDetail {
        let vid = channel.vodId.isEmpty ? channel.channelId : channel.vodId
        appendLog("🎞️ Đang tải thông tin & danh sách tập cho [\(channel.name)] (vodId=\(vid))...")
        let detail = try await FPTDirectClient.shared.fetchVodDetail(
            config: bootstrapConfig,
            vodId: vid,
            fallbackChannel: channel
        )
        appendLog("✅ [FTVOS] Đã tải \(detail.episodes.count) tập phim cho [\(detail.title)]")
        return detail
    }

    public func resolveVodEpisode(vodDetail: FPTVodDetail, episode: FPTEpisode) async throws -> FPTResolvedStream {
        let fullTitle = vodDetail.isSeries ? "\(vodDetail.title) — \(episode.title)" : vodDetail.title
        appendLog("▶️ Đang xin luồng phát phim [\(fullTitle)] (vodId=\(vodDetail.vodId), ep=\(episode.id))...")
        let resolved = try await FPTDirectClient.shared.resolveVodStream(
            config: bootstrapConfig,
            vodId: vodDetail.vodId,
            episodeId: episode.id,
            title: fullTitle,
            prefer4K: prefer4K
        )
        let ch = FPTChannel(
            id: vodDetail.isSeries ? "vod_series_\(vodDetail.vodId)" : "vod_movie_\(vodDetail.vodId)",
            channelId: vodDetail.vodId,
            name: vodDetail.title,
            badge: vodDetail.isSeries ? "🎞️ PHIM BỘ" : "🎬 PHIM LẺ",
            categoryId: vodDetail.isSeries ? "vod_series" : "vod_movies",
            category: vodDetail.isSeries ? "Phim Bộ" : "Phim Lẻ",
            logo: vodDetail.poster,
            desc: vodDetail.desc,
            is4K: true,
            isDRM: vodDetail.isDrm,
            isLive: false,
            statusText: episode.title,
            resolution: vodDetail.country.isEmpty ? "Full HD / 4K HEVC" : "\(vodDetail.country) • FHD/4K",
            fps: vodDetail.isSeries ? "Chọn Tập • TM/Phụ Đề" : "Phát Ngay • TM/Phụ Đề",
            isVod: true,
            isSeries: vodDetail.isSeries,
            vodId: vodDetail.vodId,
            episodeId: episode.id
        )
        recordWatchHistory(channel: ch, episodeId: episode.id, episodeTitle: episode.title)
        appendLog("✅ [FTVOS] Nhận luồng phim HLS (\(resolved.is4K ? "4K/HEVC" : "Full HD")) • DRM: \(resolved.drm?.provider ?? "clear")")
        return resolved
    }

    public func resolveStream(for channel: FPTChannel) async throws -> FPTResolvedStream {
        appendLog("▶️ Đang xin luồng phát trực tiếp cho [\(channel.name)] (channel=\(channel.channelId), event=\(channel.eventId))...")

        let resolved = try await FPTDirectClient.shared.resolveStream(
            config: bootstrapConfig,
            channel: channel,
            prefer4K: prefer4K
        )
        recordWatchHistory(channel: channel, episodeId: channel.episodeId, episodeTitle: channel.isVod ? "Phim lẻ" : "")
        appendLog("✅ [FTVOS] Nhận luồng HLS (\(resolved.is4K ? "4K HEVC" : "Full HD")) • DRM: \(resolved.drm?.provider ?? "clear")")
        return resolved
    }

    // MARK: - Đăng nhập SĐT + OTP / Đổi Tài Khoản / Đăng Xuất Trực Tiếp 100% Trên Apple TV
    public func startPhoneOTP(phone: String) async {
        isBusyAuth = true
        defer { isBusyAuth = false }

        appendLog("📱 Đang gửi yêu cầu mã OTP trực tiếp từ Apple TV tới FPT Play...")
        do {
            var cfg = bootstrapConfig
            let status = try await FPTDirectClient.shared.startPhoneOTP(config: &cfg, phone: phone)
            self.bootstrapConfig = cfg
            self.isAuthenticated = cfg.isAuthenticated
            self.userId = cfg.userId
            self.userPhone = cfg.phone ?? ""
            self.phoneAuth = status
            self.statusMessage = status.message ?? statusMessage
            appendLog("📩 Kết quả gửi OTP: \(status.message ?? "")")
        } catch {
            let errMsg = "Lỗi kết nối FPT Play khi gửi OTP: \(error.localizedDescription)"
            self.phoneAuth = FPTPhoneAuthStatus(stage: "error", message: errMsg)
            appendLog("❌ \(errMsg)")
        }
    }

    public func verifyPhoneOTP(otp: String) async {
        isBusyAuth = true
        defer { isBusyAuth = false }

        appendLog("🔑 Đang xác nhận mã OTP trực tiếp trên Apple TV...")
        do {
            var cfg = bootstrapConfig
            let status = try await FPTDirectClient.shared.verifyPhoneOTP(config: &cfg, otp: otp)
            self.bootstrapConfig = cfg
            self.phoneAuth = status
            self.isAuthenticated = cfg.isAuthenticated
            self.userId = cfg.userId
            self.userPhone = cfg.phone ?? ""
            if cfg.isAuthenticated {
                let phoneLabel = (cfg.phone ?? "").isEmpty ? "UID: \(cfg.userId)" : "SĐT: \(cfg.phone!) • UID: \(cfg.userId)"
                self.statusMessage = "🟢 Đã đăng nhập FTVOS (\(phoneLabel))"
                appendLog("✅ Đăng nhập FPT Play VIP trực tiếp trên Apple TV thành công (\(phoneLabel))!")
                await fetchCatalog(forceEvents: true)
                await fetchLoggedInDevices()
            } else {
                self.statusMessage = status.message ?? statusMessage
                appendLog("⚠️ Xác thực OTP: \(status.message ?? "")")
            }
        } catch {
            let errMsg = "Lỗi xác nhận OTP: \(error.localizedDescription)"
            self.phoneAuth = FPTPhoneAuthStatus(stage: "otp_sent", message: errMsg, canVerify: true, canResend: true)
            appendLog("❌ \(errMsg)")
        }
    }

    public func removeDeviceAndLogin(deviceId: String) async {
        isBusyAuth = true
        defer { isBusyAuth = false }

        appendLog("🗑️ Đang gỡ thiết bị cũ (\(deviceId)) để hoàn tất đăng nhập trên Apple TV...")
        do {
            var cfg = bootstrapConfig
            let status = try await FPTDirectClient.shared.removeDeviceAndCompleteLogin(config: &cfg, deviceId: deviceId)
            self.bootstrapConfig = cfg
            self.phoneAuth = status
            self.isAuthenticated = cfg.isAuthenticated
            self.userId = cfg.userId
            self.userPhone = cfg.phone ?? ""
            if cfg.isAuthenticated {
                let phoneLabel = (cfg.phone ?? "").isEmpty ? "UID: \(cfg.userId)" : "SĐT: \(cfg.phone!) • UID: \(cfg.userId)"
                self.statusMessage = "🟢 Đã đăng nhập FTVOS (\(phoneLabel))"
                appendLog("✅ Đã gỡ thiết bị cũ và đăng nhập thành công (\(phoneLabel))!")
                await fetchCatalog(forceEvents: true)
                await fetchLoggedInDevices()
            } else {
                self.statusMessage = status.message ?? statusMessage
                appendLog("⚠️ Gỡ thiết bị: \(status.message ?? "")")
            }
        } catch {
            let errMsg = "Lỗi gỡ thiết bị: \(error.localizedDescription)"
            appendLog("❌ \(errMsg)")
        }
    }

    public func resendPhoneOTP() async {
        isBusyAuth = true
        defer { isBusyAuth = false }

        appendLog("🔄 Đang yêu cầu gửi lại mã OTP trực tiếp từ Apple TV...")
        do {
            let status = try await FPTDirectClient.shared.resendPhoneOTP(config: bootstrapConfig)
            self.phoneAuth = status
            self.statusMessage = status.message ?? statusMessage
            appendLog("📩 Gửi lại OTP: \(status.message ?? "")")
        } catch {
            appendLog("❌ Lỗi gửi lại OTP: \(error.localizedDescription)")
        }
    }

    public func logoutAccount() async {
        isBusyAuth = true
        defer { isBusyAuth = false }

        appendLog("🔓 Đang đăng xuất tài khoản khỏi máy chủ FPT Play & xóa sạch Keychain Apple TV...")
        var cfg = bootstrapConfig
        await FPTDirectClient.shared.logoutOnServer(config: &cfg)
        self.bootstrapConfig = cfg
        self.isAuthenticated = false
        self.userId = ""
        self.userPhone = ""
        self.loggedInDevices = []
        self.phoneAuth = FPTPhoneAuthStatus(
            stage: "idle",
            message: "Đã đăng xuất hoàn toàn. Nhập số điện thoại 10 số ở bên dưới để đăng nhập tài khoản mới."
        )
        self.statusMessage = "🟡 Đã đăng xuất hoàn toàn • Nhập SĐT + OTP để đăng nhập tài khoản mới"
        appendLog("✅ Đã đăng xuất hoàn toàn và tạo mã phiên sạch để đăng nhập tài khoản bất kỳ")
    }
}
