//
//  FPTDirectClient.swift
//  FTVOS (Apple TV / tvOS)
//
//  Thực thi trực tiếp 100% giao thức FPT Play API ngay trên Apple TV (tvOS):
//  - Không cần bật Laptop
//  - Đăng nhập từ đầu trực tiếp bằng Số Điện Thoại + OTP
//  - Đăng xuất thật trên máy chủ (POST account/user/logout) & Chuyển đổi sang tài khoản khác bất kỳ lúc nào
//  - Tự động xử lý trường hợp tài khoản đầy 3 thiết bị (POST account/device/limit_list & account/device/remove)
//

import Foundation
import CryptoKit

public final class FPTDirectClient {
    public static let shared = FPTDirectClient()

    private let lockedIntlIds: Set<String> = [
        "hbo", "max-by-hbo", "warner-tv", "axn", "cinemaworld",
        "discovery", "discovery-asia", "bbc-earth", "animal-planet",
        "travel-living", "bbc-lifestyle", "fashion-tv", "cnn",
        "bbc-news", "bloomberg", "australia-plus", "cartoon-network",
        "dreamworks", "cartoonito", "cbeebies"
    ]

    private let openIntlIds: Set<String> = [
        "nhk-world-hd", "dw", "france-24", "channel-newsasia",
        "cnbc", "kbs-world", "arirang", "tv5-monde",
        "kix", "asian-food-channel", "outdoor-channel", "da-vinci-learning"
    ]

    private var cachedRawChannels: [[String: Any]] = []
    private var cachedLiveEvents: [FPTChannel] = []
    private var lastEventsFetchTime: TimeInterval = 0
    private var cachedVodSeries: [FPTChannel] = []
    private var cachedVodMovies: [FPTChannel] = []
    private var lastVodFetchTime: TimeInterval = 0

    // Trạng thái phiên OTP & Gỡ thiết bị khi đăng nhập trực tiếp trên Apple TV
    public private(set) var pendingPhone: String = ""
    private var pendingValidateToken: String = ""
    private var pendingMethodOtp: String = ""
    private var pendingLoginVerifyToken: String = ""
    private var pendingRemoveDeviceToken: String = ""

    private static let savedDeviceKey = "ftvos_appletv_device_id_v2"

    private init() {}

    // MARK: - Khởi tạo cấu hình gốc ngay trên Apple TV (Không cần Laptop)
    private static func unmask(_ bytes: [UInt8]) -> String {
        let decoded = bytes.map { $0 ^ 0x5A }
        return String(bytes: decoded, encoding: .utf8) ?? ""
    }

    public static func currentOrNewDeviceId(forceNew: Bool = false) -> String {
        if !forceNew,
           let existing = UserDefaults.standard.string(forKey: savedDeviceKey),
           existing.count == 32 {
            return existing
        }
        let generated = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        UserDefaults.standard.set(generated, forKey: savedDeviceKey)
        return generated
    }

    public static func defaultBootstrapConfig(forceNewDevice: Bool = false) -> FPTBootstrapConfig {
        let deviceId = currentOrNewDeviceId(forceNew: forceNewDevice)

        return FPTBootstrapConfig(
            ok: true,
            host: unmask([50, 46, 46, 42, 41, 96, 117, 117, 59, 42, 51, 116, 60, 42, 46, 42, 54, 59, 35, 116, 52, 63, 46]),
            mainPrefix: unmask([117, 59, 42, 51, 117, 44, 109, 116, 107, 5, 41, 46, 59, 62, 117]),
            qrPrefix: unmask([117, 59, 42, 51, 43, 54, 117, 44, 104, 116, 107, 5, 41, 46, 59, 62, 117]),
            source: unmask([41, 55, 59, 40, 46, 119, 46, 44, 119, 52, 53, 40, 55, 59, 54]),
            version: unmask([109, 116, 105, 110, 116, 107, 105]),
            versionCode: unmask([110, 105, 99, 110]),
            clientId: unmask([44, 17, 35, 10, 20, 62, 107, 51, 13, 18, 53, 62, 11, 12, 49, 52, 34, 57, 44, 0, 53, 13, 32, 109, 110, 104, 99, 111, 45, 52, 49, 98]),
            mainKey: unmask([51, 108, 22, 47, 9, 53, 14, 23, 109, 49, 15, 11, 13, 48, 28, 59, 43, 46, 44, 41, 14, 56, 109, 27, 45, 22, 32, 11, 42, 44]),
            qrKey: unmask([11, 22, 56, 44, 41, 110, 111, 44, 59, 12, 27, 29, 45, 23, 52, 52, 99, 104, 27, 56, 16, 104, 47, 52, 49, 41]),
            localId: deviceId,
            userAgent: "FPT-AndroidTV-API-Research/0.1 (AppleTV; FTVOS 2.0)",
            accessToken: "",
            accessTokenType: "Bearer",
            userId: "",
            phone: "",
            profileId: "",
            profileType: "",
            profileMaturity: "",
            storedUnix: 0
        )
    }

    public func resetPendingOtpState() {
        pendingPhone = ""
        pendingValidateToken = ""
        pendingMethodOtp = ""
        pendingLoginVerifyToken = ""
        pendingRemoveDeviceToken = ""
    }

