import AVFoundation
import UIKit

/// Every sound and haptic in NightFeed is synthesized in code at runtime — no bundled audio assets.
/// All other systems call through this single shared instance; the SFX/haptic vocabulary here is frozen.
enum SFXKind {
    case weaponFire(WeaponKind)
    case enemyHit
    case enemyDeath
    case miniBossDeath
    case gemPickup
    case levelUp
    case evolution
    case playerHit
    case miniBossSpawn
    case buttonTap
    case revive
}

enum HapticStyle { case light, medium, heavy, rigid, soft }
enum HapticType { case success, warning, error }

final class AudioManager {
    static let shared = AudioManager()

    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    private let musicMixer = AVAudioMixerNode()
    private var sfxPlayers: [AVAudioPlayerNode] = []
    private var nextSFXPlayerIndex = 0
    private let musicPlayer = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!

    private var sfxBufferCache: [String: AVAudioPCMBuffer] = [:]
    private var musicBuffer: AVAudioPCMBuffer?
    private var isMusicPlaying = false
    var sfxMuted = false
    var musicMuted = false

    private init() {
        engine.attach(mixer)
        engine.attach(musicMixer)
        engine.connect(mixer, to: engine.mainMixerNode, format: format)
        engine.connect(musicMixer, to: engine.mainMixerNode, format: format)
        mixer.outputVolume = 0.9
        musicMixer.outputVolume = 0.35

        for _ in 0..<10 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: mixer, format: format)
            sfxPlayers.append(player)
        }

        engine.attach(musicPlayer)
        engine.connect(musicPlayer, to: musicMixer, format: format)

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)
        try? engine.start()
    }

    // MARK: - SFX

    func playSFX(_ kind: SFXKind) {
        guard !sfxMuted else { return }
        let buffer = bufferForSFX(kind)
        let player = sfxPlayers[nextSFXPlayerIndex]
        nextSFXPlayerIndex = (nextSFXPlayerIndex + 1) % sfxPlayers.count
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: [.interrupts])
        player.play()
    }

    private func bufferForSFX(_ kind: SFXKind) -> AVAudioPCMBuffer {
        let key = cacheKey(for: kind)
        if let cached = sfxBufferCache[key] { return cached }
        let buffer = ToneSynth.render(recipe: recipe(for: kind), format: format)
        sfxBufferCache[key] = buffer
        return buffer
    }

    private func cacheKey(for kind: SFXKind) -> String {
        switch kind {
        case .weaponFire(let w): return "fire_\(w.rawValue)"
        case .enemyHit: return "enemyHit"
        case .enemyDeath: return "enemyDeath"
        case .miniBossDeath: return "miniBossDeath"
        case .gemPickup: return "gemPickup"
        case .levelUp: return "levelUp"
        case .evolution: return "evolution"
        case .playerHit: return "playerHit"
        case .miniBossSpawn: return "miniBossSpawn"
        case .buttonTap: return "buttonTap"
        case .revive: return "revive"
        }
    }

    private func recipe(for kind: SFXKind) -> ToneSynth.Recipe {
        switch kind {
        case .weaponFire(let weapon):
            switch weapon {
            case .fangBolt: return .init(waveform: .square, startFreq: 880, endFreq: 1200, duration: 0.07, gain: 0.18)
            case .emberOrbit: return .init(waveform: .sine, startFreq: 500, endFreq: 620, duration: 0.06, gain: 0.12)
            case .novaPulse: return .init(waveform: .sine, startFreq: 180, endFreq: 90, duration: 0.28, gain: 0.28)
            case .bloodLance: return .init(waveform: .square, startFreq: 300, endFreq: 220, duration: 0.14, gain: 0.22)
            case .batSwarm: return .init(waveform: .triangle, startFreq: 700, endFreq: 900, duration: 0.05, gain: 0.14)
            case .reaperWhirl: return .init(waveform: .noise, startFreq: 0, endFreq: 0, duration: 0.05, gain: 0.10)
            case .starShard: return .init(waveform: .triangle, startFreq: 1100, endFreq: 1400, duration: 0.05, gain: 0.15)
            case .voidRift: return .init(waveform: .sine, startFreq: 140, endFreq: 220, duration: 0.4, gain: 0.2)
            }
        case .enemyHit:
            return .init(waveform: .noise, startFreq: 0, endFreq: 0, duration: 0.04, gain: 0.14)
        case .enemyDeath:
            return .init(waveform: .square, startFreq: 320, endFreq: 60, duration: 0.18, gain: 0.22)
        case .miniBossDeath:
            return .init(waveform: .square, startFreq: 220, endFreq: 40, duration: 0.9, gain: 0.4)
        case .gemPickup:
            return .init(waveform: .sine, startFreq: 900, endFreq: 1500, duration: 0.09, gain: 0.16)
        case .levelUp:
            return .init(waveform: .sine, startFreq: 520, endFreq: 1040, duration: 0.5, gain: 0.32, arpeggio: true)
        case .evolution:
            return .init(waveform: .sine, startFreq: 260, endFreq: 1560, duration: 1.1, gain: 0.4, arpeggio: true)
        case .playerHit:
            return .init(waveform: .square, startFreq: 140, endFreq: 70, duration: 0.16, gain: 0.3)
        case .miniBossSpawn:
            return .init(waveform: .sine, startFreq: 90, endFreq: 60, duration: 1.2, gain: 0.35)
        case .buttonTap:
            return .init(waveform: .triangle, startFreq: 600, endFreq: 700, duration: 0.04, gain: 0.12)
        case .revive:
            return .init(waveform: .sine, startFreq: 300, endFreq: 900, duration: 0.7, gain: 0.35, arpeggio: true)
        }
    }

    // MARK: - Music

    func startMusic() {
        guard !isMusicPlaying, !musicMuted else { return }
        let buffer = musicBuffer ?? ToneSynth.renderMusicLoop(format: format)
        musicBuffer = buffer
        musicPlayer.scheduleBuffer(buffer, at: nil, options: [.loops])
        musicPlayer.play()
        isMusicPlaying = true
    }

    func stopMusic() {
        musicPlayer.stop()
        isMusicPlaying = false
    }

    func setMusicMuted(_ muted: Bool) {
        musicMuted = muted
        if muted { stopMusic() }
    }

    // MARK: - Haptics

    func hapticImpact(_ style: HapticStyle) {
        let mapped: UIImpactFeedbackGenerator.FeedbackStyle
        switch style {
        case .light: mapped = .light
        case .medium: mapped = .medium
        case .heavy: mapped = .heavy
        case .rigid: mapped = .rigid
        case .soft: mapped = .soft
        }
        UIImpactFeedbackGenerator(style: mapped).impactOccurred()
    }

    func hapticNotification(_ type: HapticType) {
        let mapped: UINotificationFeedbackGenerator.FeedbackType
        switch type {
        case .success: mapped = .success
        case .warning: mapped = .warning
        case .error: mapped = .error
        }
        UINotificationFeedbackGenerator().notificationOccurred(mapped)
    }
}

