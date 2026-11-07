import AVFoundation
import Foundation
import os

nonisolated enum SoundEffect: String, CaseIterable, Sendable {
    case meow, purr, eat, drink, sleep, play, interact

    enum Category: Sendable { case meowing, interaction, ambient }

    var category: Category {
        switch self {
        case .meow: .meowing
        case .purr, .interact, .play: .interaction
        case .eat, .drink, .sleep: .ambient
        }
    }

    var title: String {
        switch self {
        case .meow: "Meows"
        case .purr: "Purring"
        case .eat: "Eating"
        case .drink: "Drinking"
        case .sleep: "Sleeping"
        case .play: "Playing"
        case .interact: "Interactions"
        }
    }

    /// Minimum seconds between two plays of the same effect, so sounds stay subtle.
    var cooldown: TimeInterval {
        switch self {
        case .meow: 8
        case .purr: 4
        case .interact: 0.6
        case .play: 1.2
        case .eat, .drink: 3
        case .sleep: 10
        }
    }
}

/// Plays optional sound effects from audio files bundled in `Resources/Sounds`.
///
/// No audio ships with Whiskumi: drop files named after an effect (`meow.m4a`,
/// `meow_2.wav`, `purr.caf`, `eat_1.mp3`...) into `Resources/Sounds` and they are
/// discovered automatically. Without files every call is a silent no-op.
final class AudioManager {
    static let supportedExtensions: Set<String> = ["caf", "wav", "aif", "aiff", "m4a", "mp3"]

    private let settings: AppSettings
    private var catalog: [SoundEffect: [URL]] = [:]
    private var activePlayers: [AVAudioPlayer] = []
    private var lastPlayed: [SoundEffect: Date] = [:]

    init(settings: AppSettings, bundle: Bundle = .main) {
        self.settings = settings
        catalog = Self.discover(in: bundle)
        if catalog.isEmpty {
            Log.audio.info("No sound assets bundled; audio stays silent")
        }
    }

    var hasAnyAssets: Bool { !catalog.isEmpty }

    func hasAssets(for effect: SoundEffect) -> Bool { !(catalog[effect]?.isEmpty ?? true) }

    var availableEffects: [SoundEffect] { SoundEffect.allCases.filter(hasAssets(for:)) }

    func play(_ effect: SoundEffect, volume: Float = 1) {
        guard settings.soundEffects, let urls = catalog[effect], let url = urls.randomElement() else { return }
        switch effect.category {
        case .meowing where !settings.meowing: return
        case .interaction where !settings.interactionSounds: return
        default: break
        }
        if let last = lastPlayed[effect], Date().timeIntervalSince(last) < effect.cooldown { return }
        lastPlayed[effect] = Date()
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = Float(settings.masterVolume) * volume
            player.prepareToPlay()
            player.play()
            activePlayers.append(player)
            activePlayers.removeAll { !$0.isPlaying && $0 !== player }
        } catch {
            Log.audio.error("Could not play \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func stopAll() {
        activePlayers.forEach { $0.stop() }
        activePlayers.removeAll()
    }

    private static func discover(in bundle: Bundle) -> [SoundEffect: [URL]] {
        guard let root = bundle.resourceURL,
              let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [:] }
        var found: [SoundEffect: [URL]] = [:]
        for case let url as URL in enumerator where supportedExtensions.contains(url.pathExtension.lowercased()) {
            let base = url.deletingPathExtension().lastPathComponent.lowercased()
            let stem = base.split(separator: "_").first.map(String.init) ?? base
            if let effect = SoundEffect(rawValue: stem) {
                found[effect, default: []].append(url)
            }
        }
        return found
    }
}
