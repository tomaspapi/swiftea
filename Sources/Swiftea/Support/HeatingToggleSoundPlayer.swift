import AppKit

@MainActor
protocol HeatingToggleSoundPlaying: AnyObject {
    func playHeatingToggleSound(isEnabled: Bool)
}

@MainActor
final class NativeHeatingToggleSoundPlayer: HeatingToggleSoundPlaying {
    static let shared = NativeHeatingToggleSoundPlayer()

    private let onSound = NSSound(named: NSSound.Name("Morse"))
    private let offSound = NSSound(named: NSSound.Name("Frog"))

    private init() {
        onSound?.volume = 0.55
        offSound?.volume = 0.5
    }

    func playHeatingToggleSound(isEnabled: Bool) {
        guard let sound = isEnabled ? onSound : offSound else {
            NSSound.beep()
            return
        }

        sound.stop()
        sound.currentTime = 0
        sound.play()
    }
}

@MainActor
final class SilentHeatingToggleSoundPlayer: HeatingToggleSoundPlaying {
    static let shared = SilentHeatingToggleSoundPlayer()

    private init() {}

    func playHeatingToggleSound(isEnabled: Bool) {}
}
