import AVFoundation
import UIKit

enum HapticEvent {
    case tap
    case freeze
    case resume
    case mechanism
    case collision
    case success
    case failure
    case warning
}

final class HapticService {
    static let shared = HapticService()

    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let selection = UISelectionFeedbackGenerator()
    private let notification = UINotificationFeedbackGenerator()

    func prepare() {
        light.prepare()
        medium.prepare()
        selection.prepare()
        notification.prepare()
    }

    func play(_ event: HapticEvent) {
        guard SaveStore.shared.settings.hapticsEnabled else { return }
        switch event {
        case .tap:
            selection.selectionChanged()
            selection.prepare()
        case .freeze:
            rigid.impactOccurred(intensity: 0.85)
            rigid.prepare()
        case .resume:
            light.impactOccurred(intensity: 0.65)
            light.prepare()
        case .mechanism:
            medium.impactOccurred(intensity: 0.55)
            medium.prepare()
        case .collision:
            rigid.impactOccurred(intensity: 1)
            rigid.prepare()
        case .success:
            notification.notificationOccurred(.success)
            notification.prepare()
        case .failure:
            notification.notificationOccurred(.error)
            notification.prepare()
        case .warning:
            notification.notificationOccurred(.warning)
            notification.prepare()
        }
    }
}

enum SoundEffect: CaseIterable {
    case tap
    case freeze
    case resume
    case tileCollision
    case switchOn
    case gate
    case portal
    case rewind
    case success
    case failure

    var assetName: String {
        switch self {
        case .tap: return "sfx_tap"
        case .freeze: return "sfx_freeze"
        case .resume: return "sfx_resume"
        case .tileCollision: return "sfx_tile_collision"
        case .switchOn: return "sfx_switch_on"
        case .gate: return "sfx_gate"
        case .portal: return "sfx_portal"
        case .rewind: return "sfx_rewind"
        case .success: return "sfx_success"
        case .failure: return "sfx_failure"
        }
    }

    /// Synthesis recipe used only when the matching `.wav` is not in the bundle,
    /// so a partially delivered audio folder still leaves the game audible.
    var notes: [(frequency: Double, duration: Double, amplitude: Float)] {
        switch self {
        case .tap: return [(620, 0.035, 0.12)]
        case .freeze: return [(720, 0.05, 0.14), (520, 0.08, 0.12), (980, 0.14, 0.1)]
        case .resume: return [(480, 0.045, 0.1), (720, 0.08, 0.12)]
        case .tileCollision: return [(190, 0.035, 0.16), (145, 0.05, 0.1)]
        case .switchOn: return [(560, 0.04, 0.12), (820, 0.07, 0.12)]
        case .gate: return [(115, 0.12, 0.1)]
        case .portal: return [(390, 0.04, 0.08), (610, 0.04, 0.1), (910, 0.1, 0.08)]
        case .rewind: return [(520, 0.04, 0.08), (430, 0.04, 0.08), (340, 0.08, 0.08)]
        case .success: return [(523, 0.08, 0.12), (659, 0.08, 0.12), (784, 0.14, 0.14)]
        case .failure: return [(240, 0.1, 0.12), (185, 0.18, 0.12)]
        }
    }
}

/// A looping bed or a one-shot tag on the music channel.
enum MusicTrack {
    case menu
    case calm
    case driving
    case tense
    /// Layered over whichever bed is playing while world time is stopped.
    case freezeLayer
    case levelSuccess
    case levelFailure
    case chapterUnlock

    var assetName: String {
        switch self {
        case .menu: return "bgm_menu"
        case .calm: return "bgm_gameplay_calm"
        case .driving: return "bgm_gameplay_driving"
        case .tense: return "bgm_gameplay_tense"
        case .freezeLayer: return "bgm_freeze_layer"
        case .levelSuccess: return "bgm_level_success"
        case .levelFailure: return "bgm_level_failure"
        case .chapterUnlock: return "bgm_chapter_unlock"
        }
    }

