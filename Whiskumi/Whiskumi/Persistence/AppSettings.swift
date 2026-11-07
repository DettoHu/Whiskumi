import Foundation
import Observation

nonisolated enum WindowLayer: String, CaseIterable, Identifiable, Sendable {
    case aboveAll, normal, desktop
    var id: String { rawValue }
    var title: String {
        switch self {
        case .aboveAll: "Always on Top"
        case .normal: "With Other Windows"
        case .desktop: "On the Desktop"
        }
    }
    var detail: String {
        switch self {
        case .aboveAll: "Whiskumi stays visible above your apps."
        case .normal: "Apps you use can cover Whiskumi."
        case .desktop: "Whiskumi lives on the desktop, behind every window."
        }
    }
}

nonisolated enum RenderQuality: String, CaseIterable, Identifiable, Sendable {
    case pixelPerfect, sharp, smooth
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pixelPerfect: "Pixel Perfect"
        case .sharp: "Sharp"
        case .smooth: "Smooth"
        }
    }
    var detail: String {
        switch self {
        case .pixelPerfect: "Nearest-neighbour pixels at sizes where they map evenly onto your screen."
        case .sharp: "Nearest-neighbour pixels at exactly the size you choose."
        case .smooth: "Blends neighbouring pixels for a softer look (no mipmapping)."
        }
    }
}

nonisolated enum DefaultPosition: String, CaseIterable, Identifiable, Sendable {
    case bottomLeft, bottomCenter, bottomRight, center
    var id: String { rawValue }
    var title: String {
        switch self {
        case .bottomLeft: "Bottom Left"
        case .bottomCenter: "Bottom Center"
        case .bottomRight: "Bottom Right"
        case .center: "Center"
        }
    }
}

nonisolated enum BehaviorPreset: String, CaseIterable, Identifiable, Sendable {
    case lively, balanced, calm, stayPut
    var id: String { rawValue }
    var title: String {
        switch self {
        case .lively: "Lively"
        case .balanced: "Balanced"
        case .calm: "Calm"
        case .stayPut: "Stay Put"
        }
    }
    var detail: String {
        switch self {
        case .lively: "Busy, playful and on the move."
        case .balanced: "A natural mix of naps and adventures."
        case .calm: "Mostly lounging, rarely wandering."
        case .stayPut: "Never walks away from where you leave it."
        }
    }
}

/// All user preferences, persisted to `UserDefaults` as soon as they change.
@Observable
final class AppSettings {
    enum Key: String, CaseIterable {
        case showCatOnLaunch, windowLayer, showOnAllDesktops, restorePosition, showMenuBarIcon
        case catSize, animationSpeed, renderQuality, visualEffects, groundShadow, defaultPosition
        case activityFrequency, walkingFrequency, sleepFrequency, randomActivities, cursorReactions, autonomousMovement
        case masterVolume, soundEffects, meowing, interactionSounds
        case notificationsEnabled, feedingReminders, waterReminders
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var observers: [UUID: (Key) -> Void] = [:]
    @ObservationIgnored private var isLoading = true

    // General
    var showCatOnLaunch: Bool { didSet { changed(.showCatOnLaunch, showCatOnLaunch) } }
    var windowLayer: WindowLayer { didSet { changed(.windowLayer, windowLayer.rawValue) } }
    var showOnAllDesktops: Bool { didSet { changed(.showOnAllDesktops, showOnAllDesktops) } }
    var restorePosition: Bool { didSet { changed(.restorePosition, restorePosition) } }
    var showMenuBarIcon: Bool { didSet { changed(.showMenuBarIcon, showMenuBarIcon) } }

    // Appearance
    /// Relative cat size; 1.0 (100 %) is the default size of about 85 pt. See `PixelScale`.
    var catSize: Double { didSet { changed(.catSize, catSize) } }
    var animationSpeed: Double { didSet { changed(.animationSpeed, animationSpeed) } }
    var renderQuality: RenderQuality { didSet { changed(.renderQuality, renderQuality.rawValue) } }
    var visualEffects: Bool { didSet { changed(.visualEffects, visualEffects) } }
    var groundShadow: Bool { didSet { changed(.groundShadow, groundShadow) } }
    var defaultPosition: DefaultPosition { didSet { changed(.defaultPosition, defaultPosition.rawValue) } }

