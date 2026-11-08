//
//  FPTModels.swift
//  FTVOS (Apple TV / tvOS)
//

import Foundation

public struct FPTBootstrapConfig: Codable, Equatable {
    public var ok: Bool?
    public var host: String
    public var mainPrefix: String
    public var qrPrefix: String
    public var source: String
    public var version: String
    public var versionCode: String
    public var clientId: String
    public var mainKey: String
    public var qrKey: String
    public var localId: String
    public var userAgent: String
    public var accessToken: String
    public var accessTokenType: String
    public var userId: String
    public var phone: String?
    public var profileId: String
    public var profileType: String
    public var profileMaturity: String
    public var storedUnix: Int?

    enum CodingKeys: String, CodingKey {
        case ok
        case host
        case mainPrefix = "main_prefix"
        case qrPrefix = "qr_prefix"
        case source
        case version
        case versionCode = "version_code"
        case clientId = "client_id"
        case mainKey = "main_key"
        case qrKey = "qr_key"
        case localId = "local_id"
        case userAgent = "user_agent"
        case accessToken = "access_token"
        case accessTokenType = "access_token_type"
        case userId = "user_id"
        case phone
        case profileId = "profileid"
        case profileType = "profiletype"
        case profileMaturity = "profilematurity"
        case storedUnix = "stored_unix"
    }

    public var isProvisioned: Bool {
        !host.isEmpty && !mainKey.isEmpty && !clientId.isEmpty
    }

    public var isAuthenticated: Bool {
        isProvisioned && !accessToken.isEmpty
    }
}

public struct FPTActiveDevice: Identifiable, Hashable, Codable {
    public let id: String
    public let deviceName: String
    public let deviceType: String
    public let accessTime: String

    public init(id: String, deviceName: String, deviceType: String, accessTime: String) {
        self.id = id
        self.deviceName = deviceName
        self.deviceType = deviceType
        self.accessTime = accessTime
    }
}

public struct FPTActor: Identifiable, Hashable, Codable {
    public let id: String
    public let name: String
    public let avatar: String
    public let role: String

    public init(id: String, name: String, avatar: String = "", role: String = "Diễn viên") {
        self.id = id
        self.name = name
        self.avatar = avatar
        self.role = role
    }
}

public struct FPTEpisode: Identifiable, Hashable, Codable {
    public let id: String
    public let title: String
    public let thumb: String
    public let durationText: String
    public let desc: String
    public let autoProfile: String
    public let isVip: Bool
    public let isPreview: Bool

    public init(
        id: String,
        title: String,
        thumb: String = "",
        durationText: String = "",
        desc: String = "",
        autoProfile: String = "adaptive_bitrate",
        isVip: Bool = false,
        isPreview: Bool = false
    ) {
        self.id = id
        self.title = title
        self.thumb = thumb
        self.durationText = durationText
        self.desc = desc
        self.autoProfile = autoProfile
        self.isVip = isVip
        self.isPreview = isPreview
    }
}

public struct FPTVodDetail: Identifiable, Hashable, Codable {
    public var id: String { vodId }
    public let vodId: String
    public let title: String
    public let shortDesc: String
    public let desc: String
    public let poster: String
    public let portraitPoster: String
    public let titleLogo: String
    public let country: String
    public let yearText: String
    public let ageRating: String
    public let metaData: [String]
    public let genres: [String]
    public let isSeries: Bool
    public let episodeTotal: String
    public let isDrm: Bool
    public let trailerUrl: String
    public let episodes: [FPTEpisode]
    public let actors: [FPTActor]
    public let relatedVods: [FPTChannel]

    public init(
        vodId: String,
        title: String,
        shortDesc: String = "",
        desc: String,
        poster: String,
        portraitPoster: String = "",
        titleLogo: String = "",
        country: String = "",
        yearText: String = "",
        ageRating: String = "",
        metaData: [String] = [],
        genres: [String] = [],
        isSeries: Bool,
        episodeTotal: String = "",
        isDrm: Bool = false,
        trailerUrl: String = "",
        episodes: [FPTEpisode],
        actors: [FPTActor] = [],
        relatedVods: [FPTChannel] = []
    ) {
        self.vodId = vodId
        self.title = title
        self.shortDesc = shortDesc
        self.desc = desc
        self.poster = poster
        self.portraitPoster = portraitPoster
        self.titleLogo = titleLogo
        self.country = country
        self.yearText = yearText
        self.ageRating = ageRating
        self.metaData = metaData
        self.genres = genres
        self.isSeries = isSeries
        self.episodeTotal = episodeTotal
        self.isDrm = isDrm
        self.trailerUrl = trailerUrl
        self.episodes = episodes
        self.actors = actors
        self.relatedVods = relatedVods
    }
}