    var loops: Bool {
        switch self {
        case .levelSuccess, .levelFailure, .chapterUnlock: return false
        default: return true
        }
    }

    /// The campaign bed steps up in intensity as chapters introduce heavier
    /// machinery, matching the calm / driving / tense three-way split.
    static func gameplay(forChapter chapter: Int) -> MusicTrack {
        switch chapter {
        case ..<4: return .calm
        case 4...7: return .driving
        default: return .tense
        }
    }
}

enum AmbientTrack {
    case tableRoom
    case machineHum

    var assetName: String {
        switch self {
        case .tableRoom: return "amb_table_room"
        case .machineHum: return "amb_machine_hum"
        }
    }

    static func forChapter(_ chapter: Int) -> AmbientTrack {
        chapter >= 8 ? .machineHum : .tableRoom
    }
}

/// Plays delivered `.wav` files where they exist and falls back to synthesised
/// tones where they do not, so audio can be delivered in batches without ever
/// leaving the game silent.
///
/// Files go through `AVAudioPlayer` rather than the engine's player node: the
/// delivered files are not guaranteed to share the engine's 44.1 kHz mono graph
/// format, and `AVAudioPlayerNode` throws rather than resampling. The engine
/// stays for the synthesis fallback only.
final class AudioService {
    static let shared = AudioService()

    private let engine = AVAudioEngine()
    private let synth = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var started = false

    private var effectVoices: [SoundEffect: EffectVoice] = [:]
    private var musicPlayer: AVAudioPlayer?
    private var currentMusic: MusicTrack?
    private var freezeLayerPlayer: AVAudioPlayer?
    private var stingerPlayer: AVAudioPlayer?
    private var ambientPlayer: AVAudioPlayer?
    private var currentAmbient: AmbientTrack?
    private var ambientTimer: Timer?

    private static let musicGain: Float = 0.5
    private static let duckedGain: Float = 0.32
    private static let freezeLayerGain: Float = 0.6
    private static let ambientGain: Float = 0.34
    private static let stingerGain: Float = 0.78