    // Behaviour (0...1 sliders, 0.5 is the natural default)
    var activityFrequency: Double { didSet { changed(.activityFrequency, activityFrequency) } }
    var walkingFrequency: Double { didSet { changed(.walkingFrequency, walkingFrequency) } }
    var sleepFrequency: Double { didSet { changed(.sleepFrequency, sleepFrequency) } }
    var randomActivities: Bool { didSet { changed(.randomActivities, randomActivities) } }
    var cursorReactions: Bool { didSet { changed(.cursorReactions, cursorReactions) } }
    var autonomousMovement: Bool { didSet { changed(.autonomousMovement, autonomousMovement) } }

    // Sound
    var masterVolume: Double { didSet { changed(.masterVolume, masterVolume) } }
    var soundEffects: Bool { didSet { changed(.soundEffects, soundEffects) } }
    var meowing: Bool { didSet { changed(.meowing, meowing) } }
    var interactionSounds: Bool { didSet { changed(.interactionSounds, interactionSounds) } }

    // Notifications
    var notificationsEnabled: Bool { didSet { changed(.notificationsEnabled, notificationsEnabled) } }
    var feedingReminders: Bool { didSet { changed(.feedingReminders, feedingReminders) } }
    var waterReminders: Bool { didSet { changed(.waterReminders, waterReminders) } }

    /// 75 % is one device pixel per art pixel on Retina, the smallest size that never drops pixels.
    static let sizeRange: ClosedRange<Double> = 0.75...3.0
    static let speedRange: ClosedRange<Double> = 0.5...1.5

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        Self.migrateLegacySize(in: defaults)
        defaults.register(defaults: [
            Key.showCatOnLaunch.rawValue: true,
            Key.windowLayer.rawValue: WindowLayer.aboveAll.rawValue,
            Key.showOnAllDesktops.rawValue: true,
            Key.restorePosition.rawValue: true,
            Key.showMenuBarIcon.rawValue: true,
            Key.catSize.rawValue: 1.0,
            Key.animationSpeed.rawValue: 1.0,
            Key.renderQuality.rawValue: RenderQuality.pixelPerfect.rawValue,
            Key.visualEffects.rawValue: true,
            Key.groundShadow.rawValue: true,
            Key.defaultPosition.rawValue: DefaultPosition.bottomRight.rawValue,
            Key.activityFrequency.rawValue: 0.5,
            Key.walkingFrequency.rawValue: 0.5,
            Key.sleepFrequency.rawValue: 0.5,
            Key.randomActivities.rawValue: true,
            Key.cursorReactions.rawValue: true,
            Key.autonomousMovement.rawValue: true,
            Key.masterVolume.rawValue: 0.4,
            Key.soundEffects.rawValue: false,
            Key.meowing.rawValue: true,
            Key.interactionSounds.rawValue: true,
            Key.notificationsEnabled.rawValue: false,
            Key.feedingReminders.rawValue: true,
            Key.waterReminders.rawValue: true,
        ])
        showCatOnLaunch = defaults.bool(forKey: Key.showCatOnLaunch.rawValue)
        windowLayer = WindowLayer(rawValue: defaults.string(forKey: Key.windowLayer.rawValue) ?? "") ?? .aboveAll
        showOnAllDesktops = defaults.bool(forKey: Key.showOnAllDesktops.rawValue)
        restorePosition = defaults.bool(forKey: Key.restorePosition.rawValue)
        showMenuBarIcon = defaults.bool(forKey: Key.showMenuBarIcon.rawValue)
        catSize = defaults.double(forKey: Key.catSize.rawValue).clamped(to: Self.sizeRange)
        animationSpeed = defaults.double(forKey: Key.animationSpeed.rawValue).clamped(to: Self.speedRange)
        renderQuality = RenderQuality(rawValue: defaults.string(forKey: Key.renderQuality.rawValue) ?? "") ?? .pixelPerfect
        visualEffects = defaults.bool(forKey: Key.visualEffects.rawValue)
        groundShadow = defaults.bool(forKey: Key.groundShadow.rawValue)
        defaultPosition = DefaultPosition(rawValue: defaults.string(forKey: Key.defaultPosition.rawValue) ?? "") ?? .bottomRight
        activityFrequency = defaults.double(forKey: Key.activityFrequency.rawValue).clamped(to: 0...1)
        walkingFrequency = defaults.double(forKey: Key.walkingFrequency.rawValue).clamped(to: 0...1)
        sleepFrequency = defaults.double(forKey: Key.sleepFrequency.rawValue).clamped(to: 0...1)
        randomActivities = defaults.bool(forKey: Key.randomActivities.rawValue)
        cursorReactions = defaults.bool(forKey: Key.cursorReactions.rawValue)
        autonomousMovement = defaults.bool(forKey: Key.autonomousMovement.rawValue)
        masterVolume = defaults.double(forKey: Key.masterVolume.rawValue).clamped(to: 0...1)
        soundEffects = defaults.bool(forKey: Key.soundEffects.rawValue)
        meowing = defaults.bool(forKey: Key.meowing.rawValue)
        interactionSounds = defaults.bool(forKey: Key.interactionSounds.rawValue)
        notificationsEnabled = defaults.bool(forKey: Key.notificationsEnabled.rawValue)
        feedingReminders = defaults.bool(forKey: Key.feedingReminders.rawValue)
        waterReminders = defaults.bool(forKey: Key.waterReminders.rawValue)
        isLoading = false
    }