public struct FPTWatchHistoryItem: Identifiable, Hashable, Codable {
    public let id: String
    public var channel: FPTChannel
    public var episodeId: String
    public var episodeTitle: String
    public var lastPositionSeconds: Double
    public var durationSeconds: Double
    public var updatedAt: TimeInterval

    public init(
        id: String,
        channel: FPTChannel,
        episodeId: String = "0",
        episodeTitle: String = "",
        lastPositionSeconds: Double = 0,
        durationSeconds: Double = 0,
        updatedAt: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.channel = channel
        self.episodeId = episodeId
        self.episodeTitle = episodeTitle
        self.lastPositionSeconds = lastPositionSeconds
        self.durationSeconds = durationSeconds
        self.updatedAt = updatedAt
    }

    public var progressLabel: String {
        let timeStr: String
        if lastPositionSeconds >= 10 {
            let mins = Int(lastPositionSeconds) / 60
            let secs = Int(lastPositionSeconds) % 60
            timeStr = String(format: "%02d:%02d", mins, secs)
        } else {
            timeStr = ""
        }
        if channel.isSeries && !episodeTitle.isEmpty {
            return timeStr.isEmpty ? "Đang xem: \(episodeTitle)" : "\(episodeTitle) • \(timeStr)"
        } else if channel.isVod {
            return timeStr.isEmpty ? "Xem tiếp phim lẻ" : "Xem tiếp • \(timeStr)"
        } else {
            return "Kênh vừa xem"
        }
    }
}

public struct FPTVodPlaybackSession: Identifiable {
    public var id: String { "\(resolved.id)_\(episode.id)" }
    public let detail: FPTVodDetail
    public let episode: FPTEpisode
    public let resolved: FPTResolvedStream
    public let resumeSeconds: Double

    public init(detail: FPTVodDetail, episode: FPTEpisode, resolved: FPTResolvedStream, resumeSeconds: Double = 0) {
        self.detail = detail
        self.episode = episode
        self.resolved = resolved
        self.resumeSeconds = resumeSeconds
    }
}

public struct FPTChannel: Identifiable, Hashable, Codable {
    public let id: String
    public let channelId: String
    public let eventId: String
    public let name: String
    public let badge: String
    public let categoryId: String
    public let category: String
    public let logo: String
    public let portraitLogo: String
    public let titleLogo: String
    public let desc: String
    public let is4K: Bool
    public let isDRM: Bool
    public let isLive: Bool
    public let statusText: String
    public let resolution: String
    public let fps: String
    public let isVod: Bool
    public let isSeries: Bool
    public let vodId: String
    public let episodeId: String

    enum CodingKeys: String, CodingKey {
        case id
        case channelId = "channel_id"
        case eventId = "event_id"
        case name
        case badge
        case categoryId = "category_id"
        case category
        case logo
        case portraitLogo = "portrait_logo"
        case titleLogo = "title_logo"
        case desc
        case is4K = "is_4k"
        case isDRM = "is_drm"
        case isLive = "is_live"
        case statusText = "status_text"
        case resolution
        case fps
        case isVod = "is_vod"
        case isSeries = "is_series"
        case vodId = "vod_id"
        case episodeId = "episode_id"
    }