/// Minimal additive/FM-ish tone synthesizer producing short procedural SFX and a generative music loop.
enum ToneSynth {
    enum Waveform { case sine, square, triangle, noise }

    struct Recipe {
        let waveform: Waveform
        let startFreq: Double
        let endFreq: Double
        let duration: Double
        let gain: Float
        var arpeggio: Bool = false
    }

    static func render(recipe: Recipe, format: AVAudioFormat) -> AVAudioPCMBuffer {
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(recipe.duration * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(1, frameCount))!
        buffer.frameLength = buffer.frameCapacity
        guard let data = buffer.floatChannelData?[0] else { return buffer }
        let n = Int(buffer.frameLength)

        if recipe.arpeggio {
            let steps: [Double] = [1.0, 1.26, 1.5, 2.0]
            let stepFrames = n / steps.count
            var seed: UInt64 = 12345
            for i in 0..<n {
                let stepIndex = min(steps.count - 1, i / max(1, stepFrames))
                let freq = recipe.startFreq * steps[stepIndex]
                let t = Double(i) / sampleRate
                let localT = Double(i % max(1, stepFrames)) / Double(max(1, stepFrames))
                let env = Float(sin(.pi * min(1, localT)) ) * envelope(progress: Double(i) / Double(n))
                data[i] = sample(recipe.waveform, freq: freq, t: t, seed: &seed) * recipe.gain * env
            }
        } else {
            var seed: UInt64 = 9871
            for i in 0..<n {
                let progress = Double(i) / Double(max(1, n - 1))
                let freq = recipe.startFreq + (recipe.endFreq - recipe.startFreq) * progress
                let t = Double(i) / sampleRate
                let env = envelope(progress: progress)
                data[i] = sample(recipe.waveform, freq: freq, t: t, seed: &seed) * recipe.gain * env
            }
        }
        return buffer
    }

