import Foundation
import AVFoundation

/// Plays the beat itself so the producer can check the key by ear with the drone on top.
@MainActor
final class BeatPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var playingID: UUID?
    @Published var progress: Double = 0
    private var player: AVAudioPlayer?
    private var timer: Timer?

    func toggle(_ beat: Beat) {
        if playingID == beat.id { stop(); return }
        stop()
        do {
            try AudioSession.activate()
            let p = try AVAudioPlayer(contentsOf: beat.fileURL)
            p.delegate = self
            p.prepareToPlay()
            p.play()
            player = p
            playingID = beat.id
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let p = self.player, p.duration > 0 else { return }
                    self.progress = p.currentTime / p.duration
                }
            }
        } catch {
            playingID = nil
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        player?.stop(); player = nil
        playingID = nil
        progress = 0
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
}