    private init() {
        engine.attach(synth)
        engine.connect(synth, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = Float(SaveStore.shared.settings.audioVolume)
    }

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            synth.play()
            started = true
        } catch {
            started = false
        }
    }

    func stop() {
        ambientTimer?.invalidate()
        ambientTimer = nil
        musicPlayer?.stop()
        musicPlayer = nil
        currentMusic = nil
        freezeLayerPlayer?.stop()
        freezeLayerPlayer = nil
        stingerPlayer?.stop()
        stingerPlayer = nil
        ambientPlayer?.stop()
        ambientPlayer = nil
        currentAmbient = nil
        synth.stop()
        engine.stop()
        started = false
    }

    func setVolume(_ value: CGFloat) {
        let clamped = ScalarMath.clamp(value, 0, 1)
        engine.mainMixerNode.outputVolume = Float(clamped)
        let master = Float(clamped) * Self.musicGain
        musicPlayer?.volume = freezeLayerPlayer == nil ? master : master * Self.duckedGain
        freezeLayerPlayer?.volume = Float(clamped) * Self.freezeLayerGain
        ambientPlayer?.volume = Float(clamped) * Self.ambientGain
        stingerPlayer?.volume = Float(clamped) * Self.stingerGain
    }

    // MARK: - Effects

    func play(_ effect: SoundEffect) {
        guard SaveStore.shared.settings.soundEnabled else { return }
        start()
        if let voice = effectVoice(for: effect) {
            voice.play(volume: Float(SaveStore.shared.settings.audioVolume))
            return
        }
        playSynth(effect.notes)
    }

    /// Level end swaps the looping bed for the matching stinger so the result
    /// panel is not sitting under gameplay music. Falls back to the short effect
    /// when the stinger file is missing.
    func finishLevel(success: Bool) {
        stopMusic(fade: 0.3)
        setFreezeLayer(false, fade: 0.2)
        if !playTag(success ? .levelSuccess : .levelFailure) {
            play(success ? .success : .failure)
        }
    }

    // MARK: - Music

    func playMusic(_ track: MusicTrack, fade: TimeInterval = 0.8) {
        guard SaveStore.shared.settings.ambientEnabled else {
            stopMusic(fade: fade)
            return
        }
        guard currentMusic != track else { return }
        currentMusic = track
        start()
        retireMusic(fade: fade)
        guard let url = Self.url(for: track.assetName),
              let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.numberOfLoops = track.loops ? -1 : 0
        player.volume = 0
        player.prepareToPlay()
        player.play()
        player.setVolume(Float(SaveStore.shared.settings.audioVolume) * Self.musicGain, fadeDuration: fade)
        musicPlayer = player
    }

    func stopMusic(fade: TimeInterval = 0.6) {
        currentMusic = nil
        retireMusic(fade: fade)
    }

    /// Freezing ducks the bed and layers the suspended-time drone on top, which
    /// gives the frozen state a sustained sound instead of a single sting.
    func setFreezeLayer(_ enabled: Bool, fade: TimeInterval = 0.5) {
        guard SaveStore.shared.settings.ambientEnabled else { return }
        let volume = Float(SaveStore.shared.settings.audioVolume)
        if enabled {
            start()
            if freezeLayerPlayer == nil,
               let url = Self.url(for: MusicTrack.freezeLayer.assetName),
               let player = try? AVAudioPlayer(contentsOf: url) {
                player.numberOfLoops = -1
                player.volume = 0
                player.prepareToPlay()
                player.play()
                freezeLayerPlayer = player
            }
            guard freezeLayerPlayer != nil else { return }
            freezeLayerPlayer?.setVolume(volume * Self.freezeLayerGain, fadeDuration: fade)
            musicPlayer?.setVolume(volume * Self.musicGain * Self.duckedGain, fadeDuration: fade)
        } else {
            freezeLayerPlayer?.setVolume(0, fadeDuration: fade)
            musicPlayer?.setVolume(volume * Self.musicGain, fadeDuration: fade)
        }
    }

    /// A one-shot music tag that leaves whatever bed is playing untouched.
    @discardableResult
    func playTag(_ track: MusicTrack) -> Bool {
        guard let url = Self.url(for: track.assetName),
              let player = try? AVAudioPlayer(contentsOf: url) else { return false }
        start()
        stingerPlayer?.stop()
        player.numberOfLoops = 0
        player.volume = Float(SaveStore.shared.settings.audioVolume) * Self.stingerGain
        player.prepareToPlay()
        player.play()
        stingerPlayer = player
        return true
    }

    private func retireMusic(fade: TimeInterval) {
        guard let outgoing = musicPlayer else { return }
        musicPlayer = nil
        outgoing.setVolume(0, fadeDuration: fade)
        DispatchQueue.main.asyncAfter(deadline: .now() + fade + 0.1) { outgoing.stop() }
    }

    // MARK: - Ambient

    /// Keeps the last requested bed so toggling the setting back on resumes the
    /// right room rather than silence.
    func playAmbient(_ track: AmbientTrack, fade: TimeInterval = 1.4) {
        guard SaveStore.shared.settings.ambientEnabled else { return }
        currentAmbient = track
        start()
        guard let url = Self.url(for: track.assetName),
              let player = try? AVAudioPlayer(contentsOf: url) else {
            scheduleAmbientPulse()
            return
        }
        ambientTimer?.invalidate()
        ambientTimer = nil
        let outgoing = ambientPlayer
        ambientPlayer = nil
        outgoing?.setVolume(0, fadeDuration: fade)
        if let outgoing { DispatchQueue.main.asyncAfter(deadline: .now() + fade + 0.1) { outgoing.stop() } }
        player.numberOfLoops = -1
        player.volume = 0
        player.prepareToPlay()
        player.play()
        player.setVolume(Float(SaveStore.shared.settings.audioVolume) * Self.ambientGain, fadeDuration: fade)
        ambientPlayer = player
    }

    func stopAmbient(fade: TimeInterval = 0.8) {
        currentAmbient = nil
        ambientTimer?.invalidate()
        ambientTimer = nil
        guard let outgoing = ambientPlayer else { return }
        ambientPlayer = nil
        outgoing.setVolume(0, fadeDuration: fade)
        DispatchQueue.main.asyncAfter(deadline: .now() + fade + 0.1) { outgoing.stop() }
    }

    func setAmbientEnabled(_ enabled: Bool) {
        guard enabled else {
            stopAmbient()
            stopMusic()
            setFreezeLayer(false)
            return
        }
        start()
        if let currentAmbient { playAmbient(currentAmbient) }
    }

    /// Synthesised fallback for when `amb_table_room.wav` is not in the bundle.
    private func scheduleAmbientPulse() {
        guard ambientTimer == nil, SaveStore.shared.settings.ambientEnabled else { return }
        ambientTimer = Timer.scheduledTimer(withTimeInterval: 5.4, repeats: true) { [weak self] _ in
            guard let self, SaveStore.shared.settings.ambientEnabled else { return }
            let volume = Float(SaveStore.shared.settings.audioVolume) * 0.035
            self.synth.scheduleBuffer(self.makeTone(frequency: 110, duration: 1.8, amplitude: volume))
        }
    }

    // MARK: - Loading

    /// The asset folder is a synchronised group, so the built bundle may keep the
    /// `audio/` grouping or flatten it. Both layouts are probed.
    static func url(for name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "wav")
            ?? Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "audio")
    }

    private func effectVoice(for effect: SoundEffect) -> EffectVoice? {
        if let cached = effectVoices[effect] { return cached }
        guard let voice = EffectVoice(named: effect.assetName) else { return nil }
        effectVoices[effect] = voice
        return voice
    }

    // MARK: - Synthesis

    private func playSynth(_ notes: [(frequency: Double, duration: Double, amplitude: Float)]) {
        let volume = SaveStore.shared.settings.audioVolume
        for note in notes {
            let buffer = makeTone(
                frequency: note.frequency,
                duration: note.duration,
                amplitude: note.amplitude * Float(volume)
            )
            synth.scheduleBuffer(buffer, at: nil, options: [])
        }
    }

    private func makeTone(frequency: Double, duration: Double, amplitude: Float) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(duration * format.sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let samples = buffer.floatChannelData![0]
        let attackFrames = max(1, Int(Double(frameCount) * 0.08))
        let releaseFrames = max(1, Int(Double(frameCount) * 0.35))
        for frame in 0..<Int(frameCount) {
            let phase = Double(frame) / format.sampleRate * frequency * 2 * .pi
            let attack = min(1, Float(frame) / Float(attackFrames))
            let releaseStart = Int(frameCount) - releaseFrames
            let release = frame > releaseStart
                ? max(0, Float(Int(frameCount) - frame) / Float(releaseFrames))
                : 1
            let fundamental = sin(phase)
            let harmonic = sin(phase * 2.01) * 0.18
            samples[frame] = Float(fundamental + harmonic) * amplitude * attack * release
        }
        return buffer
    }
}

/// A preloaded file-backed voice. Rewinding and replaying an existing player
/// avoids an allocation on every tile collision.
private final class EffectVoice {
    private let player: AVAudioPlayer

    init?(named name: String) {
        guard let url = AudioService.url(for: name),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.prepareToPlay()
        self.player = player
    }

    func play(volume: Float) {
        player.volume = volume
        player.currentTime = 0
        player.play()
    }
}