    public init(
        id: String,
        channelId: String,
        eventId: String = "",
        name: String,
        badge: String,
        categoryId: String,
        category: String,
        logo: String,
        portraitLogo: String = "",
        titleLogo: String = "",
        desc: String,
        is4K: Bool,
        isDRM: Bool,
        isLive: Bool,
        statusText: String = "TRỰC TIẾP",
        resolution: String = "Full HD (H.264)",
        fps: String = "FairPlay DRM",
        isVod: Bool = false,
        isSeries: Bool = false,
        vodId: String = "",
        episodeId: String = "0"
    ) {
        self.id = id
        self.channelId = channelId
        self.eventId = eventId
        self.name = name
        self.badge = badge
        self.categoryId = categoryId
        self.category = category
        self.logo = logo
        self.portraitLogo = portraitLogo
        self.titleLogo = titleLogo
        self.desc = desc
        self.is4K = is4K
        self.isDRM = isDRM
        self.isLive = isLive
        self.statusText = statusText
        self.resolution = resolution
        self.fps = fps
        self.isVod = isVod
        self.isSeries = isSeries
        self.vodId = vodId
        self.episodeId = episodeId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        self.channelId = (try? c.decode(String.self, forKey: .channelId)) ?? ""
        self.eventId = (try? c.decode(String.self, forKey: .eventId)) ?? ""
        self.name = (try? c.decode(String.self, forKey: .name)) ?? ""
        self.badge = (try? c.decode(String.self, forKey: .badge)) ?? "LIVE"
        self.categoryId = (try? c.decode(String.self, forKey: .categoryId)) ?? ""
        self.category = (try? c.decode(String.self, forKey: .category)) ?? ""
        self.logo = (try? c.decode(String.self, forKey: .logo)) ?? ""
        self.portraitLogo = (try? c.decode(String.self, forKey: .portraitLogo)) ?? ""
        self.titleLogo = (try? c.decode(String.self, forKey: .titleLogo)) ?? ""
        self.desc = (try? c.decode(String.self, forKey: .desc)) ?? ""
        self.is4K = (try? c.decode(Bool.self, forKey: .is4K)) ?? false
        self.isDRM = (try? c.decode(Bool.self, forKey: .isDRM)) ?? false
        self.isLive = (try? c.decode(Bool.self, forKey: .isLive)) ?? true
        self.statusText = (try? c.decode(String.self, forKey: .statusText)) ?? "TRỰC TIẾP"
        self.resolution = (try? c.decode(String.self, forKey: .resolution)) ?? "Full HD"
        self.fps = (try? c.decode(String.self, forKey: .fps)) ?? "HLS Native"
        self.isVod = (try? c.decode(Bool.self, forKey: .isVod)) ?? false
        self.isSeries = (try? c.decode(Bool.self, forKey: .isSeries)) ?? false
        self.vodId = (try? c.decode(String.self, forKey: .vodId)) ?? ""
        self.episodeId = (try? c.decode(String.self, forKey: .episodeId)) ?? "0"
    }
}

public struct FPTCategory: Identifiable, Hashable, Codable {
    public let id: String
    public let title: String
    public let icon: String
    public let channels: [FPTChannel]

    public init(id: String, title: String, icon: String, channels: [FPTChannel]) {
        self.id = id
        self.title = title
        self.icon = icon
        self.channels = channels
    }
}

public struct FPTCatalogResponse: Codable {
    public let ok: Bool
    public let updatedAt: Int?
    public let authenticated: Bool
    public let userId: String?
    public let categories: [FPTCategory]

    enum CodingKeys: String, CodingKey {
        case ok
        case updatedAt = "updated_at"
        case authenticated
        case userId = "user_id"
        case categories
    }

    public init(ok: Bool, updatedAt: Int?, authenticated: Bool, userId: String?, categories: [FPTCategory]) {
        self.ok = ok
        self.updatedAt = updatedAt
        self.authenticated = authenticated
        self.userId = userId
        self.categories = categories
    }
}

public struct FPTPhoneAuthStatus: Codable {
    public let stage: String?
    public let message: String?
    public let resendAfterSeconds: Int?
    public let canVerify: Bool?
    public let canResend: Bool?
    public let activeDevices: [FPTActiveDevice]?

    enum CodingKeys: String, CodingKey {
        case stage
        case message
        case resendAfterSeconds = "resend_after_seconds"
        case canVerify = "can_verify"
        case canResend = "can_resend"
        case activeDevices = "active_devices"
    }

    public init(
        stage: String?,
        message: String?,
        resendAfterSeconds: Int? = 0,
        canVerify: Bool? = false,
        canResend: Bool? = false,
        activeDevices: [FPTActiveDevice]? = nil
    ) {
        self.stage = stage
        self.message = message
        self.resendAfterSeconds = resendAfterSeconds
        self.canVerify = canVerify
        self.canResend = canResend
        self.activeDevices = activeDevices
    }
}

public struct FPTDRMConfig: Codable, Hashable {
    public let enabled: Bool
    public let provider: String?
    public let merchant: String?
    public let certUrl: String?
    public let proxyCertUrl: String?
    public let licenseUrl: String?
    public let proxyCkcUrl: String?
    public let headerName: String?
    public let headerValue: String?