    /// A moody ~12s generative loop: a slow root-fifth pad plus a sparse plucked arpeggio, minor key.
    static func renderMusicLoop(format: AVAudioFormat) -> AVAudioPCMBuffer {
        let sampleRate = format.sampleRate
        let duration = 12.0
        let n = Int(duration * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n))!
        buffer.frameLength = buffer.frameCapacity
        guard let data = buffer.floatChannelData?[0] else { return buffer }

        let root = 110.0 // A2
        let scale: [Double] = [1.0, 1.2, 1.333, 1.5, 1.6, 1.8] // natural-minor-ish ratios over root
        var seed: UInt64 = 555111

        for i in 0..<n {
            let t = Double(i) / sampleRate
            var v: Float = 0
            // pad: root + fifth, slow amplitude swell
            let swell = 0.5 + 0.5 * sin(2 * .pi * t / 6.0)
            v += Float(sin(2 * .pi * root * t)) * 0.05 * Float(swell)
            v += Float(sin(2 * .pi * root * 1.5 * t)) * 0.035 * Float(swell)
            // sparse plucked arpeggio note every 0.75s
            let noteIndex = Int(t / 0.75) % scale.count
            let noteT = t.truncatingRemainder(dividingBy: 0.75)
            if noteT < 0.35 {
                let freq = root * 2 * scale[noteIndex]
                let env = Float(exp(-noteT * 9.0))
                v += Float(sin(2 * .pi * freq * t)) * 0.09 * env
            }
            // faint noise air/wind texture
            v += (randomFloat(&seed) * 2 - 1) * 0.006
            data[i] = v
        }
        return buffer
    }

    private static func envelope(progress: Double) -> Float {
        // quick attack, smooth release
        let attack = 0.06
        if progress < attack { return Float(progress / attack) }
        let release = (progress - attack) / (1 - attack)
        return Float(max(0, 1 - release))
    }

    private static func sample(_ waveform: Waveform, freq: Double, t: Double, seed: inout UInt64) -> Float {
        switch waveform {
        case .sine:
            return Float(sin(2 * .pi * freq * t))
        case .square:
            return sin(2 * .pi * freq * t) >= 0 ? 1 : -1
        case .triangle:
            let phase = (freq * t).truncatingRemainder(dividingBy: 1.0)
            return Float(4 * abs(phase - 0.5) - 1)
        case .noise:
            return randomFloat(&seed) * 2 - 1
        }
    }

    private static func randomFloat(_ seed: inout UInt64) -> Float {
        seed = seed &* 6364136223846793005 &+ 1
        return Float((seed >> 33) & 0xFFFFFF) / Float(0xFFFFFF)
    }
}
