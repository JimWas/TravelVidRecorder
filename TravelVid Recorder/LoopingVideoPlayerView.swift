import SwiftUI
import AVKit

struct LoopingVideoPlayerView: View {
    let videoURL: URL

    var body: some View {
        VideoPlayerRepresentable(videoURL: videoURL)
            .ignoresSafeArea(.all)
    }
}

struct VideoPlayerRepresentable: UIViewRepresentable {
    let videoURL: URL

    func makeUIView(context: Context) -> UIView {
        return VideoPlayerUIView(videoURL: videoURL)
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // No updates needed - video URL is immutable
    }
}

class VideoPlayerUIView: UIView {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var playerLooper: AVPlayerLooper?

    init(videoURL: URL) {
        super.init(frame: .zero)
        setupPlayer(with: videoURL)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    private func setupPlayer(with url: URL) {
        // Create player item
        let playerItem = AVPlayerItem(url: url)

        // Create queue player (required for AVPlayerLooper)
        let player = AVQueuePlayer(playerItem: playerItem)
        self.player = player

        // Mute audio (REQUIREMENT)
        player.isMuted = true

        // Setup seamless looping using AVPlayerLooper
        playerLooper = AVPlayerLooper(player: player, templateItem: playerItem)

        // Create player layer
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill  // Fill screen
        playerLayer.frame = bounds
        layer.addSublayer(playerLayer)
        self.playerLayer = playerLayer

        // Start playback
        player.play()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }

    deinit {
        player?.pause()
        playerLooper = nil
    }
}