    /// Earlier versions stored `catScale` in absolute points per art pixel, with 1.0 as the
    /// default. An untouched default moves to the new, smaller default; a customised size keeps
    /// its on-screen size.
    static func migrateLegacySize(in defaults: UserDefaults) {
        let legacyKey = "catScale"
        guard let legacy = defaults.object(forKey: legacyKey) as? Double else { return }
        // The legacy key is removed once migrated, so its presence means this hasn't run yet.
        if abs(legacy - 1) > 0.01 {
            let size = (legacy / Double(PixelScale.basePointsPerPixel)).clamped(to: sizeRange)
            defaults.set(size, forKey: Key.catSize.rawValue)
        }
        defaults.removeObject(forKey: legacyKey)
    }

    /// Registers a change handler; returns a token for `removeObserver`.
    @discardableResult
    func addObserver(_ handler: @escaping (Key) -> Void) -> UUID {
        let id = UUID()
        observers[id] = handler
        return id
    }

    func removeObserver(_ id: UUID) {
        observers[id] = nil
    }

    private func changed(_ key: Key, _ value: Any) {
        guard !isLoading else { return }
        defaults.set(value, forKey: key.rawValue)
        for handler in observers.values { handler(key) }
    }

    // MARK: - Behaviour presets

    var matchingPreset: BehaviorPreset? {
        BehaviorPreset.allCases.first { preset in
            let v = Self.values(for: preset)
            return abs(activityFrequency - v.activity) < 0.01 && abs(walkingFrequency - v.walking) < 0.01
                && autonomousMovement == v.movement
        }
    }

    func apply(_ preset: BehaviorPreset) {
        let v = Self.values(for: preset)
        activityFrequency = v.activity
        walkingFrequency = v.walking
        autonomousMovement = v.movement
        if preset != .stayPut { randomActivities = true }
    }

    private static func values(for preset: BehaviorPreset) -> (activity: Double, walking: Double, movement: Bool) {
        switch preset {
        case .lively: (0.85, 0.75, true)
        case .balanced: (0.5, 0.5, true)
        case .calm: (0.2, 0.2, true)
        case .stayPut: (0.5, 0.5, false)
        }
    }

    /// Restores every preference to its default value.
    func resetToDefaults() {
        for key in Key.allCases { defaults.removeObject(forKey: key.rawValue) }
        let fresh = AppSettings(defaults: defaults)
        showCatOnLaunch = fresh.showCatOnLaunch
        windowLayer = fresh.windowLayer
        showOnAllDesktops = fresh.showOnAllDesktops
        restorePosition = fresh.restorePosition
        showMenuBarIcon = fresh.showMenuBarIcon
        catSize = fresh.catSize
        animationSpeed = fresh.animationSpeed
        renderQuality = fresh.renderQuality
        visualEffects = fresh.visualEffects
        groundShadow = fresh.groundShadow
        defaultPosition = fresh.defaultPosition
        activityFrequency = fresh.activityFrequency
        walkingFrequency = fresh.walkingFrequency
        sleepFrequency = fresh.sleepFrequency
        randomActivities = fresh.randomActivities
        cursorReactions = fresh.cursorReactions
        autonomousMovement = fresh.autonomousMovement
        masterVolume = fresh.masterVolume
        soundEffects = fresh.soundEffects
        meowing = fresh.meowing
        interactionSounds = fresh.interactionSounds
        notificationsEnabled = fresh.notificationsEnabled
        feedingReminders = fresh.feedingReminders
        waterReminders = fresh.waterReminders
    }
}