    // MARK: - Ký MD5 URL-Safe Base64 (chuẩn Utils.encrypt cờ 11)
    public func signPath(key: String, expiry: Int, path: String) -> String {
        let decodedPath = path.removingPercentEncoding ?? path
        let raw = "\(key)\(expiry)\(decodedPath)"
        let digest = Insecure.MD5.hash(data: Data(raw.utf8))
        let b64 = Data(digest).base64EncodedString()
        return b64
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public func dashToHlsUrl(_ url: String) -> String {
        guard !url.isEmpty else { return "" }
        // Tuyệt đối không sửa đường dẫn nếu URL có chữ ký MD5 gắn liền với path (?sign= hoặc &sign=),
        // vì CDN sẽ từ chối 403 Forbidden nếu đổi .mpd sang .m3u8 mà không ký lại.
        if url.contains("?sign=") || url.contains("&sign=") {
            return url
        }
        if url.contains("dash_h_drm/index.mpd") {
            return url.replacingOccurrences(of: "dash_h_drm/index.mpd", with: "hls_h_drm/index.m3u8")
        }
        if url.contains("dash_a_drm/index.mpd") {
            return url.replacingOccurrences(of: "dash_a_drm/index.mpd", with: "hls_a_drm/index.m3u8")
        }
        if url.contains("dash_drm/index.mpd") {
            return url.replacingOccurrences(of: "dash_drm/index.mpd", with: "hls_drm/index.m3u8")
        }
        if url.contains("dash_h/index.mpd") {
            return url.replacingOccurrences(of: "dash_h/index.mpd", with: "hls_h/index.m3u8")
        }
        if url.contains("dash_a/index.mpd") {
            return url.replacingOccurrences(of: "dash_a/index.mpd", with: "hls_a/index.m3u8")
        }
        if url.contains("live247-dash-avc/index.mpd") {
            return url.replacingOccurrences(of: "live247-dash-avc/index.mpd", with: "live247-hls-avc/index.m3u8")
        }
        if url.contains("live-dash-avc/index.mpd") {
            return url.replacingOccurrences(of: "live-dash-avc/index.mpd", with: "live-hls-avc/index.m3u8")
        }
        if url.contains(".smil/manifest.mpd") {
            return url.replacingOccurrences(of: ".smil/manifest.mpd", with: ".smil/playlist.m3u8")
        }
        if url.contains("/manifest.mpd") {
            return url.replacingOccurrences(of: "/manifest.mpd", with: "/playlist.m3u8")
        }
        return url
    }

    public func extractJwtUserId(_ sessionJwt: String) -> String? {
        let parts = sessionJwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payloadB64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let rem = payloadB64.count % 4
        if rem > 0 {
            payloadB64 += String(repeating: "=", count: 4 - rem)
        }
        guard let data = Data(base64Encoded: payloadB64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let uid = json["userId"] as? String, !uid.isEmpty else {
            return nil
        }
        return uid
    }

    // MARK: - Gọi HTTP trực tiếp tới api.fptplay.net
    public func requestJSON(
        config: FPTBootstrapConfig,
        method: String = "GET",
        route: String,
        qrApi: Bool = false,
        extraQuery: [(String, String)] = [],
        body: [String: Any]? = nil,
        authenticated: Bool = true
    ) async throws -> (Int, [String: Any]) {
        let prefix = qrApi ? config.qrPrefix : config.mainPrefix
        let cleanRoute = route.hasPrefix("/") ? String(route.dropFirst()) : route
        let path = prefix + cleanRoute
        let expiry = Int(Date().timeIntervalSince1970) + 14400
        let key = qrApi ? config.qrKey : config.mainKey
        let signature = signPath(key: key, expiry: expiry, path: path)
        let localId = config.localId.isEmpty ? Self.currentOrNewDeviceId() : config.localId

        var queryItems: [URLQueryItem] = extraQuery.map { URLQueryItem(name: $0.0, value: $0.1) }
        let common: [(String, String)] = [
            ("serial_number", ""),
            ("drm_id", ""),
            ("drm", "1"),
            ("drmLevel", ""),
            ("deviceWidth", "3840"),
            ("deviceHeight", "2160"),
            ("fhd", "1"),
            ("2k", "1"),
            ("4k", "1"),
            ("st", signature),
            ("e", String(expiry)),
            ("version", config.version),
            ("version_code", config.versionCode),
            ("source", config.source),
            ("uSKBC", "true"),
            ("cachedByUrls", "true"),
            ("nettype", ""),
            ("device", "Apple TV FTVOS"),
            ("mac_address", localId),
            ("mac_addr", localId),
            ("fid", "1"),
            ("stream_profile", "1")
        ]
        for (k, v) in common {
            queryItems.append(URLQueryItem(name: k, value: v))
        }

        var comps = URLComponents(string: config.host + path)
        comps?.queryItems = queryItems
        guard let url = comps?.url else {
            throw NSError(domain: "FPTDirectClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Không tạo được URL FPT Play API"])
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 15.0
        req.setValue(config.userAgent.isEmpty ? "FPT-AndroidTV-API-Research/0.1 (AppleTV; FTVOS 2.0)" : config.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(signature, forHTTPHeaderField: "st")
        req.setValue(String(expiry), forHTTPHeaderField: "e")
        req.setValue(localId, forHTTPHeaderField: "X-DID")

        if authenticated && !config.accessToken.isEmpty {
            let tokenType = config.accessTokenType.isEmpty ? "Bearer" : config.accessTokenType
            req.setValue("\(tokenType) \(config.accessToken)", forHTTPHeaderField: "Authorization")
            if !config.profileId.isEmpty {
                req.setValue(config.profileId, forHTTPHeaderField: "profileid")
                req.setValue(config.profileType, forHTTPHeaderField: "profiletype")
                req.setValue(config.profileMaturity, forHTTPHeaderField: "profilematurity")
            }
        }

        if let body = body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            req.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        } else if method == "POST" {
            req.httpBody = Data("{}".utf8)
            req.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        }

        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 500
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        return (status, json)
    }

    // MARK: - Gọi cổng Web/Safari FairPlay API (/api/v7.1_w/) để lấy luồng HLS FairPlay (.m3u8) gốc cho Apple TV
    public func requestWebJSON(
        config: FPTBootstrapConfig,
        method: String = "GET",
        route: String,
        extraQuery: [(String, String)] = [],
        authenticated: Bool = true
    ) async throws -> (Int, [String: Any]) {
        // /api/v7.1_w/ & khóa ký Web FairPlay chuẩn fptplay.vn
        let webPrefix = Self.unmask([117, 59, 42, 51, 117, 44, 109, 116, 107, 5, 45, 117])
        let webKey = Self.unmask([108, 63, 59, 108, 62, 104, 59, 110, 63, 104, 62, 105, 59, 110, 56, 62, 111, 63, 104, 109, 111, 110, 106, 107, 59, 59, 106, 98, 108, 62])
        let cleanRoute = route.hasPrefix("/") ? String(route.dropFirst()) : route
        let path = webPrefix + cleanRoute
        let expiry = Int(Date().timeIntervalSince1970) + 14400
        let signature = signPath(key: webKey, expiry: expiry, path: path)
        let localId = config.localId.isEmpty ? Self.currentOrNewDeviceId() : config.localId

        var queryItems: [URLQueryItem] = extraQuery.map { URLQueryItem(name: $0.0, value: $0.1) }
        let webCommon: [(String, String)] = [
            ("st", signature),
            ("e", String(expiry)),
            ("device", "Safari(version:17.0)"),
            ("drm", "1"),
            ("version", "2026.4.1")
        ]
        for (k, v) in webCommon {
            if !queryItems.contains(where: { $0.name == k }) {
                queryItems.append(URLQueryItem(name: k, value: v))
            }
        }

        var comps = URLComponents(string: config.host + path)
        comps?.queryItems = queryItems
        guard let url = comps?.url else {
            throw NSError(domain: "FPTDirectClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Không tạo được URL FPT Play Web FairPlay API"])
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 15.0
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        req.setValue("https://fptplay.vn", forHTTPHeaderField: "Origin")
        req.setValue("https://fptplay.vn/", forHTTPHeaderField: "Referer")
        req.setValue(localId, forHTTPHeaderField: "X-DID")

        if authenticated && !config.accessToken.isEmpty {
            let tokenType = config.accessTokenType.isEmpty ? "Bearer" : config.accessTokenType
            req.setValue("\(tokenType) \(config.accessToken)", forHTTPHeaderField: "Authorization")
            if !config.profileId.isEmpty {
                req.setValue(config.profileId, forHTTPHeaderField: "profileid")
                req.setValue(config.profileType, forHTTPHeaderField: "profiletype")
                req.setValue(config.profileMaturity, forHTTPHeaderField: "profilematurity")
            }
        }

        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 500
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        return (status, json)
    }

    // MARK: - Đăng xuất thật trên máy chủ FPT Play (POST account/user/logout)
    public func logoutOnServer(config: inout FPTBootstrapConfig) async {
        if !config.accessToken.isEmpty {
            _ = try? await requestJSON(
                config: config,
                method: "POST",
                route: "account/user/logout",
                body: [:],
                authenticated: true
            )
        }
        resetPendingOtpState()
        FPTKeychain.clear()
        // Khởi tạo lại mã thiết bị sạch để sẵn sàng đăng nhập tài khoản mới không bị vướng phiên cũ
        config = Self.defaultBootstrapConfig(forceNewDevice: true)
        FPTKeychain.save(config)
    }

    // MARK: - Chuẩn hóa số điện thoại Việt Nam (10 chữ số)
    public func normalizePhone(_ raw: String) -> String {
        var digits = raw.filter { $0.isNumber }
        if digits.hasPrefix("84") && digits.count == 11 {
            digits = "0" + String(digits.dropFirst(2))
        }
        return digits
    }

    // MARK: - Bước 1: Gửi Mã OTP trực tiếp từ Apple TV
    public func startPhoneOTP(config: inout FPTBootstrapConfig, phone: String) async throws -> FPTPhoneAuthStatus {
        let cleanPhone = normalizePhone(phone)
        guard cleanPhone.count == 10, cleanPhone.hasPrefix("0") else {
            return FPTPhoneAuthStatus(
                stage: "error",
                message: "Vui lòng nhập đúng số điện thoại 10 chữ số (bắt đầu bằng số 0, VD: 09xxxxxxxx)."
            )
        }

        // Nếu đang có tài khoản cũ đăng nhập thì tự động đăng xuất tài khoản cũ trước khi gửi OTP cho số mới
        if config.isAuthenticated {
            await logoutOnServer(config: &config)
        } else {
            resetPendingOtpState()
        }

        let (_, valJson) = try await requestJSON(
            config: config,
            method: "POST",
            route: "account/otp/validate_user",
            body: [
                "phone": cleanPhone,
                "client_id": config.clientId,
                "type": "login_fpl",
                "mode": "interactive"
            ],
            authenticated: false
        )

        let valStatus = String(describing: valJson["status"] ?? "0")
        let valData = (valJson["data"] as? [String: Any]) ?? [:]
        guard valStatus == "1",
              let validateToken = valData["verify_token"] as? String,
              !validateToken.isEmpty else {
            let msg = (valJson["msg"] as? String) ?? (valData["title"] as? String) ?? "FPT Play chưa chấp nhận số điện thoại này."
            return FPTPhoneAuthStatus(stage: "error", message: msg)
        }

        self.pendingPhone = cleanPhone
        self.pendingValidateToken = validateToken

        let (_, sendJson) = try await requestJSON(
            config: config,
            method: "POST",
            route: "account/otp/send",
            body: [
                "phone": cleanPhone,
                "client_id": config.clientId,
                "type_otp": "login_fpl",
                "verify_token": validateToken,
                "method_otp": ""
            ],
            authenticated: false
        )

        let sendStatus = String(describing: sendJson["status"] ?? "0")
        let sendData = (sendJson["data"] as? [String: Any]) ?? [:]
        guard sendStatus == "1" else {
            let msg = (sendJson["msg"] as? String) ?? (sendData["title"] as? String) ?? "Không gửi được mã OTP."
            return FPTPhoneAuthStatus(stage: "error", message: msg)
        }

        if let lastMethod = sendData["last_sent_otp"] as? String, !lastMethod.isEmpty {
            self.pendingMethodOtp = lastMethod
        } else if let sw = sendData["switch_mode"] as? [String: Any],
                  let def = sw["default"] as? [String: Any],
                  let m = def["method"] as? String {
            self.pendingMethodOtp = m
        }

        let serverMsg = (sendJson["msg"] as? String) ?? "Đã gửi mã OTP tới số \(cleanPhone)."
        return FPTPhoneAuthStatus(
            stage: "otp_sent",
            message: "\(serverMsg) Vui lòng nhập mã OTP vào ô Bước 2 và bấm Xác Nhận OTP.",
            canVerify: true,
            canResend: true
        )
    }

    // MARK: - Gửi lại mã OTP
    public func resendPhoneOTP(config: FPTBootstrapConfig) async throws -> FPTPhoneAuthStatus {
        guard !pendingPhone.isEmpty else {
            return FPTPhoneAuthStatus(stage: "error", message: "Vui lòng nhập số điện thoại ở Bước 1 và bấm Gửi Mã OTP trước.")
        }
        let (_, resendJson) = try await requestJSON(
            config: config,
            method: "POST",
            route: "account/otp/resend_otp",
            body: [
                "phone": pendingPhone,
                "client_id": config.clientId,
                "type_otp": "login_fpl",
                "method_otp": pendingMethodOtp
            ],
            authenticated: false
        )
        guard String(describing: resendJson["status"] ?? "0") == "1" else {
            let msg = (resendJson["msg"] as? String) ?? "Chưa thể gửi lại mã OTP lúc này (Vui lòng chờ hết thời gian đếm ngược)."
            return FPTPhoneAuthStatus(stage: "otp_sent", message: msg, canVerify: true, canResend: true)
        }
        return FPTPhoneAuthStatus(
            stage: "otp_sent",
            message: "Đã gửi lại mã OTP mới tới số \(pendingPhone).",
            canVerify: true,
            canResend: true
        )
    }

    // MARK: - Bước 2: Xác nhận mã OTP & Đăng nhập (Tự động kiểm tra giới hạn 3 thiết bị)
    public func verifyPhoneOTP(config: inout FPTBootstrapConfig, otp: String) async throws -> FPTPhoneAuthStatus {
        let cleanOtp = otp.filter { $0.isNumber }
        guard !pendingPhone.isEmpty else {
            return FPTPhoneAuthStatus(stage: "error", message: "Vui lòng nhập số điện thoại ở Bước 1 và bấm Gửi Mã OTP trước.")
        }
        guard !cleanOtp.isEmpty else {
            return FPTPhoneAuthStatus(stage: "otp_sent", message: "Vui lòng nhập mã OTP gồm các chữ số.", canVerify: true, canResend: true)
        }

        let (_, verJson) = try await requestJSON(
            config: config,
            method: "POST",
            route: "account/otp/verify",
            body: [
                "phone": pendingPhone,
                "client_id": config.clientId,
                "type_otp": "login_fpl",
                "otp_code": cleanOtp,
                "method_otp": pendingMethodOtp
            ],
            authenticated: false
        )

        let verStatus = String(describing: verJson["status"] ?? "0")
        let verData = (verJson["data"] as? [String: Any]) ?? [:]
        guard verStatus == "1",
              let verifyToken = verData["verify_token"] as? String,
              !verifyToken.isEmpty else {
            let msg = (verJson["msg"] as? String) ?? "Mã OTP không chính xác hoặc đã hết hạn."
            return FPTPhoneAuthStatus(stage: "otp_sent", message: msg, canVerify: true, canResend: true)
        }

        self.pendingLoginVerifyToken = verifyToken

        let (_, loginJson) = try await requestJSON(
            config: config,
            method: "POST",
            route: "account/user/login",
            body: [
                "phone": pendingPhone,
                "client_id": config.clientId,
                "push_reg_id": "",
                "verify_token": verifyToken
            ],
            authenticated: false
        )

        let loginStatus = String(describing: loginJson["status"] ?? "0")
        let loginErrorCode = String(describing: loginJson["error_code"] ?? loginJson["status_code"] ?? "0")
        let loginData = (loginJson["data"] as? [String: Any]) ?? [:]

        if loginStatus == "1",
           let accessToken = loginData["access_token"] as? String,
           !accessToken.isEmpty {
            config.accessToken = accessToken
            config.accessTokenType = (loginData["access_token_type"] as? String) ?? "Bearer"
            config.phone = pendingPhone
            config.storedUnix = Int(Date().timeIntervalSince1970)
            await refreshAccountInfo(config: &config)
            FPTKeychain.save(config)
            resetPendingOtpState()

            return FPTPhoneAuthStatus(
                stage: "authenticated",
                message: "Đăng nhập thành công tài khoản \(config.phone ?? "") (UID: \(config.userId))!"
            )
        }

        // Trường hợp tài khoản đã đăng nhập đủ 5 thiết bị (error_code == 7):
        // Lấy danh sách 5 thiết bị đang đăng nhập từ POST account/device/limit_list để người dùng chọn gỡ ngay trên TV
        if loginErrorCode == "7" {
            let limitToken = (loginData["verify_token"] as? String) ?? verifyToken
            return try await fetchDeviceLimitList(config: config, limitVerifyToken: limitToken, fallbackMessage: (loginJson["msg"] as? String))
        }

        let msg = (loginJson["msg"] as? String) ?? "Đăng nhập thất bại (Mã lỗi: \(loginErrorCode))."
        return FPTPhoneAuthStatus(stage: "error", message: msg)
    }

    // MARK: - Xử lý khi tài khoản vượt quá giới hạn 5 thiết bị (POST account/device/limit_list & account/device/remove)
    private func fetchDeviceLimitList(
        config: FPTBootstrapConfig,
        limitVerifyToken: String,
        fallbackMessage: String?
    ) async throws -> FPTPhoneAuthStatus {
        let (_, listJson) = try await requestJSON(
            config: config,
            method: "POST",
            route: "account/device/limit_list",
            body: ["verify_token": limitVerifyToken],
            authenticated: false
        )

        let listData = (listJson["data"] as? [String: Any]) ?? [:]
        self.pendingRemoveDeviceToken = (listData["verify_token"] as? String) ?? limitVerifyToken
        let rawDevices = (listData["devices"] as? [[String: Any]]) ?? []

        var activeDevices: [FPTActiveDevice] = []
        for d in rawDevices {
            let id = String(describing: d["id"] ?? "")
            guard !id.isEmpty else { continue }
            let name = (d["device_name"] as? String) ?? "Thiết bị FPT Play"
            let dtype = (d["device_type"] as? String) ?? ""
            let time = (d["access_time"] as? String) ?? ""
            activeDevices.append(FPTActiveDevice(id: id, deviceName: name, deviceType: dtype, accessTime: time))
        }

        let desc = (listData["description"] as? String)
            ?? fallbackMessage
            ?? "Tài khoản đã đăng nhập đủ giới hạn 5 thiết bị. Hãy chọn 1 thiết bị bên dưới để đăng xuất và hoàn tất đăng nhập trên Apple TV:"

        return FPTPhoneAuthStatus(
            stage: "device_limit",
            message: desc,
            activeDevices: activeDevices
        )
    }

    // MARK: - Quản lý danh sách tối đa 5 thiết bị đang đăng nhập (GET account/device/list & POST account/device/delete)
    public func fetchLoggedInDevices(config: FPTBootstrapConfig) async -> [FPTActiveDevice] {
        guard config.isAuthenticated,
              let (_, json) = try? await requestJSON(config: config, method: "GET", route: "account/device/list", authenticated: true) else {
            return []
        }
        let data = (json["data"] as? [String: Any]) ?? [:]
        let rawDevices = (data["devices"] as? [[String: Any]]) ?? (data["device_list"] as? [[String: Any]]) ?? []
        var result: [FPTActiveDevice] = []
        for d in rawDevices {
            let id = (d["device_id"] as? String) ?? String(describing: d["id"] ?? "")
            guard !id.isEmpty else { continue }
            let name = (d["device_name"] as? String) ?? "Thiết bị FPT Play"
            let isCurrent = String(describing: d["is_current"] ?? "0") == "1"
            let dtype = isCurrent ? "Thiết bị này (Apple TV)" : ((d["device_icon"] as? String) ?? "Thiết bị khác")
            let time = (d["last_access"] as? String) ?? (d["access_time"] as? String) ?? ""
            result.append(FPTActiveDevice(id: id, deviceName: name, deviceType: dtype, accessTime: time))
        }
        return result
    }

    public func deleteLoggedInDevice(config: FPTBootstrapConfig, deviceId: String) async throws -> String {
        let (_, json) = try await requestJSON(
            config: config,
            method: "POST",
            route: "account/device/delete",
            body: ["device_id": deviceId],
            authenticated: true
        )
        let msg = (json["msg"] as? String) ?? ((json["data"] as? [String: Any])?["title"] as? String) ?? "Đã gỡ thiết bị khỏi danh sách 5 thiết bị."
        return msg
    }

    public func removeDeviceAndCompleteLogin(
        config: inout FPTBootstrapConfig,
        deviceId: String
    ) async throws -> FPTPhoneAuthStatus {
        let tokenToUse = pendingRemoveDeviceToken.isEmpty ? pendingLoginVerifyToken : pendingRemoveDeviceToken
        guard !tokenToUse.isEmpty else {
            return FPTPhoneAuthStatus(stage: "error", message: "Phiên xác thực đã hết hạn. Vui lòng bấm Gửi Mã OTP lại.")
        }

        let (_, remJson) = try await requestJSON(
            config: config,
            method: "POST",
            route: "account/device/remove",
            body: [
                "list_ids": [deviceId],
                "verify_token": tokenToUse
            ],
            authenticated: false
        )

        let remStatus = String(describing: remJson["status"] ?? "0")
        let remData = (remJson["data"] as? [String: Any]) ?? [:]

        if remStatus == "1",
           let accessToken = remData["access_token"] as? String,
           !accessToken.isEmpty {
            config.accessToken = accessToken
            config.accessTokenType = (remData["access_token_type"] as? String) ?? "Bearer"
            config.phone = pendingPhone
            config.storedUnix = Int(Date().timeIntervalSince1970)
            await refreshAccountInfo(config: &config)
            FPTKeychain.save(config)
            resetPendingOtpState()

            return FPTPhoneAuthStatus(
                stage: "authenticated",
                message: "Đã gỡ thiết bị cũ và đăng nhập thành công (UID: \(config.userId))!"
            )
        }

        // Nếu account/device/remove thành công nhưng chưa trả ngay access_token thì gọi lại account/user/login
        if remStatus == "1" && !pendingLoginVerifyToken.isEmpty {
            let (_, loginJson) = try await requestJSON(
                config: config,
                method: "POST",
                route: "account/user/login",
                body: [
                    "phone": pendingPhone,
                    "client_id": config.clientId,
                    "push_reg_id": "",
                    "verify_token": pendingLoginVerifyToken
                ],
                authenticated: false
            )
            if String(describing: loginJson["status"] ?? "0") == "1",
               let loginData = loginJson["data"] as? [String: Any],
               let accessToken = loginData["access_token"] as? String,
               !accessToken.isEmpty {
                config.accessToken = accessToken
                config.accessTokenType = (loginData["access_token_type"] as? String) ?? "Bearer"
                config.phone = pendingPhone
                config.storedUnix = Int(Date().timeIntervalSince1970)
                await refreshAccountInfo(config: &config)
                FPTKeychain.save(config)
                resetPendingOtpState()

                return FPTPhoneAuthStatus(
                    stage: "authenticated",
                    message: "Đã gỡ thiết bị cũ và đăng nhập thành công (UID: \(config.userId))!"
                )
            }
        }

        let errMsg = (remJson["msg"] as? String) ?? "Không gỡ được thiết bị cũ."
        return FPTPhoneAuthStatus(stage: "error", message: errMsg)
    }

    public func refreshAccountInfo(config: inout FPTBootstrapConfig) async {
        guard let (st, infoJson) = try? await requestJSON(config: config, route: "account/user/info"),
              st == 200 else { return }
        let dataDict = (infoJson["data"] as? [String: Any]) ?? infoJson
        let uidCandidates: [Any?] = [
            infoJson["user_id_str"],
            dataDict["user_id_str"],
            infoJson["user_id"],
            dataDict["user_id"]
        ]
        for cand in uidCandidates {
            if let s = cand as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                config.userId = s.trimmingCharacters(in: .whitespacesAndNewlines)
                break
            } else if let n = cand as? Int, n > 0 {
                config.userId = String(n)
                break
            }
        }
        if let phoneStr = (infoJson["phone"] as? String) ?? (dataDict["phone"] as? String), !phoneStr.isEmpty {
            config.phone = phoneStr
        }
        if let profile = (infoJson["profile"] as? [String: Any]) ?? (dataDict["profile"] as? [String: Any]) {
            config.profileId = String(describing: profile["profile_id"] ?? "")
            config.profileType = String(describing: profile["profile_type"] ?? "")
            config.profileMaturity = String(describing: profile["profile_maturity"] ?? "")
        }
    }

    private func resolveActiveUserId(
        config: FPTBootstrapConfig,
        sessionToken: String,
        merchant: String,
        sourceProvider: String = ""
    ) async -> String {
        let lowerSource = sourceProvider.lowercased()
        let lowerMerchant = merchant.lowercased()
        if lowerMerchant == "qnet" || lowerSource == "hbo" || lowerSource == "qnet" {
            if let jwtUid = extractJwtUserId(sessionToken), !jwtUid.isEmpty {
                return jwtUid
            }
        }

        var uid = config.userId.trimmingCharacters(in: .whitespacesAndNewlines)
        if uid.isEmpty && config.isAuthenticated {
            var mutableCfg = config
            await refreshAccountInfo(config: &mutableCfg)
            if !mutableCfg.userId.isEmpty {
                uid = mutableCfg.userId
                FPTKeychain.save(mutableCfg)
            }
        }
        if uid.isEmpty, let jwtUid = extractJwtUserId(sessionToken), !jwtUid.isEmpty {
            uid = jwtUid
        }
        return uid
    }

    private func buildFairPlayDRMConfig(
        enabled: Bool,
        config: FPTBootstrapConfig,
        sessionToken: String,
        merchant: String,
        sourceProvider: String = ""
    ) async -> FPTDRMConfig {
        guard enabled, !sessionToken.isEmpty, !merchant.isEmpty else {
            return FPTDRMConfig(enabled: false)
        }

        let userId = await resolveActiveUserId(
            config: config,
            sessionToken: sessionToken,
            merchant: merchant,
            sourceProvider: sourceProvider
        )

        // Chuẩn VodDetailFragment.java & fptplay.vn (597-1e4687141da3e606.js & 6195-e5581bdb4a15b3c8.js):
        // - Khi merchant == "fptplay" -> SigmaDRM (cert.sigmadrm.com / license.sigmadrm.com, header custom-data)
        // - Khi merchant != "fptplay" (ví dụ "galaxy", "qnet", "castlab"...) -> DRMtoday (lic.drmtoday.com, header x-dt-custom-data)
        if merchant.lowercased() == "fptplay" {
            let extraDict: [String: String] = ["playerVersion": "Shaka_4.3.6", "osDevice": "Mac OS"]
            let extraB64 = ((try? JSONSerialization.data(withJSONObject: extraDict)) ?? Data()).base64EncodedString()
            let customObj: [String: String] = [
                "userId": userId,
                "sessionId": sessionToken,
                "merchantId": merchant,
                "appId": "sigma",
                "extraData": extraB64
            ]
            let customData = (try? JSONSerialization.data(withJSONObject: customObj)) ?? Data()
            let headerVal = customData.base64EncodedString()
            return FPTDRMConfig(
                enabled: true,
                provider: "sigma",
                merchant: merchant,
                certUrl: "https://cert.sigmadrm.com/app/fairplay/fptplay/sigma",
                proxyCertUrl: nil,
                licenseUrl: "https://license.sigmadrm.com/license/verify/fairplay",
                proxyCkcUrl: nil,
                headerName: "custom-data",
                headerValue: headerVal
            )
        } else {
            let customObj: [String: String] = [
                "userId": userId,
                "sessionId": sessionToken,
                "merchant": merchant
            ]
            let customData = (try? JSONSerialization.data(withJSONObject: customObj)) ?? Data()
            let headerVal = customData.base64EncodedString()
            return FPTDRMConfig(
                enabled: true,
                provider: "drmtoday",
                merchant: merchant,
                certUrl: "https://lic.drmtoday.com/license-server-fairplay/cert/\(merchant)",
                proxyCertUrl: nil,
                licenseUrl: "https://lic.drmtoday.com/license-server-fairplay",
                proxyCkcUrl: nil,
                headerName: "x-dt-custom-data",
                headerValue: headerVal
            )
        }
    }

    // MARK: - Tải danh mục kênh & Lịch Thi Đấu Bóng Đá trực tiếp từ Apple TV
    public func fetchCatalog(config: FPTBootstrapConfig, forceEvents: Bool = false) async throws -> FPTCatalogResponse {
        if cachedRawChannels.isEmpty || forceEvents {
            let (st, payload) = try await requestJSON(config: config, route: "content/tv/channels")
            if st == 200,
               let dataObj = payload["data"] as? [String: Any],
               let chs = dataObj["channels"] as? [[String: Any]],
               !chs.isEmpty {
                cachedRawChannels = chs
            }
        }

        let liveEvents = await fetchLiveEvents(config: config, force: forceEvents)

        var intlDrmList: [FPTChannel] = []
        var intlOpenList: [FPTChannel] = []
        var vnTvList: [FPTChannel] = []

        let thvlDisplayNames: [String: String] = [
            "thvl1": "THVL1 HD — Vĩnh Long 1",
            "vinh-long-2": "THVL2 HD — Vĩnh Long 2",
            "vinh-long-3": "THVL3 HD — Vĩnh Long 3",
            "vinh-long-4-hd": "THVL4 HD — Vĩnh Long 4",
            "vinh-long-5": "THVL5 HD — Vĩnh Long 5"
        ]
        let thvlOrder: [String] = ["thvl1", "vinh-long-2", "vinh-long-3", "vinh-long-4-hd", "vinh-long-5"]
        let thvlDefaultLogos: [String: String] = [
            "thvl1": "https://images.fptplay53.net/media/channels/OTT_ECS/2026/07/10/thvl1.png",
            "vinh-long-2": "https://images.fptplay53.net/media/channels/OTT_ECS/2026/07/10/vinh-long-2.png",
            "vinh-long-3": "https://images.fptplay53.net/media/channels/OTT_ECS/2026/07/10/vinh-long-3.png",
            "vinh-long-4-hd": "https://images.fptplay53.net/media/channels/OTT_ECS/2026/07/10/vinh-long-4-hd.png",
            "vinh-long-5": "https://images.fptplay53.net/media/channels/OTT_ECS/2026/07/10/vinh-long-5.png"
        ]

        var seenIds: Set<String> = []

        for row in cachedRawChannels {
            let cid = ((row["id"] as? String) ?? (row["_id"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cid.isEmpty else { continue }
            seenIds.insert(cid)

            let rawName = ((row["name"] as? String) ?? (row["alias_name"] as? String) ?? cid).trimmingCharacters(in: .whitespacesAndNewlines)
            let name = thvlDisplayNames[cid] ?? rawName
            let origLogo = ((row["original_logo"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let thumbLogo = ((row["thumb"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let defaultCdnLogo = "https://images.fptplay53.net/media/channels/OTT_ECS/2026/07/10/\(cid).png"
            let logo = !origLogo.isEmpty ? origLogo : (!thumbLogo.isEmpty ? thumbLogo : (thvlDefaultLogos[cid] ?? defaultCdnLogo))
            let secondaryLogo = !thumbLogo.isEmpty ? thumbLogo : defaultCdnLogo

            let groupId = ((row["group_id"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let vmVal = String(describing: row["verimatrix"] ?? "0")
            let isDrm = (vmVal == "1" || vmVal.lowercased() == "true")

            let isThvl = thvlDisplayNames[cid] != nil || cid.hasPrefix("thvl") || cid.hasPrefix("vinh-long")
            let isIntlGroup = (groupId == "5767a33317dc1352af43cccb")

            if lockedIntlIds.contains(cid) || (isIntlGroup && isDrm) {
                intlDrmList.append(FPTChannel(
                    id: cid,
                    channelId: cid,
                    name: name,
                    badge: "QUỐC TẾ VIP • DRM",
                    categoryId: "intl_channels",
                    category: "🔒 KÊNH QUỐC TẾ VIP",
                    logo: logo,
                    portraitLogo: secondaryLogo,
                    desc: "Kênh quốc tế bản quyền \(name) trên FPT Play (Giải mã phần cứng Apple FairPlay).",
                    is4K: false,
                    isDRM: true,
                    isLive: true,
                    statusText: "TRỰC TIẾP",
                    resolution: "Full HD (H.264)",
                    fps: "FairPlay DRM"
                ))
            } else if openIntlIds.contains(cid) || isIntlGroup {
                intlOpenList.append(FPTChannel(
                    id: cid,
                    channelId: cid,
                    name: name,
                    badge: "QUỐC TẾ MỞ RỘNG",
                    categoryId: "intl_channels",
                    category: "🌍 QUỐC TẾ MỞ RỘNG",
                    logo: logo,
                    portraitLogo: secondaryLogo,
                    desc: "Kênh truyền hình quốc tế \(name) phát sóng trực tiếp trên FPT Play.",
                    is4K: false,
                    isDRM: false,
                    isLive: true,
                    statusText: "TRỰC TIẾP",
                    resolution: "Full HD (H.264)",
                    fps: "HLS Native"
                ))
            } else {
                let vnGroupBadge: String
                if cid.hasPrefix("vtv") {
                    vnGroupBadge = "KÊNH VTV QUỐC GIA"
                } else if isThvl {
                    vnGroupBadge = "TRUYỀN HÌNH VĨNH LONG (THVL)"
                } else if cid.hasPrefix("htv") {
                    vnGroupBadge = "ĐÀI TP.HCM (HTV / HTVC)"
                } else if groupId == "55572fcd17dc13323f89f966" {
                    vnGroupBadge = "KÊNH ĐỊA PHƯƠNG"
                } else {
                    vnGroupBadge = "KÊNH THIẾT YẾU & TRUNG ƯƠNG"
                }

                vnTvList.append(FPTChannel(
                    id: cid,
                    channelId: cid,
                    name: name,
                    badge: vnGroupBadge,
                    categoryId: "vn_channels",
                    category: "📺 TRUYỀN HÌNH VIỆT NAM",
                    logo: logo,
                    portraitLogo: secondaryLogo,
                    desc: "Kênh truyền hình \(name) phát sóng trực tiếp trên FPT Play.",
                    is4K: false,
                    isDRM: isDrm,
                    isLive: true,
                    statusText: "TRỰC TIẾP",
                    resolution: "Full HD (H.264)",
                    fps: "HLS Native"
                ))
            }
        }

        // Đảm bảo luôn có đầy đủ 5 kênh THVL (THVL1 -> THVL5) nằm liền kề nhau theo thứ tự 1 -> 5 trong mục VTV • HTV • THVL
        for tid in thvlOrder where !vnTvList.contains(where: { $0.channelId == tid }) {
            let name = thvlDisplayNames[tid] ?? tid
            let logo = thvlDefaultLogos[tid] ?? "https://images.fptplay53.net/media/channels/OTT_ECS/2026/07/10/\(tid).png"
            vnTvList.append(FPTChannel(
                id: tid,
                channelId: tid,
                name: name,
                badge: "TRUYỀN HÌNH VĨNH LONG (THVL)",
                categoryId: "vn_channels",
                category: "📺 TRUYỀN HÌNH VIỆT NAM",
                logo: logo,
                portraitLogo: logo,
                desc: "Kênh truyền hình \(name) phát sóng trực tiếp trên FPT Play.",
                is4K: false,
                isDRM: false,
                isLive: true,
                statusText: "TRỰC TIẾP",
                resolution: "Full HD (H.264)",
                fps: "HLS Native"
            ))
        }
        let thvlChannelsInVn = thvlOrder.compactMap { tid in vnTvList.first(where: { $0.channelId == tid }) }
        let nonThvlInVn = vnTvList.filter { !thvlOrder.contains($0.channelId) }
        if let firstHtvOrVtvEnd = nonThvlInVn.lastIndex(where: { $0.channelId.hasPrefix("vtv") || $0.channelId.hasPrefix("htv7") || $0.channelId.hasPrefix("htv9") }) {
            var arranged = Array(nonThvlInVn.prefix(firstHtvOrVtvEnd + 1))
            arranged.append(contentsOf: thvlChannelsInVn)
            arranged.append(contentsOf: nonThvlInVn.dropFirst(firstHtvOrVtvEnd + 1))
            vnTvList = arranged
        } else {
            vnTvList = thvlChannelsInVn + nonThvlInVn
        }

        // Nếu chưa đăng nhập khiến API ẩn bớt danh sách 20 kênh Quốc tế khóa mã, vẫn hiển thị đủ 20 kênh kèm Logo chính chủ FPT Play CDN
        if intlDrmList.isEmpty {
            let fallbackIntlDrm: [(String, String)] = [
                ("cnn", "CNN International"),
                ("bbc-news", "BBC News HD"),
                ("hbo", "HBO HD"),
                ("max-by-hbo", "Max by HBO (Cinemax)"),
                ("warner-tv", "Warner TV HD"),
                ("axn", "AXN HD"),
                ("cinemaworld", "CinemaWorld HD"),
                ("discovery", "Discovery Channel"),
                ("discovery-asia", "Discovery Asia"),
                ("bbc-earth", "BBC Earth HD"),
                ("animal-planet", "Animal Planet"),
                ("travel-living", "TLC (Travel & Living)"),
                ("bbc-lifestyle", "BBC Lifestyle"),
                ("fashion-tv", "Fashion TV HD"),
                ("bloomberg", "Bloomberg TV"),
                ("australia-plus", "ABC Australia"),
                ("cartoon-network", "Cartoon Network HD"),
                ("dreamworks", "DreamWorks HD"),
                ("cartoonito", "Cartoonito"),
                ("cbeebies", "CBeebies")
            ]
            for (cid, cname) in fallbackIntlDrm {
                let cdnLogo = "https://images.fptplay53.net/media/channels/OTT_ECS/2026/07/10/\(cid).png"
                let cdnThumb = "https://images.fptplay53.net/media/channels/OTT_ECS/2026/07/06/\(cid).png"
                intlDrmList.append(FPTChannel(
                    id: cid,
                    channelId: cid,
                    name: cname,
                    badge: "QUỐC TẾ VIP • DRM",
                    categoryId: "intl_channels",
                    category: "🔒 KÊNH QUỐC TẾ VIP",
                    logo: cdnLogo,
                    portraitLogo: cdnThumb,
                    desc: "Kênh quốc tế bản quyền \(cname) trên FPT Play (Giải mã phần cứng Apple FairPlay).",
                    is4K: false,
                    isDRM: true,
                    isLive: true,
                    statusText: "TRỰC TIẾP",
                    resolution: "Full HD (H.264)",
                    fps: "FairPlay DRM"
                ))
            }
        }

        let vodLists = await fetchVodCatalog(config: config, force: forceEvents)
        let intlChannels = intlDrmList + intlOpenList

        let categories: [FPTCategory] = [
            FPTCategory(id: "live_football", title: "Trực Tiếp", icon: "dot.radiowaves.left.and.right", channels: liveEvents),
            FPTCategory(id: "vod_series", title: "Phim Bộ", icon: "film.stack.fill", channels: vodLists.series),
            FPTCategory(id: "vod_movies", title: "Phim Lẻ", icon: "popcorn.fill", channels: vodLists.movies),
            FPTCategory(id: "intl_channels", title: "Kênh Nước Ngoài", icon: "globe.americas.fill", channels: intlChannels),
            FPTCategory(id: "vn_channels", title: "Kênh Trong Nước", icon: "tv.fill", channels: vnTvList)
        ]

        return FPTCatalogResponse(
            ok: true,
            updatedAt: Int(Date().timeIntervalSince1970),
            authenticated: config.isAuthenticated,
            userId: config.userId,
            categories: categories
        )
    }

    private func formatMatchTime(beginTs: Int?, fallbackLabel: String) -> String {
        guard let ts = beginTs, ts > 0 else { return fallbackLabel }
        let date = Date(timeIntervalSince1970: TimeInterval(ts))
        let fmt = DateFormatter()
        fmt.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")
        fmt.dateFormat = "HH:mm • dd/MM"
        return fmt.string(from: date)
    }

    private func fetchLiveEvents(config: FPTBootstrapConfig, force: Bool) async -> [FPTChannel] {
        let now = Date().timeIntervalSince1970
        if !force && !cachedLiveEvents.isEmpty && (now - lastEventsFetchTime) < 60 {
            return cachedLiveEvents
        }

        var scoredEvents: [(priority: Int, beginTs: Int, channel: FPTChannel)] = []
        var seenEventIds: Set<String> = []

        // Quét đầy đủ cả trang Thể Thao tổng hợp ("sport" - chứa NBA, Pickleball, V.League, Bóng rổ, Bóng chuyền, Võ thuật, eSports...),
        // trang Sự Kiện ("event"), Ngoại Hạng Anh ("ngoai-hang-anh"), Võ Thuật/Đối Kháng ("ufc", "doi-khang") và Trang chủ ("home")
        for pageId in ["sport", "event", "ngoai-hang-anh", "ufc", "doi-khang", "home"] {
            guard let (st, pagePayload) = try? await requestJSON(config: config, route: "navigation/page/\(pageId)"),
                  st == 200,
                  let dataObj = pagePayload["data"] as? [String: Any],
                  let blocks = dataObj["blocks"] as? [[String: Any]] else {
                continue
            }

            for blk in blocks {
                let btype = (blk["data_type"] as? String) ?? (blk["block_type"] as? String) ?? (blk["type"] as? String) ?? ""
                let bid = String(describing: blk["id"] ?? blk["_id"] ?? "")
                var items = (blk["content"] as? [[String: Any]]) ?? (blk["items"] as? [[String: Any]]) ?? (blk["data"] as? [[String: Any]]) ?? []

                if items.isEmpty && (btype == "highlight" || btype == "live_event" || btype == "event" || btype == "horizontal_slider") && !bid.isEmpty {
                    // Trên trang "home", chỉ lấy các block Nổi bật hoặc Thể thao để tốc độ tải nhanh nhất
                    if pageId == "home" && bid != "632f01322089bd00e5c5ed3d" && bid != "5677cc4a17dc1342ea2d9b48" {
                        continue
                    }
                    if let (hlCode, hlPayload) = try? await requestJSON(
                        config: config,
                        route: "playos/block/\(btype.isEmpty ? "highlight" : btype)/\(bid)",
                        extraQuery: [("page_id", pageId)]
                    ), hlCode == 200 {
                        if let hlArr = hlPayload["data"] as? [[String: Any]] {
                            items = hlArr
                        } else if let hlDict = hlPayload["data"] as? [String: Any] {
                            items = (hlDict["content"] as? [[String: Any]]) ?? (hlDict["items"] as? [[String: Any]]) ?? []
                        }
                    }
                }

                for item in items {
                    let itemType = (item["type"] as? String) ?? ""
                    guard ["event", "livetv", "premiere"].contains(itemType) else { continue }
                    let evId = String(describing: item["highlight_id"] ?? item["id"] ?? item["_id"] ?? "")
                    guard !evId.isEmpty, !seenEventIds.contains(evId) else { continue }
                    if scoredEvents.count >= 48 { break }

                    guard let (detCode, detPayload) = try? await requestJSON(config: config, route: "event/detail/\(evId)"),
                          detCode == 200,
                          let evData = detPayload["data"] as? [String: Any] else {
                        continue
                    }

                    let channelId = ((evData["id"] as? String) ?? (evData["asset_id"] as? String) ?? (item["id"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let title = ((evData["title"] as? String) ?? (item["title"] as? String) ?? (item["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !channelId.isEmpty, !title.isEmpty else { continue }
                    seenEventIds.insert(evId)

                    let is4K = channelId.lowercased().contains("4k") || title.lowercased().contains("4k")
                    let vmxStr = String(describing: evData["verimatrix"] ?? evData["drm"] ?? "1").lowercased()
                    let isDrmEvent = (vmxStr == "1" || vmxStr == "true")
                    let imgObj = (item["image"] as? [String: Any]) ?? [:]
                    let evImgObj = (evData["image"] as? [String: Any]) ?? [:]
                    let thumb = (evImgObj["landscape_title"] as? String)
                        ?? (evImgObj["landscape"] as? String)
                        ?? (imgObj["landscape_title"] as? String)
                        ?? (imgObj["landscape"] as? String)
                        ?? (evImgObj["portrait"] as? String)
                        ?? (imgObj["portrait"] as? String)
                        ?? (evData["image"] as? String)
                        ?? ""
                    let rawLabel = (evData["label_time"] as? String) ?? (item["label_event"] as? String) ?? "TRỰC TIẾP"

                    let beginInt = Int(String(describing: evData["begin_time"] ?? item["begin_time"] ?? ""))
                    let endInt = Int(String(describing: evData["end_time"] ?? item["end_time"] ?? ""))

                    var isLiveNow = true
                    var matchStateBadge = "🔴 ĐANG TRỰC TIẾP"
                    var sortPriority = 0
                    if let bVal = beginInt {
                        let eVal = endInt ?? (bVal + 10800)
                        if now < Double(bVal - 900) {
                            isLiveNow = false
                            matchStateBadge = "⏳ SẮP DIỄN RA"
                            sortPriority = 1
                        } else if now <= Double(eVal) {
                            isLiveNow = true
                            matchStateBadge = "🔴 ĐANG TRỰC TIẾP"
                            sortPriority = 0
                        } else {
                            isLiveNow = false
                            matchStateBadge = "✅ KẾT THÚC"
                            sortPriority = 2
                        }
                    }

                    let metaArr = (evData["meta_data"] as? [String]) ?? []
                    let tournamentTag = metaArr.first ?? ""
                    let scheduleStr = formatMatchTime(beginTs: beginInt, fallbackLabel: rawLabel)
                    let baseDesc = (evData["description"] as? String) ?? "Lịch phát sóng: \(scheduleStr) trên kênh \(channelId)"
                    let desc = tournamentTag.isEmpty ? baseDesc : "[\(tournamentTag)] \(baseDesc)"

                    let ch = FPTChannel(
                        id: "event_\(evId)",
                        channelId: channelId,
                        eventId: evId,
                        name: title,
                        badge: matchStateBadge,
                        categoryId: "live_football",
                        category: "⚽ THỂ THAO & BÓNG ĐÁ",
                        logo: thumb,
                        desc: desc,
                        is4K: is4K,
                        isDRM: isDrmEvent,
                        isLive: isLiveNow,
                        statusText: scheduleStr,
                        resolution: is4K ? "4K UHD (HEVC)" : "Full HD (1080p)",
                        fps: isLiveNow ? "ĐANG TRỰC TIẾP" : "SẮP DIỄN RA"
                    )
                    scoredEvents.append((priority: sortPriority, beginTs: beginInt ?? Int(now), channel: ch))
                }
            }
        }

        // Sắp xếp các trận ĐANG TRỰC TIẾP (Pickleball, V.League, Ngoại Hạng Anh...) lên đầu tiên, sau đó đến SẮP DIỄN RA theo giờ gần nhất
        scoredEvents.sort { a, b in
            if a.priority != b.priority {
                return a.priority < b.priority
            }
            return a.beginTs < b.beginTs
        }

        let eventsOut = scoredEvents.map { $0.channel }
        if !eventsOut.isEmpty {
            cachedLiveEvents = eventsOut
            lastEventsFetchTime = now
        }
        return eventsOut
    }

    // MARK: - Kho Phim Bộ (Series) & Phim Lẻ (Movies) Chính Chủ Trên FPT Play
    private func fetchVodCatalog(config: FPTBootstrapConfig, force: Bool) async -> (series: [FPTChannel], movies: [FPTChannel]) {
        let now = Date().timeIntervalSince1970
        if !force && !cachedVodSeries.isEmpty && !cachedVodMovies.isEmpty && (now - lastVodFetchTime) < 300 {
            return (cachedVodSeries, cachedVodMovies)
        }

        let blockSources: [(blockId: String, pageId: String, defaultSeries: Bool, tag: String)] = [
            // Khối Phim Bộ (Series)
            ("560e365717dc1310a164d2c4", "series", true, "PHIM BỘ HOT"),
            ("6ad1ea1b38dceae2c12f723c", "home", true, "PHIM HÀN QUỐC"),
            ("6628dbc38ab1b9023508e354", "series", true, "PHIM VIỆT NAM"),
            ("627b59eb2089bd00386079d4", "series", true, "PHIM HOA NGỮ"),
            ("63631a652089bd04b9e70d0b", "series", true, "PHIM TUYỂN CHỌN"),
            ("66053d1bd9a42107fe4eaf75", "series", true, "CỔ TRANG ĐẶC SẮC"),
            ("6269b6d52089bd00b05311fa", "series", true, "NGÔN TÌNH ĐÔ THỊ"),
            ("67e53297184c02cd18da0c6c", "series", true, "SERIES HÀNH ĐỘNG"),
            ("6a3e2000fad62b23dc0b535a", "series", true, "SERIES CHÂU Á"),
            ("67f5e9fbbd9557710ff86b80", "home", true, "PHIM MIỄN PHÍ"),
            // Khối Phim Lẻ & Điện Ảnh (Movies)
            ("6792f82f66b2fca51fead01b", "home", false, "PHIM LẺ NỔI BẬT"),
            ("galaxy-play", "galaxy-play", false, "GALAXY PLAY"),
            ("689043280df66119217d4c85", "home", false, "ĐIỆN ẢNH HOLLYWOOD"),
            ("6abb561c42e991e58eed1857", "home", false, "HÀNH ĐỘNG & SINH TỒN"),
            ("6715f4b0fed30100ac5452b4", "home", false, "ĐIỆN ẢNH GIẬT GÂN"),
            ("6ab210559b1a69b33f62a4aa", "home", false, "TÂM LÝ • TÌNH CẢM"),
            ("67dbec82af85eefa21f4dc3b", "series", false, "ĐIỆN ẢNH CHÂU Á"),
            ("5677cc4a17dc1342ea2d9b48", "home", false, "TOP THỊNH HÀNH"),
            ("5a309d2f5583204230df1af4", "home", false, "PHIM ĐẶC SẮC")
        ]

        var fetchedBlocks: [(index: Int, defaultSeries: Bool, tag: String, items: [[String: Any]])] = []
        await withTaskGroup(of: (Int, Bool, String, [[String: Any]])?.self) { group in
            for (idx, src) in blockSources.enumerated() {
                group.addTask { [weak self] in
                    guard let self = self else { return nil }
                    guard let (st, payload) = try? await self.requestJSON(
                        config: config,
                        route: "playos/block/highlight/\(src.blockId)",
                        extraQuery: [("page_id", src.pageId)]
                    ), st == 200 else {
                        return nil
                    }
                    if let arr = payload["data"] as? [[String: Any]] {
                        return (idx, src.defaultSeries, src.tag, arr)
                    } else if let dict = payload["data"] as? [String: Any],
                              let arr = (dict["content"] as? [[String: Any]]) ?? (dict["items"] as? [[String: Any]]) {
                        return (idx, src.defaultSeries, src.tag, arr)
                    }
                    return nil
                }
            }
            for await result in group {
                if let res = result {
                    fetchedBlocks.append(res)
                }
            }
        }

        fetchedBlocks.sort { $0.index < $1.index }

        var seriesList: [FPTChannel] = []
        var moviesList: [FPTChannel] = []
        var seenSeriesIds: Set<String> = []
        var seenMovieIds: Set<String> = []

        for blk in fetchedBlocks {
            for item in blk.items {
                let itemType = (item["type"] as? String) ?? ""
                guard itemType == "vod" || itemType.isEmpty else { continue }
                let vodId = String(describing: item["id"] ?? item["_id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let title = ((item["title"] as? String) ?? (item["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !vodId.isEmpty, !title.isEmpty else { continue }

                let appId = String(describing: item["app_id"] ?? "")
                let detailObj = (item["detail"] as? [String: Any]) ?? [:]
                let durationStr = ((detailObj["duration_s"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let countryStr = ((detailObj["country"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let ageStr = ((detailObj["age_rating"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let shortDesc = ((detailObj["short_description"] as? String) ?? (detailObj["description"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let metaArr = (detailObj["meta_data"] as? [String]) ?? []
                let yearStr = metaArr.first ?? ""

                let isSeriesItem: Bool
                if appId == "77" || durationStr.lowercased().contains("tập") {
                    isSeriesItem = true
                } else if appId == "71" || appId == "87" {
                    isSeriesItem = false
                } else {
                    isSeriesItem = blk.defaultSeries
                }

                let imgObj = (item["image"] as? [String: Any]) ?? [:]
                let poster = (imgObj["landscape"] as? String)
                    ?? (imgObj["landscape_title"] as? String)
                    ?? (imgObj["portrait"] as? String)
                    ?? (imgObj["thumb"] as? String)
                    ?? ""
                let portraitPoster = (imgObj["portrait"] as? String)
                    ?? (imgObj["standing"] as? String)
                    ?? (item["standing_thumb"] as? String)
                    ?? (imgObj["landscape_title"] as? String)
                    ?? poster
                let titleLogo = (imgObj["title"] as? String) ?? ""

                let metaParts = [yearStr, countryStr, ageStr, durationStr].filter { !$0.isEmpty }
                let metaLine = metaParts.joined(separator: " • ")
                let fullDesc: String
                if !shortDesc.isEmpty && !metaLine.isEmpty {
                    fullDesc = "[\(metaLine)] \(shortDesc)"
                } else if !shortDesc.isEmpty {
                    fullDesc = shortDesc
                } else if !metaLine.isEmpty {
                    fullDesc = "Phim bản quyền trên FPT Play (\(metaLine)). Hỗ trợ Thuyết minh & Phụ đề Tiếng Việt."
                } else {
                    fullDesc = "Phim bản quyền trên FPT Play. Hỗ trợ Thuyết minh & Phụ đề Tiếng Việt."
                }

                let statusLabel = !durationStr.isEmpty ? durationStr : (isSeriesItem ? "Trọn bộ" : "Phim lẻ")
                let subAudioTag = isSeriesItem ? "Chọn Tập • TM/Phụ Đề" : "Phát Ngay • TM/Phụ Đề"

                if isSeriesItem {
                    guard !seenSeriesIds.contains(vodId) else { continue }
                    seenSeriesIds.insert(vodId)
                    seriesList.append(FPTChannel(
                        id: "vod_series_\(vodId)",
                        channelId: vodId,
                        name: title,
                        badge: "🎞️ \(blk.tag)",
                        categoryId: "vod_series",
                        category: "🎞️ PHIM BỘ ĐẶC SẮC",
                        logo: poster,
                        portraitLogo: portraitPoster,
                        titleLogo: titleLogo,
                        desc: fullDesc,
                        is4K: true,
                        isDRM: false,
                        isLive: false,
                        statusText: statusLabel,
                        resolution: countryStr.isEmpty ? "Full HD / 4K HEVC" : "\(countryStr) • FHD/4K",
                        fps: subAudioTag,
                        isVod: true,
                        isSeries: true,
                        vodId: vodId,
                        episodeId: "0"
                    ))
                } else {
                    guard !seenMovieIds.contains(vodId) else { continue }
                    seenMovieIds.insert(vodId)
                    moviesList.append(FPTChannel(
                        id: "vod_movie_\(vodId)",
                        channelId: vodId,
                        name: title,
                        badge: "🎬 \(blk.tag)",
                        categoryId: "vod_movies",
                        category: "🎬 PHIM LẺ & ĐIỆN ẢNH",
                        logo: poster,
                        portraitLogo: portraitPoster,
                        titleLogo: titleLogo,
                        desc: fullDesc,
                        is4K: true,
                        isDRM: false,
                        isLive: false,
                        statusText: statusLabel,
                        resolution: countryStr.isEmpty ? "Full HD / 4K HEVC" : "\(countryStr) • FHD/4K",
                        fps: subAudioTag,
                        isVod: true,
                        isSeries: false,
                        vodId: vodId,
                        episodeId: "0"
                    ))
                }
            }
        }

        if !seriesList.isEmpty {
            cachedVodSeries = seriesList
        }
        if !moviesList.isEmpty {
            cachedVodMovies = moviesList
        }
        if !seriesList.isEmpty || !moviesList.isEmpty {
            lastVodFetchTime = now
        }
        return (seriesList, moviesList)
    }

    // MARK: - Tìm kiếm toàn bộ Kho Phim Bộ & Phim Lẻ trên máy chủ FPT Play (GET search/vod)
    public func searchVod(
        config: FPTBootstrapConfig,
        query: String,
        page: Int = 1,
        pageSize: Int = 36
    ) async throws -> (total: Int, results: [FPTChannel]) {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else { return (0, []) }

        let (st, payload) = try await requestJSON(
            config: config,
            route: "search/vod",
            extraQuery: [
                ("action", "search"),
                ("query_str", cleanQuery),
                ("page_index", String(max(1, page))),
                ("page_size", String(max(12, pageSize))),
                ("type", ""),
                ("search_version", "v2")
            ],
            authenticated: config.isAuthenticated
        )
        guard st == 200 else {
            throw NSError(
                domain: "FPTDirectClient",
                code: st,
                userInfo: [NSLocalizedDescriptionKey: "Lỗi kết nối máy chủ tìm kiếm FPT Play (HTTP \(st))."]
            )
        }

        let rawResults = (payload["result"] as? [[String: Any]])
            ?? ((payload["data"] as? [String: Any])?["result"] as? [[String: Any]])
            ?? []
        let totalCount = (payload["total"] as? Int) ?? Int(String(describing: payload["total"] ?? "")) ?? rawResults.count

        var scoredOut: [(priority: Int, channel: FPTChannel)] = []
        var seenIds: Set<String> = []

        for item in rawResults {
            let vodId = ((item["id"] as? String) ?? (item["_id"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let title = ((item["title"] as? String) ?? (item["title_vie"] as? String) ?? (item["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !vodId.isEmpty, !title.isEmpty, !seenIds.contains(vodId) else { continue }
            seenIds.insert(vodId)

            let appId = String(describing: item["app_id"] ?? "")
            let epTotalStr = String(describing: item["episode_total"] ?? item["playlist_total"] ?? "1")
            let epTotalInt = Int(epTotalStr) ?? 1

            let detailObj = (item["detail"] as? [String: Any]) ?? [:]
            let durationStr = ((detailObj["duration_s"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let countryStr = ((detailObj["country"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let ageStr = ((detailObj["age_rating"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let releaseStr = ((detailObj["release"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let descStr = ((detailObj["description"] as? String) ?? (detailObj["short_description"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let catStr = ((item["category"] as? String) ?? (item["sub_category"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            let isSeriesItem: Bool
            if appId == "77" || epTotalInt > 1 || durationStr.lowercased().contains("tập") {
                isSeriesItem = true
            } else {
                isSeriesItem = false
            }

            let imgObj = (item["image"] as? [String: Any]) ?? [:]
            let poster = (imgObj["landscape"] as? String)
                ?? (imgObj["landscape_title"] as? String)
                ?? (item["thumb"] as? String)
                ?? (imgObj["portrait"] as? String)
                ?? ""
            let portraitPoster = (imgObj["portrait"] as? String)
                ?? (item["standing_thumb"] as? String)
                ?? (imgObj["standing"] as? String)
                ?? poster
            let titleLogo = (imgObj["title"] as? String) ?? ""

            let metaParts = [releaseStr, countryStr, ageStr, durationStr, catStr].filter { !$0.isEmpty }
            let metaLine = metaParts.joined(separator: " • ")
            let fullDesc: String
            if !descStr.isEmpty && !metaLine.isEmpty {
                fullDesc = "[\(metaLine)] \(descStr)"
            } else if !descStr.isEmpty {
                fullDesc = descStr
            } else if !metaLine.isEmpty {
                fullDesc = "Phim bản quyền trên FPT Play (\(metaLine))."
            } else {
                fullDesc = "Phim bản quyền trên FPT Play."
            }

            let statusLabel: String
            if !durationStr.isEmpty {
                statusLabel = durationStr
            } else if isSeriesItem && epTotalInt > 1 {
                statusLabel = "\(epTotalInt) tập"
            } else {
                statusLabel = isSeriesItem ? "Phim bộ" : "Phim lẻ"
            }

            // Ưu tiên Phim Bộ (77), Phim Lẻ Điện Ảnh (71), Galaxy Play (87), Anime (72) lên trên các clip ngắn (79, 23)
            let priority: Int
            if ["71", "87", "77", "72"].contains(appId) {
                priority = 0
            } else if epTotalInt > 1 {
                priority = 1
            } else {
                priority = 2
            }

            let ch = FPTChannel(
                id: "search_\(vodId)",
                channelId: vodId,
                name: title,
                badge: isSeriesItem ? "🎞️ PHIM BỘ" : "🎬 PHIM LẺ",
                categoryId: isSeriesItem ? "vod_series" : "vod_movies",
                category: isSeriesItem ? "Phim Bộ" : "Phim Lẻ",
                logo: poster,
                portraitLogo: portraitPoster,
                titleLogo: titleLogo,
                desc: fullDesc,
                is4K: true,
                isDRM: false,
                isLive: false,
                statusText: statusLabel,
                resolution: countryStr.isEmpty ? "Full HD / 4K HEVC" : "\(countryStr) • FHD/4K",
                fps: isSeriesItem ? "Chọn Tập • TM/Phụ Đề" : "Phát Ngay • TM/Phụ Đề",
                isVod: true,
                isSeries: isSeriesItem,
                vodId: vodId,
                episodeId: "0"
            )
            scoredOut.append((priority: priority, channel: ch))
        }

        scoredOut.sort { $0.priority < $1.priority }
        return (totalCount, scoredOut.map { $0.channel })
    }

    // MARK: - Lấy chi tiết bộ phim & Danh sách tập (GET content/vod/{vodId}) chuẩn VodDetailV2 trên G2
    public func fetchVodDetail(
        config: FPTBootstrapConfig,
        vodId: String,
        fallbackChannel: FPTChannel? = nil
    ) async throws -> FPTVodDetail {
        let cleanVodId = vodId.trimmingCharacters(in: .whitespacesAndNewlines)
        let (st, payload) = try await requestJSON(
            config: config,
            route: "content/vod/\(cleanVodId)",
            extraQuery: [("data_type", "")]
        )
        guard st == 200, let dataObj = payload["data"] as? [String: Any] else {
            throw NSError(
                domain: "FPTDirectClient",
                code: st,
                userInfo: [NSLocalizedDescriptionKey: "Không tải được thông tin chi tiết phim từ FPT Play (HTTP \(st))."]
            )
        }

        let title = ((dataObj["title"] as? String) ?? (dataObj["title_vie"] as? String) ?? fallbackChannel?.name ?? cleanVodId).trimmingCharacters(in: .whitespacesAndNewlines)
        let shortDesc = ((dataObj["short_description"] as? String) ?? (dataObj["title_origin"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let rawDescStr = ((dataObj["description"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let desc = !rawDescStr.isEmpty ? rawDescStr : (!shortDesc.isEmpty ? shortDesc : (fallbackChannel?.desc ?? ""))
        let imgObj = (dataObj["image"] as? [String: Any]) ?? [:]
        let poster = (imgObj["landscape"] as? String)
            ?? (imgObj["landscape_title"] as? String)
            ?? (dataObj["banner_thumb"] as? String)
            ?? (imgObj["portrait"] as? String)
            ?? (imgObj["thumb"] as? String)
            ?? fallbackChannel?.logo
            ?? ""
        let portraitPoster = (imgObj["portrait"] as? String)
            ?? (dataObj["standing_thumb"] as? String)
            ?? fallbackChannel?.portraitLogo
            ?? poster
        let titleLogo = (imgObj["title"] as? String)
            ?? (dataObj["title_image"] as? String)
            ?? fallbackChannel?.titleLogo
            ?? ""

        let epTypeStr = String(describing: dataObj["episode_type"] ?? "0")
        let epTotalStr = String(describing: dataObj["episode_total"] ?? "")
        let drmStr = String(describing: dataObj["drm"] ?? "0")
        let isDrm = (drmStr == "1" || drmStr.lowercased() == "true")

        let metaArr = ((dataObj["meta_data"] as? [String]) ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let yearText = metaArr.first ?? ((dataObj["movie_release_date"] as? String) ?? "")
        let country = ((dataObj["countries"] as? String) ?? (dataObj["country"] as? String) ?? (dataObj["nation"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let maturityObj = (dataObj["maturity_rating"] as? [String: Any]) ?? [:]
        let ageRating = ((dataObj["age_rating"] as? String) ?? (maturityObj["value"] as? String) ?? (maturityObj["prefix"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var genres: [String] = []
        if let gArr = dataObj["genres"] as? [String] {
            genres = gArr.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        } else if let tagArr = dataObj["tags_genre"] as? [[String: Any]] {
            genres = tagArr.compactMap { ($0["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        let trailerObj = (dataObj["trailer_info"] as? [String: Any]) ?? [:]
        let trailerUrl = (trailerObj["url"] as? String) ?? (dataObj["trailer_url"] as? String) ?? ""

        let rawEpisodes = (dataObj["episodes"] as? [[String: Any]]) ?? []
        var episodes: [FPTEpisode] = []
        for (idx, ep) in rawEpisodes.enumerated() {
            let epId = String(describing: ep["id"] ?? "\(idx)")
            let rawEpTitle = ((ep["title"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let epTitle = rawEpTitle.isEmpty ? "Tập \(idx + 1)" : rawEpTitle
            let epThumb = (ep["thumb"] as? String) ?? poster
            let epDur = (ep["duration_s"] as? String) ?? ""
            let epDesc = (ep["description"] as? String) ?? ""
            let epAuto = (ep["auto_profile"] as? String) ?? "adaptive_bitrate"
            let vipVal = String(describing: ep["is_vip"] ?? "0")
            let prevVal = String(describing: ep["is_preview"] ?? "0")

            episodes.append(FPTEpisode(
                id: epId,
                title: epTitle,
                thumb: epThumb,
                durationText: epDur,
                desc: epDesc,
                autoProfile: epAuto,
                isVip: vipVal == "1" || vipVal.lowercased() == "true",
                isPreview: prevVal == "1" || prevVal.lowercased() == "true"
            ))
        }

        if episodes.isEmpty {
            episodes.append(FPTEpisode(
                id: "0",
                title: title,
                thumb: poster,
                durationText: fallbackChannel?.statusText ?? "",
                desc: desc,
                autoProfile: "adaptive_bitrate",
                isVip: false,
                isPreview: false
            ))
        }

        // Bóc tách Diễn viên & Đạo diễn (actors) và Nội dung tương tự (relatedVods) từ mảng blocks của VodDetailV2
        var actors: [FPTActor] = []
        var relatedVods: [FPTChannel] = []
        var seenActorIds: Set<String> = []
        var seenRelatedIds: Set<String> = []

        if let blocksArr = dataObj["blocks"] as? [[String: Any]] {
            for blk in blocksArr {
                let blkType = ((blk["block_type"] as? String) ?? (blk["type"] as? String) ?? "").lowercased()
                let blkName = ((blk["name"] as? String) ?? (blk["title"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let items = (blk["content"] as? [[String: Any]]) ?? (blk["items"] as? [[String: Any]]) ?? (blk["data"] as? [[String: Any]]) ?? []

                for item in items {
                    let itemType = ((item["type"] as? String) ?? "").lowercased()
                    let itemId = String(describing: item["id"] ?? item["_id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let itemTitle = ((item["title"] as? String) ?? (item["name"] as? String) ?? (item["full_name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !itemTitle.isEmpty else { continue }
                    let itemImgObj = (item["image"] as? [String: Any]) ?? [:]

                    if itemType == "people" || blkType.contains("circle") || blkType.contains("people") || blkName.lowercased().contains("diễn viên") {
                        let aid = itemId.isEmpty ? itemTitle : itemId
                        guard !seenActorIds.contains(aid) else { continue }
                        seenActorIds.insert(aid)
                        let avatarUrl = (itemImgObj["portrait"] as? String)
                            ?? (itemImgObj["landscape"] as? String)
                            ?? (item["avatar"] as? String)
                            ?? (item["thumb"] as? String)
                            ?? ""
                        let roleStr = ((item["detail"] as? [String: Any])?["description"] as? String) ?? "Diễn viên"
                        actors.append(FPTActor(id: aid, name: itemTitle, avatar: avatarUrl, role: roleStr))
                    } else if !itemId.isEmpty && itemId != cleanVodId {
                        guard !seenRelatedIds.contains(itemId) else { continue }
                        seenRelatedIds.insert(itemId)
                        let relLand = (itemImgObj["landscape"] as? String)
                            ?? (itemImgObj["landscape_title"] as? String)
                            ?? (item["thumb"] as? String)
                            ?? (itemImgObj["portrait"] as? String)
                            ?? ""
                        let relPort = (itemImgObj["portrait"] as? String)
                            ?? (item["standing_thumb"] as? String)
                            ?? relLand
                        let relTitleLogo = (itemImgObj["title"] as? String) ?? ""
                        let relDetail = (item["detail"] as? [String: Any]) ?? [:]
                        let relDur = (relDetail["duration_s"] as? String) ?? ""
                        let relCountry = (relDetail["country"] as? String) ?? ""
                        let relShort = (relDetail["short_description"] as? String) ?? (relDetail["description"] as? String) ?? ""
                        let relAppId = String(describing: item["app_id"] ?? "")
                        let relIsSeries = (relAppId == "77") || relDur.lowercased().contains("tập")

                        relatedVods.append(FPTChannel(
                            id: "rel_\(itemId)",
                            channelId: itemId,
                            name: itemTitle,
                            badge: blkName.isEmpty ? "ĐỀ XUẤT" : blkName,
                            categoryId: relIsSeries ? "vod_series" : "vod_movies",
                            category: blkName.isEmpty ? "Nội dung tương tự" : blkName,
                            logo: relLand,
                            portraitLogo: relPort,
                            titleLogo: relTitleLogo,
                            desc: relShort,
                            is4K: true,
                            isDRM: false,
                            isLive: false,
                            statusText: relDur.isEmpty ? (relIsSeries ? "Phim bộ" : "Phim lẻ") : relDur,
                            resolution: relCountry.isEmpty ? "Full HD / 4K" : relCountry,
                            fps: "TM/Phụ Đề",
                            isVod: true,
                            isSeries: relIsSeries,
                            vodId: itemId,
                            episodeId: "0"
                        ))
                    }
                }
            }
        }

        if actors.isEmpty, let actArr = dataObj["actors_detail"] as? [[String: Any]] {
            for act in actArr {
                let name = ((act["full_name"] as? String) ?? (act["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                let aid = ((act["_id"] as? String) ?? name)
                let av = (act["avatar"] as? String) ?? ""
                actors.append(FPTActor(id: aid, name: name, avatar: av, role: "Diễn viên"))
            }
        }

        let isSeries = (epTypeStr != "0") || (episodes.count > 1) || (fallbackChannel?.isSeries == true)

        return FPTVodDetail(
            vodId: cleanVodId,
            title: title,
            shortDesc: shortDesc,
            desc: desc,
            poster: poster,
            portraitPoster: portraitPoster,
            titleLogo: titleLogo,
            country: country,
            yearText: yearText,
            ageRating: ageRating,
            metaData: metaArr,
            genres: genres,
            isSeries: isSeries,
            episodeTotal: epTotalStr,
            isDrm: isDrm,
            trailerUrl: trailerUrl,
            episodes: episodes,
            actors: actors,
            relatedVods: relatedVods
        )
    }

    // MARK: - Xin luồng phát Phim Bộ & Phim Lẻ (GET /api/v7.1_w/stream/vod/{vodId}/{episodeId}/{autoProfile})
    public func resolveVodStream(
        config: FPTBootstrapConfig,
        vodId: String,
        episodeId: String,
        title: String,
        prefer4K: Bool
    ) async throws -> FPTResolvedStream {
        let cleanVodId = vodId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanEpId = episodeId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "0"
            : episodeId.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Lấy metadata từ content/vod/{vodId} để xác định chính xác cờ DRM, source_provider (ví dụ galaxy-play, hbo, qnet) và auto_profile
        var isDrmContent = false
        var sourceProvider = ""
        var autoProfile = "adaptive_bitrate"
        var effectiveEpId = cleanEpId

        if let (detSt, detPayload) = try? await requestJSON(
            config: config,
            route: "content/vod/\(cleanVodId)",
            extraQuery: [("data_type", "")],
            authenticated: config.isAuthenticated
        ), detSt == 200, let dataObj = detPayload["data"] as? [String: Any] {
            let drmStr = String(describing: dataObj["drm"] ?? "0").lowercased()
            let vmxStr = String(describing: dataObj["verimatrix"] ?? "0").lowercased()
            isDrmContent = (drmStr == "1" || drmStr == "true" || vmxStr == "1" || vmxStr == "true")
            sourceProvider = (dataObj["source_provider"] as? String) ?? ""
            if let topAuto = dataObj["auto_profile"] as? String, !topAuto.isEmpty {
                autoProfile = topAuto
            }
            let epTypeStr = String(describing: dataObj["episode_type"] ?? "0")
            if let rawEps = dataObj["episodes"] as? [[String: Any]], !rawEps.isEmpty {
                if let matchedEp = rawEps.first(where: { String(describing: $0["id"] ?? "") == cleanEpId }) {
                    if let epAuto = matchedEp["auto_profile"] as? String, !epAuto.isEmpty {
                        autoProfile = epAuto
                    }
                } else if let firstEp = rawEps.first {
                    if let epAuto = firstEp["auto_profile"] as? String, !epAuto.isEmpty {
                        autoProfile = epAuto
                    }
                    if cleanEpId == "0" && epTypeStr != "0" {
                        let firstId = String(describing: firstEp["id"] ?? "0").trimmingCharacters(in: .whitespacesAndNewlines)
                        if !firstId.isEmpty {
                            effectiveEpId = firstId
                        }
                    }
                }
            }
        }

        let vodQuery: [(String, String)] = [
            ("data_type", ""),
            ("event_id", ""),
            ("stream_profile", "1"),
            ("is_pre_stream", "0")
        ]

        // 2. Ưu tiên gọi cổng Web/Safari FairPlay (/api/v7.1_w/stream/vod/...) để nhận luồng HLS FairPlay (.m3u8) gốc cho Apple TV
        //    (Cổng /api/v7.1_stad/ chỉ trả Widevine DASH .mpd cho các phim DRM của Galaxy Play / Điện ảnh)
        var (httpSt, streamPayload) = (try? await requestWebJSON(
            config: config,
            route: "stream/vod/\(cleanVodId)/\(effectiveEpId)/\(autoProfile)",
            extraQuery: vodQuery,
            authenticated: config.isAuthenticated
        )) ?? (500, [:])

        if httpSt != 200 && effectiveEpId != cleanEpId {
            let (retrySt, retryPayload) = (try? await requestWebJSON(
                config: config,
                route: "stream/vod/\(cleanVodId)/\(cleanEpId)/\(autoProfile)",
                extraQuery: vodQuery,
                authenticated: config.isAuthenticated
            )) ?? (500, [:])
            if retrySt == 200 || streamPayload.isEmpty {
                httpSt = retrySt
                streamPayload = retryPayload
            }
        }

        var sdata = (streamPayload["data"] as? [String: Any]) ?? streamPayload

        let isPlayableHls: (String) -> Bool = { url in
            let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && trimmed.contains(".m3u8") && !trimmed.contains(".mpd")
        }

        let hasWebM3u8 = [
            sdata["url_hls_drm_dolby_vision"],
            sdata["url_hls_drm_h265_hdr_10_plus"],
            sdata["url_hls_drm_h265_hdr_10"],
            sdata["url_hls_drm_h265_hlg"],
            sdata["url_hls_drm_h265"],
            sdata["url_hls_drm"],
            sdata["url_hls_dolby_vision"],
            sdata["url_hls_h265_hdr_10_plus"],
            sdata["url_hls_h265_hdr_10"],
            sdata["url_hls_h265_hlg"],
            sdata["url_hls_h265"],
            sdata["url_hls"],
            sdata["url_sub"],
            sdata["url_clean"],
            sdata["url"]
        ].compactMap { $0 as? String }.contains(where: { isPlayableHls($0) })

        // Dự phòng qua /api/v7.1_stad/ nếu cổng Web không trả về .m3u8
        if !hasWebM3u8 {
            let (stadSt, stadPayload) = (try? await requestJSON(
                config: config,
                route: "stream/vod/\(cleanVodId)/\(effectiveEpId)/\(autoProfile)",
                extraQuery: vodQuery,
                authenticated: config.isAuthenticated
            )) ?? (500, [:])
            let stadData = (stadPayload["data"] as? [String: Any]) ?? stadPayload
            if httpSt != 200 && stadSt == 200 {
                httpSt = stadSt
                streamPayload = stadPayload
            }
            for (k, v) in stadData {
                if sdata[k] == nil || String(describing: sdata[k] ?? "").isEmpty {
                    sdata[k] = v
                }
            }
        }

        let requireVipPlan = (sdata["require_vip_plan"] as? String)
            ?? (streamPayload["require_vip_plan"] as? String)
            ?? ""

        // 3. Tuyển chọn URL HLS (.m3u8) theo đúng thứ tự ưu tiên Safari FairPlay trên fptplay.vn (6195-e5581bdb4a15b3c8.js)
        let h265Candidates: [String]
        let h264Candidates: [String]

        if isDrmContent {
            h265Candidates = [
                (sdata["url_hls_drm_dolby_vision"] as? String) ?? "",
                (sdata["url_hls_drm_h265_hdr_10_plus"] as? String) ?? "",
                (sdata["url_hls_drm_h265_hdr_10"] as? String) ?? "",
                (sdata["url_hls_drm_h265_hlg"] as? String) ?? "",
                (sdata["url_hls_drm_h265"] as? String) ?? "",
                (sdata["url_hls_dolby_vision"] as? String) ?? "",
                (sdata["url_hls_h265_hdr_10_plus"] as? String) ?? "",
                (sdata["url_hls_h265_hdr_10"] as? String) ?? "",
                (sdata["url_hls_h265_hlg"] as? String) ?? "",
                (sdata["url_hls_h265"] as? String) ?? "",
                dashToHlsUrl((sdata["url_dash_drm_h265"] as? String) ?? "")
            ]
            h264Candidates = [
                (sdata["url_hls_drm"] as? String) ?? "",
                (sdata["url_hls"] as? String) ?? "",
                (sdata["url_sub"] as? String) ?? "",
                (sdata["url_clean"] as? String) ?? "",
                (sdata["url"] as? String) ?? "",
                dashToHlsUrl((sdata["url_dash_drm"] as? String) ?? ""),
                dashToHlsUrl((sdata["url_dash_no_drm"] as? String) ?? "")
            ]
        } else {
            h265Candidates = [
                (sdata["url_hls_dolby_vision"] as? String) ?? "",
                (sdata["url_hls_h265_hdr_10_plus"] as? String) ?? "",
                (sdata["url_hls_h265_hdr_10"] as? String) ?? "",
                (sdata["url_hls_h265_hlg"] as? String) ?? "",
                (sdata["url_hls_h265"] as? String) ?? "",
                (sdata["url_hls_drm_h265"] as? String) ?? "",
                dashToHlsUrl((sdata["url_dash_h265"] as? String) ?? ""),
                dashToHlsUrl((sdata["url_dash_drm_h265"] as? String) ?? "")
            ]
            h264Candidates = [
                (sdata["url_hls"] as? String) ?? "",
                (sdata["url_sub"] as? String) ?? "",
                (sdata["url_clean"] as? String) ?? "",
                (sdata["url"] as? String) ?? "",
                (sdata["url_hls_drm"] as? String) ?? "",
                dashToHlsUrl((sdata["url_dash_no_drm"] as? String) ?? ""),
                dashToHlsUrl((sdata["url_dash_drm"] as? String) ?? "")
            ]
        }

        // Tuyệt đối chỉ nhận luồng .m3u8 hợp lệ cho AVPlayer trên tvOS, không bao giờ chọn .mpd (MPEG-DASH)
        let hls4K = h265Candidates.first(where: { isPlayableHls($0) }) ?? ""
        let hlsH264 = h264Candidates.first(where: { isPlayableHls($0) }) ?? ""
        let isPreviewStream = hls4K.contains("-pre-") || hlsH264.contains("-pre-")

        // Nếu chưa đăng nhập và máy chủ trả 401 hoặc chỉ trả bản xem thử (-pre-), nhắc đăng nhập tài khoản chính chủ để xem trọn bộ
        if !config.isAuthenticated && (httpSt == 401 || isPreviewStream || !requireVipPlan.isEmpty) {
            throw NSError(
                domain: "FPTDirectClient",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Bộ phim '\(title)' yêu cầu đăng nhập tài khoản FPT Play chính chủ để xem trọn vẹn. Vui lòng bấm 'Đăng Nhập SĐT (OTP)' ở góc phải màn hình."]
            )
        }

        // Nếu đã đăng nhập nhưng gói cước chưa bao gồm phim VIP và không có luồng HLS
        if (httpSt == 401 || httpSt == 406) && hls4K.isEmpty && hlsH264.isEmpty {
            let msg = (streamPayload["msg"] as? String) ?? "Tài khoản FPT Play hiện tại chưa có gói xem bộ phim này (\(requireVipPlan))."
            throw NSError(domain: "FPTDirectClient", code: httpSt, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        let primaryHls: String
        let fallbackHls: String
        let is4K: Bool

        if prefer4K && !hls4K.isEmpty {
            primaryHls = hls4K
            fallbackHls = hlsH264
            is4K = true
        } else if !hlsH264.isEmpty {
            primaryHls = hlsH264
            fallbackHls = hls4K
            is4K = false
        } else if !hls4K.isEmpty {
            primaryHls = hls4K
            fallbackHls = ""
            is4K = true
        } else {
            let msg = (streamPayload["msg"] as? String) ?? "Không lấy được luồng phát HLS cho bộ phim này."
            throw NSError(domain: "FPTDirectClient", code: -3, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        let sessionToken = (sdata["session"] as? String) ?? ""
        let merchant = (sdata["merchant"] as? String) ?? ""
        let streamSession = (sdata["stream_session"] as? String) ?? ""

        // Chỉ kích hoạt FairPlay DRM khi nội dung có cờ DRM (hoặc URL là luồng DRM) và có session + merchant
        let shouldEnableDrm = (isDrmContent || primaryHls.lowercased().contains("drm"))
            && !sessionToken.isEmpty
            && !merchant.isEmpty

        let drmConfig = await buildFairPlayDRMConfig(
            enabled: shouldEnableDrm,
            config: config,
            sessionToken: sessionToken,
            merchant: merchant,
            sourceProvider: sourceProvider
        )

        return FPTResolvedStream(
            ok: true,
            channelId: cleanVodId,
            eventId: effectiveEpId,
            title: title,
            hlsUrl: primaryHls,
            fallbackHlsUrl: fallbackHls.isEmpty ? nil : fallbackHls,
            hls4KUrl: hls4K.isEmpty ? nil : hls4K,
            hlsH264Url: hlsH264.isEmpty ? nil : hlsH264,
            is4K: is4K,
            mediaHeaders: streamSession.isEmpty ? [:] : ["x-id": streamSession],
            drm: drmConfig
        )
    }

    // MARK: - Xin luồng phát HLS + FairPlay trực tiếp trên Apple TV (Hỗ trợ màn hình tĩnh chờ phát sóng khi trận đấu chưa mở luồng)
    public func resolveStream(
        config: FPTBootstrapConfig,
        channel: FPTChannel,
        prefer4K: Bool
    ) async throws -> FPTResolvedStream {
        if channel.isVod {
            let vid = channel.vodId.isEmpty ? channel.channelId : channel.vodId
            let epId = channel.episodeId.isEmpty ? "0" : channel.episodeId
            return try await resolveVodStream(
                config: config,
                vodId: vid,
                episodeId: epId,
                title: channel.name,
                prefer4K: prefer4K
            )
        }

        var channelId = channel.channelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let eventId = channel.eventId.trimmingCharacters(in: .whitespacesAndNewlines)
        var title = channel.name
        var autoProfile = "adaptive_bitrate"
        var posterUrl = channel.logo
        var scheduleLabel = channel.statusText
        var eventDesc = channel.desc
        var beginInt: Int? = nil
        var isDrmContent = channel.isDRM
        var sourceProvider = ""

        if !eventId.isEmpty {
            if let (evCode, evPayload) = try? await requestJSON(config: config, route: "event/detail/\(eventId)", authenticated: config.isAuthenticated),
               evCode == 200,
               let evData = evPayload["data"] as? [String: Any] {
                if let realCid = ((evData["id"] as? String) ?? (evData["asset_id"] as? String))?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !realCid.isEmpty {
                    channelId = realCid
                }
                if let evTitle = (evData["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !evTitle.isEmpty {
                    title = evTitle
                }
                if let evAuto = (evData["auto_profile"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !evAuto.isEmpty {
                    autoProfile = evAuto
                }
                let vmxStr = String(describing: evData["verimatrix"] ?? "").lowercased()
                let drmStr = String(describing: evData["drm"] ?? "").lowercased()
                if !vmxStr.isEmpty || !drmStr.isEmpty {
                    isDrmContent = (vmxStr == "1" || vmxStr == "true" || drmStr == "1" || drmStr == "true")
                }
                sourceProvider = (evData["source_provider"] as? String) ?? sourceProvider
                if let evImgObj = evData["image"] as? [String: Any] {
                    posterUrl = (evImgObj["landscape_title"] as? String)
                        ?? (evImgObj["landscape"] as? String)
                        ?? (evImgObj["portrait"] as? String)
                        ?? posterUrl
                }
                if let bVal = Int(String(describing: evData["begin_time"] ?? "")) {
                    beginInt = bVal
                    scheduleLabel = formatMatchTime(beginTs: bVal, fallbackLabel: scheduleLabel)
                }
                if let dStr = evData["description"] as? String, !dStr.isEmpty {
                    eventDesc = dStr
                }
            }
        } else if config.isAuthenticated {
            if let (detCode, detPayload) = try? await requestJSON(config: config, route: "tv/detail/\(channelId)", extraQuery: [("data_type", "")]),
               detCode == 200,
               let chObj = (detPayload["Channel"] as? [String: Any]) ?? (detPayload["data"] as? [String: Any]) {
                title = (chObj["name"] as? String) ?? title
                if let chAuto = (chObj["auto_profile"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !chAuto.isEmpty {
                    autoProfile = chAuto
                }
                let vmxStr = String(describing: chObj["verimatrix"] ?? "").lowercased()
                let drmStr = String(describing: chObj["drm"] ?? "").lowercased()
                if !vmxStr.isEmpty || !drmStr.isEmpty {
                    isDrmContent = (vmxStr == "1" || vmxStr == "true" || drmStr == "1" || drmStr == "true")
                }
                sourceProvider = (chObj["source_provider"] as? String) ?? sourceProvider
            }
        }

        let now = Date().timeIntervalSince1970
        let isUpcomingEvent = !eventId.isEmpty && ((beginInt != nil && now < Double(beginInt! - 600)) || !channel.isLive)

        // Nếu trận đấu chưa tới giờ mở luồng (SẮP DIỄN RA), hiển thị ngay Màn Hình Tĩnh Chờ Phát Sóng (Poster sự kiện + Giờ thi đấu) giống hệt trên điện thoại!
        if isUpcomingEvent && !config.isAuthenticated {
            return FPTResolvedStream(
                ok: true,
                channelId: channelId,
                eventId: eventId,
                title: title,
                hlsUrl: "",
                fallbackHlsUrl: nil,
                hls4KUrl: nil,
                hlsH264Url: nil,
                is4K: channel.is4K,
                mediaHeaders: nil,
                drm: nil,
                message: "Trận đấu dự kiến bắt đầu lúc \(scheduleLabel). Luồng trực tiếp sẽ tự động mở khi trận đấu bắt đầu.\n\(eventDesc)",
                isWaitingSlate: true,
                posterUrl: posterUrl,
                scheduleText: scheduleLabel
            )
        }

        guard config.isAuthenticated else {
            throw NSError(
                domain: "FPTDirectClient",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Bạn chưa đăng nhập tài khoản FPT Play trên Apple TV. Vui lòng bấm 'Đăng Nhập SĐT (OTP)' ở góc phải màn hình để đăng nhập."]
            )
        }

        let streamQuery: [(String, String)] = [
            ("fhd", "1"),
            ("data_type", ""),
            ("enable_preview", "0"),
            ("event_id", eventId),
            ("stream_profile", "1")
        ]

        // 1. Ưu tiên gọi cổng Web/Safari FairPlay (/api/v7.1_w/stream/tv/...) để lấy luồng HLS FairPlay (.m3u8) gốc kèm chữ ký CDN hợp lệ cho các sự kiện trực tiếp (NBA, Võ thuật, Thể thao, Kênh TV)
        var (httpSt, streamPayload) = (try? await requestWebJSON(
            config: config,
            route: "stream/tv/\(channelId)/\(autoProfile)",
            extraQuery: streamQuery,
            authenticated: config.isAuthenticated
        )) ?? (500, [:])

        var statusVal = String(describing: streamPayload["status"] ?? "0")
        var sdata = (streamPayload["data"] as? [String: Any]) ?? [:]

        // 2. Đồng thời gọi cổng SmartTV (/api/v7.1_stad/stream/tv/...) để bổ sung luồng 4K HEVC (url_dash_drm_h265) hoặc dự phòng khi cần
        let (stadSt, stadPayload) = (try? await requestJSON(
            config: config,
            route: "stream/tv/\(channelId)/\(autoProfile)",
            extraQuery: streamQuery
        )) ?? (500, [:])

        let stadStatusVal = String(describing: stadPayload["status"] ?? "0")
        let stadData = (stadPayload["data"] as? [String: Any]) ?? [:]

        if statusVal != "1" && stadStatusVal == "1" {
            httpSt = stadSt
            statusVal = stadStatusVal
            streamPayload = stadPayload
            sdata = stadData
        } else {
            if httpSt != 200 && stadSt == 200 {
                httpSt = stadSt
            }
            for (k, v) in stadData {
                if sdata[k] == nil || String(describing: sdata[k] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    sdata[k] = v
                }
            }
        }

        let isPlayableHls: (String) -> Bool = { url in
            let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && trimmed.contains(".m3u8") && !trimmed.contains(".mpd")
        }

        // 3. Tuyển chọn URL HLS (.m3u8) theo đúng chuẩn Safari FairPlay trên fptplay.vn (6195-e5581bdb4a15b3c8.js)
        let h265Candidates: [String]
        let h264Candidates: [String]

        if isDrmContent {
            h265Candidates = [
                (sdata["url_hls_drm_dolby_vision"] as? String) ?? "",
                (sdata["url_hls_drm_h265_hdr_10_plus"] as? String) ?? "",
                (sdata["url_hls_drm_h265_hdr_10"] as? String) ?? "",
                (sdata["url_hls_drm_h265_hlg"] as? String) ?? "",
                (sdata["url_hls_drm_h265"] as? String) ?? "",
                dashToHlsUrl((sdata["url_dash_drm_h265"] as? String) ?? ""),
                (sdata["url_hls_dolby_vision"] as? String) ?? "",
                (sdata["url_hls_h265_hdr_10_plus"] as? String) ?? "",
                (sdata["url_hls_h265_hdr_10"] as? String) ?? "",
                (sdata["url_hls_h265_hlg"] as? String) ?? "",
                (sdata["url_hls_h265"] as? String) ?? "",
                dashToHlsUrl((sdata["url_dash_h265"] as? String) ?? "")
            ]
            h264Candidates = [
                (sdata["url_hls_drm"] as? String) ?? "",
                (sdata["url_hls"] as? String) ?? "",
                (sdata["url_sub"] as? String) ?? "",
                (sdata["url_clean"] as? String) ?? "",
                (sdata["url"] as? String) ?? "",
                dashToHlsUrl((sdata["url_sub"] as? String) ?? ""),
                dashToHlsUrl((sdata["url"] as? String) ?? ""),
                dashToHlsUrl((sdata["url_dash_drm"] as? String) ?? ""),
                dashToHlsUrl((sdata["url_dash_no_drm"] as? String) ?? "")
            ]
        } else {
            h265Candidates = [
                (sdata["url_hls_dolby_vision"] as? String) ?? "",
                (sdata["url_hls_h265_hdr_10_plus"] as? String) ?? "",
                (sdata["url_hls_h265_hdr_10"] as? String) ?? "",
                (sdata["url_hls_h265_hlg"] as? String) ?? "",
                (sdata["url_hls_h265"] as? String) ?? "",
                (sdata["url_hls_drm_h265"] as? String) ?? "",
                dashToHlsUrl((sdata["url_dash_h265"] as? String) ?? ""),
                dashToHlsUrl((sdata["url_dash_drm_h265"] as? String) ?? "")
            ]
            h264Candidates = [
                (sdata["url_hls"] as? String) ?? "",
                (sdata["url_sub"] as? String) ?? "",
                (sdata["url_clean"] as? String) ?? "",
                (sdata["url"] as? String) ?? "",
                (sdata["url_hls_drm"] as? String) ?? "",
                dashToHlsUrl((sdata["url_dash_no_drm"] as? String) ?? ""),
                dashToHlsUrl((sdata["url_sub"] as? String) ?? ""),
                dashToHlsUrl((sdata["url"] as? String) ?? ""),
                dashToHlsUrl((sdata["url_dash_drm"] as? String) ?? "")
            ]
        }

        let clearCandidates: [String] = [
            (sdata["url_hls"] as? String) ?? "",
            (sdata["url_clean"] as? String) ?? "",
            dashToHlsUrl((sdata["url_dash_no_drm"] as? String) ?? "")
        ]

        // Chỉ chấp nhận URL .m3u8 hợp lệ cho AVPlayer trên tvOS, không bao giờ đưa .mpd vào AVPlayer
        let hls4K = h265Candidates.first(where: { isPlayableHls($0) }) ?? ""
        let hlsH264 = h264Candidates.first(where: { isPlayableHls($0) }) ?? ""
        let hlsClear = clearCandidates.first(where: { isPlayableHls($0) }) ?? ""

        let hasAnyStreamUrl = !hls4K.isEmpty || !hlsH264.isEmpty || !hlsClear.isEmpty

        // Nếu sự kiện thể thao/bóng đá chưa tới giờ mở luồng (hoặc nhà đài chưa bật encoder cho sự kiện này),
        // hiển thị Màn Hình Tĩnh Chờ Phát Sóng (Poster sự kiện + Giờ thi đấu) giống hệt trên app điện thoại FPT Play!
        if !eventId.isEmpty && (!hasAnyStreamUrl || statusVal != "1") {
            if isUpcomingEvent || httpSt != 401 {
                let serverMsg = (streamPayload["msg"] as? String) ?? (stadPayload["msg"] as? String) ?? ""
                let waitMsg = !serverMsg.isEmpty
                    ? "\(serverMsg) • Lịch phát sóng: \(scheduleLabel)"
                    : "Trận đấu chưa mở luồng trực tiếp (Lịch phát sóng: \(scheduleLabel)). Màn hình sẽ tự động phát ngay khi trận đấu bắt đầu."
                return FPTResolvedStream(
                    ok: true,
                    channelId: channelId,
                    eventId: eventId,
                    title: title,
                    hlsUrl: "",
                    fallbackHlsUrl: nil,
                    hls4KUrl: nil,
                    hlsH264Url: nil,
                    is4K: channel.is4K,
                    mediaHeaders: nil,
                    drm: nil,
                    message: "\(waitMsg)\n\(eventDesc)",
                    isWaitingSlate: true,
                    posterUrl: posterUrl,
                    scheduleText: scheduleLabel
                )
            }
        }

        if httpSt == 401 {
            throw NSError(
                domain: "FPTDirectClient",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Phiên đăng nhập đã hết hạn hoặc tài khoản chưa đăng ký gói cước cho nội dung này. Vui lòng kiểm tra mục 'Tài Khoản'."]
            )
        }

        guard statusVal == "1", hasAnyStreamUrl else {
            let msg = (streamPayload["msg"] as? String) ?? (stadPayload["msg"] as? String) ?? "Không xin được phiên phát từ FPT Play"
            throw NSError(domain: "FPTDirectClient", code: -2, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        let primaryHls: String
        let fallbackHls: String
        let is4K: Bool

        if prefer4K && !hls4K.isEmpty {
            primaryHls = hls4K
            fallbackHls = !hlsH264.isEmpty ? hlsH264 : hlsClear
            is4K = true
        } else if !hlsH264.isEmpty {
            primaryHls = hlsH264
            fallbackHls = !hlsClear.isEmpty && hlsClear != hlsH264 ? hlsClear : (!hls4K.isEmpty ? hls4K : "")
            is4K = false
        } else if !hlsClear.isEmpty {
            primaryHls = hlsClear
            fallbackHls = ""
            is4K = false
        } else {
            throw NSError(domain: "FPTDirectClient", code: -3, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy URL HLS phù hợp cho kênh này"])
        }

        let sessionToken = (sdata["session"] as? String) ?? ""
        let merchant = (sdata["merchant"] as? String) ?? ""
        let streamSession = (sdata["stream_session"] as? String) ?? ""

        let shouldEnableDrm = (isDrmContent || primaryHls.lowercased().contains("drm"))
            && !sessionToken.isEmpty
            && !merchant.isEmpty

        let drmConfig = await buildFairPlayDRMConfig(
            enabled: shouldEnableDrm,
            config: config,
            sessionToken: sessionToken,
            merchant: merchant,
            sourceProvider: sourceProvider
        )

        return FPTResolvedStream(
            ok: true,
            channelId: channelId,
            eventId: eventId,
            title: title,
            hlsUrl: primaryHls,
            fallbackHlsUrl: fallbackHls.isEmpty ? nil : fallbackHls,
            hls4KUrl: hls4K.isEmpty ? nil : hls4K,
            hlsH264Url: hlsH264.isEmpty ? nil : hlsH264,
            is4K: is4K,
            mediaHeaders: streamSession.isEmpty ? [:] : ["x-id": streamSession],
            drm: drmConfig
        )
    }
}
