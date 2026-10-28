//
//  FPTPlayerView.swift
//  FTVOS (Apple TV / tvOS)
//
//  - Trình phát gốc AVPlayerViewController toàn màn hình trên Apple TV (không có badge đo thông số góc dưới phải)
//  - Màn Hình Chờ Sự Kiện Thể Thao (Match Waiting Slate) thiết kế chuẩn FPT Play Android TV (G2):
//    Poster 16:9 toàn màn hình + Gradient trái/dưới + Pill giờ thi đấu + Nút Capsule "Xem ngay" / "Quay lại"
//  - Hỗ trợ chuyển Tập Tiếp / Tập Trước cho Phim Bộ và chuyển Kênh Tiếp / Kênh Trước / Danh Sách Kênh cho Truyền Hình Trực Tiếp
//

import SwiftUI
import AVKit
import AVFoundation
import UIKit

public struct FPTPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentStream: FPTResolvedStream
    @State private var currentEpisode: FPTEpisode?
    @State private var isCheckingLive: Bool = false

    public let vodDetail: FPTVodDetail?
    public let initialResumeSeconds: Double
    public var onEpisodeChanged: ((FPTEpisode) -> Void)?

    private let fptOrange = FPTTheme.accent
    private let g2Bg = FPTTheme.bg
    private let autoCheckTimer = Timer.publish(every: 20, on: .main, in: .common).autoconnect()

    public init(
        resolved: FPTResolvedStream,
        vodDetail: FPTVodDetail? = nil,
        initialEpisode: FPTEpisode? = nil,
        resumeSeconds: Double = 0,
        onEpisodeChanged: ((FPTEpisode) -> Void)? = nil
    ) {
        _currentStream = State(initialValue: resolved)
        _currentEpisode = State(initialValue: initialEpisode)
        self.vodDetail = vodDetail
        self.initialResumeSeconds = resumeSeconds
        self.onEpisodeChanged = onEpisodeChanged
    }

    public var body: some View {
        Group {
            if currentStream.isWaitingSlate == true || currentStream.hlsUrl.isEmpty {
                waitingSlateView
            } else {
                FPTAVPlayerRepresentable(
                    resolved: currentStream,
                    vodDetail: vodDetail,
                    currentEpisode: currentEpisode,
                    resumeSeconds: initialResumeSeconds,
                    onEpisodeChanged: { newEp in
                        currentEpisode = newEp
                        onEpisodeChanged?(newEp)
                    },
                    onChannelSwitched: { newStream in
                        currentStream = newStream
                    }
                )
                .ignoresSafeArea()
            }
        }
        .onReceive(autoCheckTimer) { _ in
            if (currentStream.isWaitingSlate == true || currentStream.hlsUrl.isEmpty) && !isCheckingLive {
                Task {
                    await retryCheckLiveStream()
                }
            }
        }
    }

    // MARK: - Màn hình chờ sự kiện thể thao chuẩn FPT Play Android TV (G2 - screen-football-event.png)
    private var waitingSlateView: some View {
        ZStack(alignment: .leading) {
            g2Bg.ignoresSafeArea()

            // Ảnh nền 16:9 toàn màn hình
            if let poster = currentStream.posterUrl, let url = URL(string: poster), !poster.isEmpty {
                AsyncImage(url: url) { phase in
                    if let img = phase.image {
                        img
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                            .ignoresSafeArea()
                    } else {
                        g2Bg.ignoresSafeArea()
                    }
                }
            }

            // Lớp phủ Gradient trái sang phải (chuẩn vod_background_banner_v2 trên G2)
            LinearGradient(
                stops: [
                    .init(color: g2Bg.opacity(0.98), location: 0.0),
                    .init(color: g2Bg.opacity(0.88), location: 0.32),
                    .init(color: g2Bg.opacity(0.42), location: 0.62),
                    .init(color: Color.clear, location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .ignoresSafeArea()

            // Lớp phủ Gradient dưới lên trên
            LinearGradient(
                stops: [
                    .init(color: Color.clear, location: 0.0),
                    .init(color: g2Bg.opacity(0.35), location: 0.65),
                    .init(color: g2Bg.opacity(0.96), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Cột thông tin bên trái (x = 114pt chuẩn G2)
            VStack(alignment: .leading, spacing: 20) {
                // Pill lịch phát sóng phía trên (giống tv_event_time trên G2)
                HStack(spacing: 12) {
                    if let sched = currentStream.scheduleText, !sched.isEmpty {
                        Text(sched)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(.ultraThinMaterial)
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
                            )
                    }

                    HStack(spacing: 6) {
                        Text("LIVE")
                            .font(.system(size: 14, weight: .black))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(LinearGradient(colors: [Color.red, FPTTheme.accent2], startPoint: .leading, endPoint: .trailing)))
                            .shadow(color: Color.red.opacity(0.6), radius: 8, x: 0, y: 0)

                        Text("SỰ KIỆN TRỰC TIẾP")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(LinearGradient(colors: [FPTTheme.violet, FPTTheme.cyan.opacity(0.9)], startPoint: .leading, endPoint: .trailing)))
                    }
                }

                // Tiêu đề trận đấu / sự kiện lớn
                Text(currentStream.title)
                    .font(.system(size: 46, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .frame(maxWidth: 760, alignment: .leading)

                // Dòng metadata ngăn cách bằng dấu chấm •
                HStack(spacing: 10) {
                    Text("Thể thao trực tiếp")
                    Text("•")
                    Text("FPT Play")
                    if currentStream.is4K {
                        Text("•")
                        Text("4K UHD")
                            .foregroundColor(fptOrange)
                    }
                }
                .font(.system(size: 19, weight: .medium))
                .foregroundColor(Color.white.opacity(0.68))

                // Mô tả chi tiết
                if let msg = currentStream.message, !msg.isEmpty {
                    Text(msg)
                        .font(.system(size: 19, weight: .regular))
                        .foregroundColor(Color.white.opacity(0.88))
                        .lineSpacing(4)
                        .lineLimit(4)
                        .frame(maxWidth: 700, alignment: .leading)
                }

                // Cụm nút Capsule chuẩn G2 ("Xem ngay" & "Quay lại")
                HStack(spacing: 18) {
                    Button {
                        Task {
                            await retryCheckLiveStream()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            if isCheckingLive {
                                ProgressView()
                            } else {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 18, weight: .bold))
                            }
                            Text("Xem ngay")
                                .font(.system(size: 20, weight: .bold))
                        }
                        .padding(.horizontal, 30)
                        .padding(.vertical, 16)
                        .background(
                            Capsule()
                                .fill(FPTTheme.accentGradient)
                        )
                        .shadow(color: FPTTheme.accent2.opacity(0.5), radius: 16, x: 0, y: 6)
                        .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(isCheckingLive)

                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "bell.fill")
                                .font(.system(size: 18, weight: .bold))
                            Text("Quay lại lịch thi đấu")
                                .font(.system(size: 20, weight: .bold))
                        }
                        .padding(.horizontal, 30)
                        .padding(.vertical, 16)
                        .background(
                            Capsule()
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
                        .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 10)
            }
            .padding(.leading, 114)
            .padding(.trailing, 80)
        }
    }

    private func retryCheckLiveStream() async {
        isCheckingLive = true
        defer { isCheckingLive = false }

        let tempChannel = FPTChannel(
            id: "event_\(currentStream.eventId)",
            channelId: currentStream.channelId,
            eventId: currentStream.eventId,
            name: currentStream.title,
            badge: "LIVE",
            categoryId: "live_football",
            category: "Trực Tiếp",
            logo: currentStream.posterUrl ?? "",
            desc: currentStream.message ?? "",
            is4K: currentStream.is4K,
            isDRM: true,
            isLive: true,
            statusText: currentStream.scheduleText ?? "TRỰC TIẾP"
        )
        if let updated = try? await FPTService.shared.resolveStream(for: tempChannel),
           updated.isWaitingSlate != true,
           !updated.hlsUrl.isEmpty {
            currentStream = updated
        }
    }
}

struct FPTAVPlayerRepresentable: UIViewControllerRepresentable {
    let resolved: FPTResolvedStream
    let vodDetail: FPTVodDetail?
    let currentEpisode: FPTEpisode?
    let resumeSeconds: Double
    let onEpisodeChanged: ((FPTEpisode) -> Void)?
    let onChannelSwitched: ((FPTResolvedStream) -> Void)?

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = true

        context.coordinator.startPlayback(
            resolved: resolved,
            vodDetail: vodDetail,
            episode: currentEpisode,
            resumeSeconds: resumeSeconds,
            onEpisodeChanged: onEpisodeChanged,
            onChannelSwitched: onChannelSwitched,
            in: controller
        )
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject {
        private var player: AVPlayer?
        private var fairPlayLoader: FPTFairPlayLoader?
        private var statusObserver: NSKeyValueObservation?
        private var timeObserverToken: Any?
        private var endPlayObserver: NSObjectProtocol?
        private var didFallback: Bool = false
        private var didApplyInitialSeek: Bool = false

        private var activeResolved: FPTResolvedStream?
        private var activeVodDetail: FPTVodDetail?
        private var activeEpisode: FPTEpisode?
        private var onEpisodeChanged: ((FPTEpisode) -> Void)?
        private var onChannelSwitched: ((FPTResolvedStream) -> Void)?
        private weak var playerController: AVPlayerViewController?

        @MainActor
        func startPlayback(
            resolved: FPTResolvedStream,
            vodDetail: FPTVodDetail?,
            episode: FPTEpisode?,
            resumeSeconds: Double,
            onEpisodeChanged: ((FPTEpisode) -> Void)?,
            onChannelSwitched: ((FPTResolvedStream) -> Void)?,
            in controller: AVPlayerViewController
        ) {
            self.activeResolved = resolved
            self.activeVodDetail = vodDetail
            self.activeEpisode = episode
            self.onEpisodeChanged = onEpisodeChanged
            self.onChannelSwitched = onChannelSwitched
            self.playerController = controller
            self.didFallback = false
            self.didApplyInitialSeek = false

            configureTransportControls(on: controller)

            loadUrl(
                urlStr: resolved.hlsUrl,
                resolved: resolved,
                resumeSeconds: resumeSeconds,
                controller: controller
            )
        }

        @MainActor
        private func configureTransportControls(on controller: AVPlayerViewController) {
            if let detail = activeVodDetail, detail.episodes.count > 1 {
                configureEpisodeTransportControls(detail: detail, on: controller)
                return
            }

            // Nếu đang xem Kênh Truyền Hình (Live TV), tích hợp nút Chuyển Kênh & Danh Sách Kênh ngay trên thanh điều khiển (chuẩn G2 screen-return.png)
            let allTvChannels = FPTService.shared.categories
                .filter { $0.id == "vn_channels" || $0.id == "vn_tv" || $0.id == "intl_channels" }
                .flatMap { $0.channels }

            guard let curChannelId = activeResolved?.channelId,
                  let curIdx = allTvChannels.firstIndex(where: { $0.channelId == curChannelId }) else {
                if #available(tvOS 15.0, *) {
                    controller.transportBarCustomMenuItems = []
                    controller.infoViewActions = []
                }
                return
            }

            if #available(tvOS 15.0, *) {
                var transportItems: [UIMenuElement] = []
                var infoActions: [UIAction] = []

                let nextIdx = (curIdx + 1) % allTvChannels.count
                let nextCh = allTvChannels[nextIdx]
                let nextAction = UIAction(
                    title: "Kênh Tiếp: \(nextCh.name)",
                    image: UIImage(systemName: "chevron.up.circle.fill")
                ) { [weak self] _ in
                    self?.switchToLiveChannel(nextCh)
                }
                transportItems.append(nextAction)
                infoActions.append(nextAction)

                let prevIdx = (curIdx - 1 + allTvChannels.count) % allTvChannels.count
                let prevCh = allTvChannels[prevIdx]
                let prevAction = UIAction(
                    title: "Kênh Trước: \(prevCh.name)",
                    image: UIImage(systemName: "chevron.down.circle.fill")
                ) { [weak self] _ in
                    self?.switchToLiveChannel(prevCh)
                }
                transportItems.append(prevAction)
                infoActions.append(prevAction)

                let channelActions: [UIAction] = allTvChannels.enumerated().map { idx, ch in
                    let isCur = (ch.channelId == curChannelId)
                    let numLabel = "\(idx + 1). \(ch.name)"
                    return UIAction(
                        title: isCur ? "▶ \(numLabel) (Đang phát)" : numLabel,
                        image: UIImage(systemName: isCur ? "play.tv.fill" : "tv")
                    ) { [weak self] _ in
                        guard !isCur else { return }
                        self?.switchToLiveChannel(ch)
                    }
                }
                let chMenu = UIMenu(
                    title: "Danh sách kênh (\(allTvChannels.count))",
                    image: UIImage(systemName: "list.number"),
                    children: channelActions
                )
                transportItems.append(chMenu)

                controller.transportBarCustomMenuItems = transportItems
                controller.infoViewActions = infoActions
            }
        }

        private func configureEpisodeTransportControls(detail: FPTVodDetail, on controller: AVPlayerViewController) {
            let curId = activeEpisode?.id ?? activeResolved?.eventId ?? "0"
            let curIdx = detail.episodes.firstIndex(where: { $0.id == curId }) ?? 0

            if #available(tvOS 15.0, *) {
                var transportItems: [UIMenuElement] = []
                var infoActions: [UIAction] = []

                if curIdx + 1 < detail.episodes.count {
                    let nextEp = detail.episodes[curIdx + 1]
                    let nextAction = UIAction(
                        title: "Tập Tiếp: \(nextEp.title)",
                        image: UIImage(systemName: "forward.end.fill")
                    ) { [weak self] _ in
                        self?.switchToEpisode(nextEp)
                    }
                    transportItems.append(nextAction)
                    infoActions.append(nextAction)
                }

                if curIdx > 0 {
                    let prevEp = detail.episodes[curIdx - 1]
                    let prevAction = UIAction(
                        title: "Tập Trước: \(prevEp.title)",
                        image: UIImage(systemName: "backward.end.fill")
                    ) { [weak self] _ in
                        self?.switchToEpisode(prevEp)
                    }
                    transportItems.append(prevAction)
                    infoActions.append(prevAction)
                }

                let epActions: [UIAction] = detail.episodes.map { ep in
                    let isCurrent = (ep.id == curId)
                    return UIAction(
                        title: isCurrent ? "▶ \(ep.title) (Đang phát)" : ep.title,
                        image: UIImage(systemName: isCurrent ? "play.circle.fill" : "film")
                    ) { [weak self] _ in
                        guard !isCurrent else { return }
                        self?.switchToEpisode(ep)
                    }
                }
                let epMenu = UIMenu(
                    title: "Chọn Tập (\(curIdx + 1)/\(detail.episodes.count))",
                    image: UIImage(systemName: "list.and.film"),
                    children: epActions
                )
                transportItems.append(epMenu)

                controller.transportBarCustomMenuItems = transportItems
                controller.infoViewActions = infoActions
            }
        }

        private func switchToLiveChannel(_ targetChannel: FPTChannel) {
            guard let controller = playerController else { return }
            Task { @MainActor in
                do {
                    let newResolved = try await FPTService.shared.resolveStream(for: targetChannel)
                    guard !newResolved.hlsUrl.isEmpty else { return }
                    self.activeResolved = newResolved
                    self.didFallback = false
                    self.didApplyInitialSeek = false
                    self.onChannelSwitched?(newResolved)
                    self.configureTransportControls(on: controller)
                    self.loadUrl(
                        urlStr: newResolved.hlsUrl,
                        resolved: newResolved,
                        resumeSeconds: 0,
                        controller: controller
                    )
                } catch {
                    FPTService.shared.appendLog("❌ Không chuyển được sang kênh \(targetChannel.name): \(error.localizedDescription)")
                }
            }
        }

        private func switchToEpisode(_ targetEp: FPTEpisode) {
            guard let detail = activeVodDetail, let controller = playerController else { return }
            saveCurrentProgressNow()

            Task { @MainActor in
                do {
                    let newResolved = try await FPTService.shared.resolveVodEpisode(
                        vodDetail: detail,
                        episode: targetEp
                    )
                    self.activeEpisode = targetEp
                    self.activeResolved = newResolved
                    self.didFallback = false
                    self.didApplyInitialSeek = false
                    self.onEpisodeChanged?(targetEp)
                    self.configureTransportControls(on: controller)
                    self.loadUrl(
                        urlStr: newResolved.hlsUrl,
                        resolved: newResolved,
                        resumeSeconds: 0,
                        controller: controller
                    )
                } catch {
                    FPTService.shared.appendLog("❌ Không chuyển được sang \(targetEp.title): \(error.localizedDescription)")
                }
            }
        }

        private func saveCurrentProgressNow() {
            guard let avPlayer = self.player,
                  let resolved = self.activeResolved else { return }
            let sec = CMTimeGetSeconds(avPlayer.currentTime())
            let dur = CMTimeGetSeconds(avPlayer.currentItem?.duration ?? .zero)
            guard sec.isFinite && sec >= 3 else { return }
            let cleanDur = (dur.isFinite && dur > 0) ? dur : 0
            let epId = activeEpisode?.id ?? resolved.eventId
            let epTitle = activeEpisode?.title ?? ""
            let itemId = activeVodDetail?.vodId ?? resolved.channelId

            Task { @MainActor in
                FPTService.shared.updatePlaybackProgress(
                    vodOrChannelId: itemId,
                    episodeId: epId,
                    episodeTitle: epTitle,
                    positionSeconds: sec,
                    durationSeconds: cleanDur
                )
            }
        }

        private func loadUrl(
            urlStr: String,
            resolved: FPTResolvedStream,
            resumeSeconds: Double,
            controller: AVPlayerViewController
        ) {
            guard let url = URL(string: urlStr) else { return }

            var options: [String: Any] = [:]
            if let headers = resolved.mediaHeaders, !headers.isEmpty {
                options["AVURLAssetHTTPHeaderFieldsKey"] = headers
            }

            let asset = AVURLAsset(url: url, options: options.isEmpty ? nil : options)

            if let drm = resolved.drm, drm.enabled {
                let loader = FPTFairPlayLoader(drm: drm) { msg in
                    Task { @MainActor in
                        FPTService.shared.appendLog(msg)
                    }
                }
                loader.attach(to: asset)
                self.fairPlayLoader = loader
            } else {
                self.fairPlayLoader = nil
            }

            let item = AVPlayerItem(asset: asset)
            item.preferredForwardBufferDuration = 8.0

            let titleMeta = AVMutableMetadataItem()
            titleMeta.identifier = .commonIdentifierTitle
            titleMeta.value = resolved.title as (NSCopying & NSObjectProtocol)
            titleMeta.extendedLanguageTag = "und"
            item.externalMetadata = [titleMeta]

            if let oldEnd = endPlayObserver {
                NotificationCenter.default.removeObserver(oldEnd)
                endPlayObserver = nil
            }

            endPlayObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                guard let self = self,
                      let detail = self.activeVodDetail,
                      detail.episodes.count > 1 else { return }
                let curId = self.activeEpisode?.id ?? self.activeResolved?.eventId ?? "0"
                if let curIdx = detail.episodes.firstIndex(where: { $0.id == curId }),
                   curIdx + 1 < detail.episodes.count {
                    let nextEp = detail.episodes[curIdx + 1]
                    self.switchToEpisode(nextEp)
                }
            }

            let avPlayer: AVPlayer
            if let existing = self.player {
                existing.replaceCurrentItem(with: item)
                avPlayer = existing
            } else {
                avPlayer = AVPlayer(playerItem: item)
                avPlayer.automaticallyWaitsToMinimizeStalling = true
                self.player = avPlayer
                controller.player = avPlayer

                let interval = CMTime(seconds: 5.0, preferredTimescale: 600)
                timeObserverToken = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
                    self?.saveCurrentProgressNow()
                }
            }

            statusObserver = item.observe(\.status, options: [.new]) { [weak self] observedItem, _ in
                guard let self = self else { return }
                if observedItem.status == .readyToPlay {
                    if !self.didApplyInitialSeek && resumeSeconds >= 10 {
                        self.didApplyInitialSeek = true
                        let targetTime = CMTime(seconds: resumeSeconds, preferredTimescale: 600)
                        avPlayer.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
                    }
                } else if observedItem.status == .failed {
                    let errDesc = observedItem.error?.localizedDescription ?? "Unknown AVPlayerItem error"
                    Task { @MainActor in
                        FPTService.shared.appendLog("⚠️ Luồng chính gặp lỗi: \(errDesc)")
                    }
                    if !self.didFallback,
                       let fb = resolved.fallbackHlsUrl,
                       !fb.isEmpty,
                       fb != urlStr {
                        self.didFallback = true
                        Task { @MainActor in
                            FPTService.shared.appendLog("🔄 Tự động chuyển sang luồng FHD H.264 dự phòng...")
                            self.loadUrl(urlStr: fb, resolved: resolved, resumeSeconds: resumeSeconds, controller: controller)
                        }
                    }
                }
            }

            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)

            avPlayer.play()
        }

        deinit {
            saveCurrentProgressNow()
            if let token = timeObserverToken {
                player?.removeTimeObserver(token)
            }
            if let endObs = endPlayObserver {
                NotificationCenter.default.removeObserver(endObs)
            }
            statusObserver?.invalidate()
            player?.pause()
            fairPlayLoader?.invalidate()
        }
    }
}
