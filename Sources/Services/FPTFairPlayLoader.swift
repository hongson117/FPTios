//
//  FPTFairPlayLoader.swift
//  FPT (Apple TV / tvOS)
//
//  Giải mã phần cứng Apple FairPlay Streaming (AVContentKeySession) trực tiếp trên Apple TV
//  Hỗ trợ đồng thời:
//  - SigmaDRM (Ngoại Hạng Anh 4K/FHD 50fps, Thể Thao)
//  - CastLabs DRMtoday / Qnet (BBC News, CNN, HBO HD, Cinemax, Warner TV, AXN, Discovery, Cartoon Network...)
//

import Foundation
import AVFoundation

public final class FPTFairPlayLoader: NSObject, AVContentKeySessionDelegate {
    private let drm: FPTDRMConfig
    private let keyQueue = DispatchQueue(label: "vn.fptplay.appletv.fairplay")
    private var keySession: AVContentKeySession?
    private var cachedCertificate: Data?
    private let onLog: ((String) -> Void)?

    public init(drm: FPTDRMConfig, onLog: ((String) -> Void)? = nil) {
        self.drm = drm
        self.onLog = onLog
        super.init()
    }

    public func attach(to asset: AVURLAsset) {
        guard drm.enabled else { return }
        let session = AVContentKeySession(keySystem: .fairPlayStreaming)
        session.setDelegate(self, queue: keyQueue)
        session.addContentKeyRecipient(asset)
        self.keySession = session
        log("🔐 Khởi tạo phiên giải mã phần cứng FairPlay (\(drm.provider ?? "sigma"))")
    }

    public func invalidate() {
        keySession = nil
    }

    private func log(_ text: String) {
        onLog?(text)
    }

    public func contentKeySession(
        _ session: AVContentKeySession,
        didProvide keyRequest: AVContentKeyRequest
    ) {
        handleKeyRequest(keyRequest)
    }

    public func contentKeySession(
        _ session: AVContentKeySession,
        didProvideRenewingContentKeyRequest keyRequest: AVContentKeyRequest
    ) {
        handleKeyRequest(keyRequest)
    }

    public func contentKeySession(
        _ session: AVContentKeySession,
        contentKeyRequest keyRequest: AVContentKeyRequest,
        didFailWithError err: Error
    ) {
        log("❌ Lỗi FairPlay KeyRequest: \(err.localizedDescription)")
    }

    private func handleKeyRequest(_ keyRequest: AVContentKeyRequest) {
        guard let skdString = keyRequest.identifier as? String ?? (keyRequest.identifier as? URL)?.absoluteString else {
            let err = NSError(domain: "FPTFairPlay", code: -10, userInfo: [NSLocalizedDescriptionKey: "Thiếu định danh skd:// trong luồng HLS"])
            keyRequest.processContentKeyResponseError(err)
            return
        }

        let assetId = extractAssetId(from: skdString)
        let provider = drm.provider ?? (skdString.lowercased().contains("drmtoday") ? "drmtoday" : "sigma")
        log("🔑 Bắt gặp khóa FairPlay (\(provider)): assetId=\(assetId)")

        Task {
            do {
                let certData = try await loadCertificate(provider: provider)

                // Chuẩn Shaka Player FairPlayUtils trên fptplay.vn (6195-e5581bdb4a15b3c8.js):
                // - DRMtoday: defaultGetContentId("skd://drmtoday?assetId=...") lấy hostname -> "drmtoday"
                // - SigmaDRM: lấy assetId
                var candidateContentIds: [String] = []
                if provider == "drmtoday" {
                    let hostId = URL(string: skdString)?.host ?? "drmtoday"
                    candidateContentIds.append(hostId.isEmpty ? "drmtoday" : hostId)
                    if !assetId.isEmpty && !candidateContentIds.contains(assetId) {
                        candidateContentIds.append(assetId)
                    }
                    let stripped = skdString.replacingOccurrences(of: "skd://", with: "")
                    if !candidateContentIds.contains(stripped) {
                        candidateContentIds.append(stripped)
                    }
                } else {
                    let primary = assetId.isEmpty ? skdString.replacingOccurrences(of: "skd://", with: "") : assetId
                    candidateContentIds.append(primary)
                }

                var lastError: Error?
                for cidString in candidateContentIds {
                    guard let cidData = cidString.data(using: .utf8) else { continue }
                    do {
                        let spcData = try await makeSPCData(keyRequest: keyRequest, certData: certData, contentIdData: cidData)
                        let ckcData = try await requestCKC(spcData: spcData, skdUri: skdString, assetId: assetId, provider: provider)
                        let keyResponse = AVContentKeyResponse(fairPlayStreamingKeyResponseData: ckcData)
                        keyRequest.processContentKeyResponse(keyResponse)
                        log("✅ Cấp khóa phần cứng FairPlay CKC (\(provider), cid=\(cidString)) thành công (\(ckcData.count) bytes)!")
                        return
                    } catch {
                        lastError = error
                        log("⚠️ Thử CKC với contentId='\(cidString)' chưa khớp: \(error.localizedDescription)")
                    }
                }

                if let err = lastError {
                    log("❌ Lỗi xin khóa CKC (\(provider)): \(err.localizedDescription)")
                    keyRequest.processContentKeyResponseError(err)
                }
            } catch {
                log("❌ Lỗi tải chứng chỉ FairPlay: \(error.localizedDescription)")
                keyRequest.processContentKeyResponseError(error)
            }
        }
    }