    enum CodingKeys: String, CodingKey {
        case enabled
        case provider
        case merchant
        case certUrl = "cert_url"
        case proxyCertUrl = "proxy_cert_url"
        case licenseUrl = "license_url"
        case proxyCkcUrl = "proxy_ckc_url"
        case headerName = "header_name"
        case headerValue = "header_value"
    }

    public init(
        enabled: Bool,
        provider: String? = nil,
        merchant: String? = nil,
        certUrl: String? = nil,
        proxyCertUrl: String? = nil,
        licenseUrl: String? = nil,
        proxyCkcUrl: String? = nil,
        headerName: String? = nil,
        headerValue: String? = nil
    ) {
        self.enabled = enabled
        self.provider = provider
        self.merchant = merchant
        self.certUrl = certUrl
        self.proxyCertUrl = proxyCertUrl
        self.licenseUrl = licenseUrl
        self.proxyCkcUrl = proxyCkcUrl
        self.headerName = headerName
        self.headerValue = headerValue
    }
}

public struct FPTResolvedStream: Codable, Identifiable {
    public var id: String { "\(channelId)_\(eventId)_\(hlsUrl)_\(isWaitingSlate ?? false)" }
    public let ok: Bool
    public let channelId: String
    public let eventId: String
    public let title: String
    public let hlsUrl: String
    public let fallbackHlsUrl: String?
    public let hls4KUrl: String?
    public let hlsH264Url: String?
    public let is4K: Bool
    public let mediaHeaders: [String: String]?
    public let drm: FPTDRMConfig?
    public let message: String?
    public let isWaitingSlate: Bool?
    public let posterUrl: String?
    public let scheduleText: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case channelId = "channel_id"
        case eventId = "event_id"
        case title
        case hlsUrl = "hls_url"
        case fallbackHlsUrl = "fallback_hls_url"
        case hls4KUrl = "hls_4k_url"
        case hlsH264Url = "hls_h264_url"
        case is4K = "is_4k"
        case mediaHeaders = "media_headers"
        case drm
        case message
        case isWaitingSlate = "is_waiting_slate"
        case posterUrl = "poster_url"
        case scheduleText = "schedule_text"
    }

    public init(
        ok: Bool,
        channelId: String,
        eventId: String,
        title: String,
        hlsUrl: String,
        fallbackHlsUrl: String?,
        hls4KUrl: String?,
        hlsH264Url: String?,
        is4K: Bool,
        mediaHeaders: [String: String]?,
        drm: FPTDRMConfig?,
        message: String? = nil,
        isWaitingSlate: Bool? = false,
        posterUrl: String? = nil,
        scheduleText: String? = nil
    ) {
        self.ok = ok
        self.channelId = channelId
        self.eventId = eventId
        self.title = title
        self.hlsUrl = hlsUrl
        self.fallbackHlsUrl = fallbackHlsUrl
        self.hls4KUrl = hls4KUrl
        self.hlsH264Url = hlsH264Url
        self.is4K = is4K
        self.mediaHeaders = mediaHeaders
        self.drm = drm
        self.message = message
        self.isWaitingSlate = isWaitingSlate
        self.posterUrl = posterUrl
        self.scheduleText = scheduleText
    }
}

// MARK: - Cấu Hình Đổi Luồng Động & Cập Nhật Tự Động Qua GitHub (remote_stream_config.json)
public struct FPTRemoteStreamConfig: Codable, Equatable {
    public var configVersion: Int
    public var updatedAt: String
    public var latestAppVersion: String
    public var latestBuildNumber: Int
    public var latestIpaUrl: String
    public var releasePageUrl: String
    public var updateNotes: String
    public var liveGatewayOrder: [String]
    public var vodGatewayOrder: [String]
    public var channelGatewayOverrides: [String: [String]]
    public var h265DrmKeys: [String]
    public var h265ClearKeys: [String]
    public var h264DrmKeys: [String]
    public var h264ClearKeys: [String]
    public var iosExtraQuery: [String: String]
    public var keepAllTopTierAudioVariants: Bool
    public var enableDashToHlsFallback: Bool
    public var channelDirectOverrides: [String: [String: String]]

