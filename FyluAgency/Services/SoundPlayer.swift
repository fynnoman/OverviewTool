import Foundation
import AVFoundation

/// Plays short app feedback sounds from the main bundle.
/// Keeps a strong reference to the current player so it isn't deallocated
/// mid-playback when called from a transient view (e.g. inside a button
/// action followed by `dismiss()`).
enum SoundPlayer {
    private static var current: AVAudioPlayer?

    static func play(_ resource: String, withExtension ext: String = "wav") {
        guard let url = Bundle.main.url(forResource: resource, withExtension: ext) else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            player.play()
            current = player
        } catch {
            // Silently ignore — sound feedback is non-critical.
        }
    }

    static func kaching() {
        play("kaching")
    }
}