    private func makeSPCData(
        keyRequest: AVContentKeyRequest,
        certData: Data,
        contentIdData: Data
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            keyRequest.makeStreamingContentKeyRequestData(
                forApp: certData,
                contentIdentifier: contentIdData,
                options: nil
            ) { spcData, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let spcData = spcData {
                    continuation.resume(returning: spcData)
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "FPTFairPlay",
                        code: -12,
                        userInfo: [NSLocalizedDescriptionKey: "Dữ liệu SPC rỗng"]
                    ))
                }
            }
        }
    }

    private func extractAssetId(from skdUri: String) -> String {
        if let components = URLComponents(string: skdUri),
           let items = components.queryItems {
            for key in ["assetId", "contentId", "id"] {
                if let aid = items.first(where: { $0.name.caseInsensitiveCompare(key) == .orderedSame })?.value,
                   !aid.isEmpty {
                    return aid
                }
            }
        }
        if let url = URL(string: skdUri) {
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !path.isEmpty && !path.lowercased().contains("license/verify/fairplay") {
                return path
            }
            if let host = url.host, !host.isEmpty, host.lowercased() != "drmtoday", !host.lowercased().contains("sigmadrm") {
                return host
            }
        }
        return ""
    }

    private func loadCertificate(provider: String) async throws -> Data {
        if let cached = cachedCertificate {
            return cached
        }

        let defaultCertUrl = (provider == "drmtoday")
            ? "https://lic.drmtoday.com/license-server-fairplay/cert/\(drm.merchant ?? "qnet")"
            : "https://cert.sigmadrm.com/app/fairplay/fptplay/sigma"

        // Ưu tiên tải trực tiếp từ máy chủ chứng chỉ quốc tế để chạy độc lập không cần Laptop
        let urlsToTry = [drm.certUrl, defaultCertUrl, drm.proxyCertUrl]
            .compactMap { $0 }
            .filter { !$0.isEmpty }

        var lastError: Error?
        for urlStr in urlsToTry {
            guard let url = URL(string: urlStr) else { continue }
            var req = URLRequest(url: url)
            req.timeoutInterval = 8.0
            req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty {
                    cachedCertificate = data
                    log("📜 Đã nạp chứng chỉ FairPlay (\(data.count) bytes)")
                    return data
                }
            } catch {
                lastError = error
            }
        }

        throw lastError ?? NSError(domain: "FPTFairPlay", code: -20, userInfo: [NSLocalizedDescriptionKey: "Không tải được chứng chỉ FairPlay"])
    }

    private func requestCKC(
        spcData: Data,
        skdUri: String,
        assetId: String,
        provider: String
    ) async throws -> Data {
        let spcBase64 = spcData.base64EncodedString()
        let ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

        // 1. Gọi trực tiếp máy chủ cấp phép FairPlay từ Apple TV (Hoạt động độc lập 100% không cần Laptop)
        do {
            if provider == "drmtoday" {
                // Chuẩn _app-905975c024a4ba11.js & 6195-e5581bdb4a15b3c8.js:
                // URL chính xác là https://lic.drmtoday.com/license-server-fairplay (không có /ckc)
                var licUrlStr = drm.licenseUrl ?? "https://lic.drmtoday.com/license-server-fairplay"
                if licUrlStr.hasSuffix("/ckc") {
                    licUrlStr = String(licUrlStr.dropLast(4))
                }
                guard let licUrl = URL(string: licUrlStr) else {
                    throw NSError(domain: "FPTFairPlay", code: -30, userInfo: [NSLocalizedDescriptionKey: "URL DRMtoday không hợp lệ"])
                }
                var req = URLRequest(url: licUrl)
                req.httpMethod = "POST"
                req.timeoutInterval = 10.0
                req.setValue(ua, forHTTPHeaderField: "User-Agent")
                req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                req.setValue("https://fptplay.vn", forHTTPHeaderField: "Origin")
                req.setValue("https://fptplay.vn/", forHTTPHeaderField: "Referer")
                if let hName = drm.headerName, let hVal = drm.headerValue, !hName.isEmpty {
                    req.setValue(hVal, forHTTPHeaderField: hName)
                }

                // Shaka Player Uint8ArrayUtils.toBase64 chuyển '+' -> '-' và '/' -> '_' (giữ nguyên dấu '=')
                let spcBase64Url = spcBase64
                    .replacingOccurrences(of: "+", with: "-")
                    .replacingOccurrences(of: "/", with: "_")
                let bodyStr = "spc=\(spcBase64Url)&assetId=\(assetId)"
                req.httpBody = bodyStr.data(using: .utf8)

                let (data, resp) = try await URLSession.shared.data(for: req)
                let httpCode = (resp as? HTTPURLResponse)?.statusCode ?? 500
                guard httpCode == 200 else {
                    let errBody = String(data: data, encoding: .utf8) ?? ""
                    throw NSError(domain: "FPTFairPlay", code: httpCode, userInfo: [NSLocalizedDescriptionKey: "DRMtoday HTTP \(httpCode): \(errBody.prefix(120))"])
                }

                return try decodeCKCResponse(data: data)
            } else {
                let licUrlStr = skdUri.hasPrefix("skd://")
                    ? skdUri.replacingOccurrences(of: "skd://", with: "https://")
                    : (drm.licenseUrl ?? "https://license.sigmadrm.com/license/verify/fairplay")
                guard let licUrl = URL(string: licUrlStr) else {
                    throw NSError(domain: "FPTFairPlay", code: -40, userInfo: [NSLocalizedDescriptionKey: "URL SigmaDRM không hợp lệ"])
                }
                var req = URLRequest(url: licUrl)
                req.httpMethod = "POST"
                req.timeoutInterval = 10.0
                req.setValue(ua, forHTTPHeaderField: "User-Agent")
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.setValue("https://fptplay.vn", forHTTPHeaderField: "Origin")
                req.setValue("https://fptplay.vn/", forHTTPHeaderField: "Referer")
                if let hName = drm.headerName, let hVal = drm.headerValue, !hName.isEmpty {
                    req.setValue(hVal, forHTTPHeaderField: hName)
                }
                let payload: [String: String] = ["spc": spcBase64, "assetId": assetId]
                req.httpBody = try JSONSerialization.data(withJSONObject: payload)

                let (data, resp) = try await URLSession.shared.data(for: req)
                let httpCode = (resp as? HTTPURLResponse)?.statusCode ?? 500
                guard httpCode == 200 else {
                    throw NSError(domain: "FPTFairPlay", code: httpCode, userInfo: [NSLocalizedDescriptionKey: "SigmaDRM HTTP \(httpCode)"])
                }
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let ckcB64 = json["license"] as? String,
                      let ckcData = Data(base64Encoded: ckcB64.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    throw NSError(domain: "FPTFairPlay", code: -42, userInfo: [NSLocalizedDescriptionKey: "Phản hồi SigmaDRM không chứa trường license hợp lệ"])
                }
                return ckcData
            }
        } catch {
            // 2. Dự phòng qua Gateway LAN nếu đang bật
            if let proxyStr = drm.proxyCkcUrl, let proxyUrl = URL(string: proxyStr) {
                var req = URLRequest(url: proxyUrl)
                req.httpMethod = "POST"
                req.timeoutInterval = 8.0
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let bodyObj: [String: String] = [
                    "provider": provider,
                    "spc": spcBase64,
                    "skd_uri": skdUri,
                    "asset_id": assetId,
                    "header_name": drm.headerName ?? "",
                    "header_value": drm.headerValue ?? ""
                ]
                req.httpBody = try? JSONSerialization.data(withJSONObject: bodyObj)
                if let (data, resp) = try? await URLSession.shared.data(for: req),
                   let http = resp as? HTTPURLResponse, http.statusCode == 200,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let ckcB64 = json["ckc"] as? String,
                   let ckcData = Data(base64Encoded: ckcB64.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    return ckcData
                }
            }
            throw error
        }
    }

    private func decodeCKCResponse(data: Data) throws -> Data {
        var rawText = (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if rawText.hasPrefix("<ckc>") && rawText.hasSuffix("</ckc>") {
            rawText = String(rawText.dropFirst(5).dropLast(6)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if rawText.hasPrefix("{") {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let ckcStr = (json["ckc"] as? String) ?? (json["license"] as? String) {
                rawText = ckcStr.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        let normalized = rawText
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let rem = normalized.count % 4
        let padded = rem > 0 ? normalized + String(repeating: "=", count: 4 - rem) : normalized
        if let decoded = Data(base64Encoded: padded, options: .ignoreUnknownCharacters), !decoded.isEmpty {
            return decoded
        }
        // Trường hợp máy chủ trả về raw binary CKC
        if data.count > 64 && !rawText.hasPrefix("{") && !rawText.hasPrefix("<") {
            return data
        }
        throw NSError(domain: "FPTFairPlay", code: -32, userInfo: [NSLocalizedDescriptionKey: "Không giải mã được dữ liệu CKC từ DRMtoday"])
    }
}