    enum CodingKeys: String, CodingKey {
        case configVersion = "config_version"
        case updatedAt = "updated_at"
        case latestAppVersion = "latest_app_version"
        case latestBuildNumber = "latest_build_number"
        case latestIpaUrl = "latest_ipa_url"
        case releasePageUrl = "release_page_url"
        case updateNotes = "update_notes"
        case liveGatewayOrder = "live_gateway_order"
        case vodGatewayOrder = "vod_gateway_order"
        case channelGatewayOverrides = "channel_gateway_overrides"
        case h265DrmKeys = "h265_drm_keys"
        case h265ClearKeys = "h265_clear_keys"
        case h264DrmKeys = "h264_drm_keys"
        case h264ClearKeys = "h264_clear_keys"
        case iosExtraQuery = "ios_extra_query"
        case keepAllTopTierAudioVariants = "keep_all_top_tier_audio_variants"
        case enableDashToHlsFallback = "enable_dash_to_hls_fallback"
        case channelDirectOverrides = "channel_direct_overrides"
    }

    public static func defaultConfig() -> FPTRemoteStreamConfig {
        return FPTRemoteStreamConfig(
            configVersion: 2026110801,
            updatedAt: "2026-11-08T08:00:00+07:00",
            latestAppVersion: "2.1.0",
            latestBuildNumber: 6,
            latestIpaUrl: "https://github.com/hongson117/FPTios/releases/latest/download/FTVOS.ipa",
            releasePageUrl: "https://github.com/hongson117/FPTios/releases/latest",
            updateNotes: "Cập nhật luồng Ngoại Hạng Anh 4K UHD 50fps qua cổng Apple (/api/v7.1_ios/) & tự động đồng bộ cấu hình đổi luồng từ GitHub.",
            liveGatewayOrder: ["ios", "stad", "web"],
            vodGatewayOrder: ["ios", "web", "stad"],
            channelGatewayOverrides: [
                "hbo": ["stad", "ios", "web"],
                "max-by-hbo": ["stad", "ios", "web"],
                "cnn": ["stad", "ios", "web"],
                "bbc-news": ["stad", "ios", "web"],
                "warner-tv": ["stad", "ios", "web"],
                "cartoon-network": ["stad", "ios", "web"],
                "discovery": ["stad", "ios", "web"],
                "axn": ["stad", "ios", "web"]
            ],
            h265DrmKeys: [
                "url_hls_drm_dolby_vision",
                "url_hls_drm_h265_hdr_10_plus",
                "url_hls_drm_h265_hdr_10",
                "url_hls_drm_h265_hlg",
                "url_hls_drm_h265",
                "url_hls_dolby_vision",
                "url_hls_h265_hdr_10_plus",
                "url_hls_h265_hdr_10",
                "url_hls_h265_hlg",
                "url_hls_h265"
            ],
            h265ClearKeys: [
                "url_hls_dolby_vision",
                "url_hls_h265_hdr_10_plus",
                "url_hls_h265_hdr_10",
                "url_hls_h265_hlg",
                "url_hls_h265",
                "url_hls_drm_h265"
            ],
            h264DrmKeys: [
                "url_hls_drm",
                "url_hls",
                "url_sub",
                "url_clean",
                "url"
            ],
            h264ClearKeys: [
                "url_hls",
                "url_sub",
                "url_clean",
                "url",
                "url_hls_drm"
            ],
            iosExtraQuery: [
                "device": "Apple TV",
                "drm": "1",
                "fhd": "1",
                "2k": "1",
                "4k": "1",
                "hd": "1",
                "dolby_vision": "1",
                "hdr_10": "1",
                "hdr_10_plus": "1",
                "hlg": "1",
                "h265": "1",
                "deviceWidth": "3840",
                "deviceHeight": "2160"
            ],
            keepAllTopTierAudioVariants: true,
            enableDashToHlsFallback: true,
            channelDirectOverrides: [:]
        )
    }
}

public struct FPTGitHubReleaseInfo: Codable, Equatable {
    public let tagName: String
    public let title: String
    public let notes: String
    public let publishedAt: String
    public let ipaDownloadUrl: String
    public let htmlUrl: String
    public let fileSizeText: String
    public let hasNewerBinary: Bool
    public let remoteConfigVersion: Int

    public init(
        tagName: String,
        title: String,
        notes: String,
        publishedAt: String,
        ipaDownloadUrl: String,
        htmlUrl: String,
        fileSizeText: String,
        hasNewerBinary: Bool,
        remoteConfigVersion: Int
    ) {
        self.tagName = tagName
        self.title = title
        self.notes = notes
        self.publishedAt = publishedAt
        self.ipaDownloadUrl = ipaDownloadUrl
        self.htmlUrl = htmlUrl
        self.fileSizeText = fileSizeText
        self.hasNewerBinary = hasNewerBinary
        self.remoteConfigVersion = remoteConfigVersion
    }
}
