//
//  WhiskumiTests.swift
//  WhiskumiTests
//
//  Created by Kőszegi Zoltán on 2026. 11. 07..
//

import CoreGraphics
import Foundation
import Testing
@testable import Whiskumi

/// Deterministic generator so statistical tests are repeatable.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Needs

struct CatNeedsTests {
    @Test func passiveDecayIsGentleAndNeverHitsZero() {
        var needs = CatNeeds()
        needs.advance(by: 200 * 3600, sleeping: false)
        #expect(needs.fullness >= CatNeeds.Floors.fullness)
        #expect(needs.hydration >= CatNeeds.Floors.hydration)
        #expect(needs.energy >= CatNeeds.Floors.energy)
        #expect(needs.affection >= CatNeeds.Floors.affection)
    }

    @Test func oneHourOnlyChangesNeedsALittle() {
        var needs = CatNeeds()
        let before = needs
        needs.advance(by: 3600, sleeping: false)
        #expect(before.fullness - needs.fullness < 0.15)
        #expect(before.hydration - needs.hydration < 0.15)
    }

    @Test func sleepingRestoresEnergyAndActivityDrainsIt() {
        var resting = CatNeeds(energy: 0.5)
        var active = CatNeeds(energy: 0.5)
        var sleeping = CatNeeds(energy: 0.3)
        resting.advance(by: 1800, sleeping: false, activity: 0)
        active.advance(by: 1800, sleeping: false, activity: 1)
        sleeping.advance(by: 1800, sleeping: true)
        #expect(active.energy < resting.energy)
        #expect(sleeping.energy > 0.3)
    }

    @Test func offlineTimeIsCappedAndForgiving() {
        var needs = CatNeeds(fullness: 0.9, hydration: 0.9, energy: 0.4, happiness: 0.8, affection: 0.6)
        needs.applyOfflineTime(30 * 24 * 3600) // a month away
        #expect(needs.fullness >= CatNeeds.Floors.offlineFullness)
        #expect(needs.hydration >= CatNeeds.Floors.offlineHydration)
        #expect(needs.energy > 0.4, "Whiskumi naps while you are away")
        #expect(needs.happiness > 0.4)
    }

    @Test func caringActionsRaiseNeedsAndStayInRange() {
        var needs = CatNeeds(fullness: 0.95, hydration: 0.2, energy: 0.5, happiness: 0.5, affection: 0.98)
        needs.eat(nourishment: 0.5, joy: 0.1)
        needs.drink(0.45)
        needs.receivePets()
        #expect(needs.fullness == 1)
        #expect(needs.hydration > 0.6)
        #expect(needs.affection <= 1)
    }

    @Test func moodReflectsNeedsAndState() {
        #expect(CatMood.evaluate(needs: CatNeeds(), state: .sleeping) == .sleeping)
        #expect(CatMood.evaluate(needs: CatNeeds(fullness: 0.1), state: .idle) == .hungry)
        #expect(CatMood.evaluate(needs: CatNeeds(energy: 0.1), state: .idle) == .sleepy)
        #expect(CatMood.evaluate(needs: CatNeeds(happiness: 0.9, affection: 0.9), state: .idle) == .loving)
    }
}

// MARK: - Personality

struct CatPersonalityTests {
    @Test func nudgesAreSmallAndBounded() {
        var personality = CatPersonality()
        personality.nudge(.playfulness, by: 0.01)
        #expect(personality.playfulness > 0.5 && personality.playfulness < 0.52)
        for _ in 0..<20_000 { personality.nudge(.playfulness, by: 0.01) }
        #expect(personality.playfulness <= CatPersonality.range.upperBound)
        #expect(personality.laziness >= CatPersonality.range.lowerBound)
    }

    @Test func newbornsVaryButStayBalanced() {
        for _ in 0..<50 {
            let p = CatPersonality.newborn()
            for trait in CatPersonality.Trait.allCases {
                #expect((0.35...0.65).contains(p[trait]))
            }
        }
    }

    @Test func summaryNamesStrongTraits() {
        let p = CatPersonality(playfulness: 0.8, laziness: 0.2, curiosity: 0.7, affection: 0.4)
        #expect(p.summary.contains("playful"))
        #expect(p.dominantTrait == .playfulness)
    }
}

// MARK: - Behaviour engine

struct CatBehaviorEngineTests {
    private func weight(_ activity: CatActivity, in weights: [(CatActivity, Double)]) -> Double {
        weights.first { $0.0 == activity }?.1 ?? 0
    }

    @Test func defaultDistributionFollowsTheBaseTable() {
        var generator = SplitMix64(seed: 42)
        var counts: [CatActivity: Int] = [:]
        let context = BehaviorContext(needs: CatNeeds(energy: 0.6))
        let picks = 20_000
        for _ in 0..<picks {
            var engine = CatBehaviorEngine() // fresh each time: no repetition damping
            counts[engine.choose(context, using: &generator), default: 0] += 1
        }
        let idleShare = Double(counts[.idle, default: 0]) / Double(picks)
        let walkShare = Double(counts[.walk, default: 0]) / Double(picks)
        #expect((0.30...0.40).contains(idleShare))
        #expect((0.07...0.14).contains(walkShare))
    }

    @Test func tiredCatsNapMore() {
        let engine = CatBehaviorEngine()
        let rested = engine.weights(for: BehaviorContext(needs: CatNeeds(energy: 0.9)))
        let tired = engine.weights(for: BehaviorContext(needs: CatNeeds(energy: 0.05)))
        #expect(weight(.nap, in: tired) > weight(.nap, in: rested) * 10)
        #expect(weight(.walk, in: tired) < weight(.walk, in: rested))
    }

    @Test func personalityShapesChoices() {
        let engine = CatBehaviorEngine()
        let playful = engine.weights(for: BehaviorContext(personality: CatPersonality(playfulness: 0.9, laziness: 0.1)))
        let lazy = engine.weights(for: BehaviorContext(personality: CatPersonality(playfulness: 0.1, laziness: 0.9)))
        #expect(weight(.rollOver, in: playful) > weight(.rollOver, in: lazy))
        #expect(weight(.lieDown, in: lazy) > weight(.lieDown, in: playful))
    }

    @Test func settingsCanStopWalkingAndRandomActivities() {
        let engine = CatBehaviorEngine()
        let stayPut = engine.weights(for: BehaviorContext(autonomousMovement: false))
        #expect(weight(.walk, in: stayPut) == 0)
        #expect(weight(.zoomies, in: stayPut) == 0)
        let quiet = engine.weights(for: BehaviorContext(randomActivities: false))
        #expect(quiet.filter { $0.1 > 0 }.map(\.0) == [.idle])
    }

    @Test func recentActivitiesAreDamped() {
        var engine = CatBehaviorEngine()
        let before = weight(.groom, in: engine.weights(for: BehaviorContext()))
        engine.record(.groom)
        let after = weight(.groom, in: engine.weights(for: BehaviorContext()))
        #expect(after < before * 0.2)
    }

    @Test func unavailableActivitiesAreNeverChosen() {
        var generator = SplitMix64(seed: 7)
        var engine = CatBehaviorEngine()
        let context = BehaviorContext(available: [.idle, .groom])
        for _ in 0..<500 {
            #expect([.idle, .groom].contains(engine.choose(context, using: &generator)))
        }
    }

    @Test func weightedRandomRespectsWeights() {
        var generator = SplitMix64(seed: 1)
        var hits = 0
        for _ in 0..<10_000 where WeightedRandom.pick([("a", 9.0), ("b", 1.0), ("c", 0)], using: &generator) == "a" {
            hits += 1
        }
        #expect((8700...9300).contains(hits))
        #expect(WeightedRandom.pick([("x", 0.0)], using: &generator) == nil)
    }
}

// MARK: - Petting

struct PettingHandlerTests {
    @Test func singleClicksArePets() {
        var petting = PettingHandler()
        #expect(petting.registerClick(at: 0) == .pet)
        #expect(petting.registerClick(at: 5) == .pet)
    }

    @Test func rapidClicksAreOverPetting() {
        var petting = PettingHandler()
        var results: [PettingHandler.ClickResult] = []
        for i in 0..<PettingHandler.overPetClicks { results.append(petting.registerClick(at: Double(i) * 0.2)) }
        #expect(results.last == .overPetted)
        #expect(petting.registerClick(at: 2) == .pet, "cooldown after an over-pet")
    }

    @Test func backAndForthStrokingIsPetting() {
        var petting = PettingHandler()
        var detected = false
        var x: CGFloat = 100
        var t = 0.0
        for stroke in 0..<6 {
            for _ in 0..<5 {
                x += stroke.isMultiple(of: 2) ? 6 : -6
                t += 0.03
                if petting.registerHover(x: x, at: t) { detected = true }
            }
        }
        #expect(detected)
    }

    @Test func passingOverTheCatIsNotPetting() {
        var petting = PettingHandler()
        var detected = false
        for i in 0..<30 where petting.registerHover(x: CGFloat(i) * 8, at: Double(i) * 0.03) {
            detected = true
        }
        #expect(!detected)
    }
}

// MARK: - Persistence

struct PersistenceTests {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("WhiskumiTests-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func saveAndLoadRoundTrip() throws {
        let manager = PersistenceManager(directory: temporaryDirectory())
        var data = CatSaveData()
        data.needs = CatNeeds(fullness: 0.42, hydration: 0.33, energy: 0.21, happiness: 0.9, affection: 0.77)
        data.personality = CatPersonality(playfulness: 0.8, laziness: 0.2, curiosity: 0.6, affection: 0.7)
        data.stats.pets = 12
        data.savedAt = Date(timeIntervalSince1970: 1_800_000_000)
        try manager.save(data)
        let loaded = try #require(manager.load())
        #expect(loaded.needs == data.needs)
        #expect(loaded.personality == data.personality)
        #expect(loaded.stats.pets == 12)
        #expect(loaded.savedAt == data.savedAt)
    }

    @Test func missingFileLoadsNothing() {
        #expect(PersistenceManager(directory: temporaryDirectory()).load() == nil)
    }

    @Test func corruptFileIsSetAsideNotFatal() throws {
        let directory = temporaryDirectory()
        let manager = PersistenceManager(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: manager.fileURL)
        #expect(manager.load() == nil)
        #expect(!FileManager.default.fileExists(atPath: manager.fileURL.path))
        let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(backups.contains { $0.contains("corrupt") })
    }
}

// MARK: - Sprites

struct SpriteLibraryTests {
    @Test func everyAnimationAndPropLoadsFromTheAppBundle() throws {
        let library = try SpriteLibrary(bundle: .main)
        for animation in CatAnimation.allCases {
            #expect(library.has(animation), "missing \(animation.rawValue)")
        }
        for prop in ["ball", "zSmall", "zMedium", "zLarge", "heartSmall", "heart", "question", "exclaim", "thought", "puff"] {
            #expect(library.prop(prop) != nil, "missing prop \(prop)")
        }
    }

    @Test func framesShareTheirCanvasAndAnchorsAreInside() throws {
        let library = try SpriteLibrary(bundle: .main)
        for animation in CatAnimation.allCases {
            let data = try #require(library.animation(animation))
            for frame in data.frames {
                #expect(frame.image.width == Int(data.size.width))
                #expect(frame.image.height == Int(data.size.height))
            }
            #expect(data.anchor.x > 0 && data.anchor.x < data.size.width)
            #expect(data.anchor.y > data.size.height * 0.5 && data.anchor.y <= data.size.height)
        }
    }

    @Test func clipsOnlyReferenceExistingFrames() throws {
        let library = try SpriteLibrary(bundle: .main)
        for clip in Clips.all {
            let data = try #require(library.animation(clip.animation))
            for step in clip.frames {
                #expect(step.index < data.frames.count, "\(clip.animation.rawValue) frame \(step.index)")
                #expect(step.duration > 0)
            }
        }
    }

    @Test func alphaMasksKnowWhereTheCatIs() throws {
        let library = try SpriteLibrary(bundle: .main)
        let idle = try #require(library.animation(.idle))
        let mask = idle.frame(at: 0).mask
        #expect(!mask.isOpaque(x: 0, y: 0), "corners are transparent")
        // Just above the feet, under the head, is solid cat.
        #expect(mask.isOpaque(x: Int(idle.anchor.x), y: Int(idle.anchor.y) - 30, radius: 2))
    }

    @Test func fallbacksAlwaysProduceTheCat() throws {
        let library = try SpriteLibrary(bundle: .main)
        for animation in CatAnimation.allCases {
            #expect(library.animation(animation) != nil)
        }
    }
}

// MARK: - Pixel-art scaling

struct PixelScaleTests {
    @Test func defaultIsFourDevicePixelsPerThreeArtPixelsOnRetina() {
        let ppp = PixelScale.pointsPerPixel(size: 1, quality: .pixelPerfect, backingScale: 2)
        #expect(abs(ppp - 2.0 / 3.0) < 0.000_001)
        #expect(abs(ppp * 2 - 4.0 / 3.0) < 0.000_001)
    }

    @Test func defaultIsAboutThirtyPercentSmallerThanBefore() throws {
        let library = try SpriteLibrary(bundle: .main)
        let ppp = PixelScale.pointsPerPixel(size: 1, quality: .pixelPerfect, backingScale: 2)
        let height = library.standingHeight * ppp
        let before = library.standingHeight * 1.0
        #expect((80...90).contains(height), "cat is \(height) pt tall")
        #expect((0.28...0.38).contains(1 - height / before))
    }

    @Test func pixelPerfectOnlyUsesCrispRatiosAndNeverDropsPixels() {
        for backing: CGFloat in [1, 2, 3] {
            for size in stride(from: AppSettings.sizeRange.lowerBound, through: AppSettings.sizeRange.upperBound, by: 0.05) {
                let ratio = PixelScale.pointsPerPixel(size: size, quality: .pixelPerfect, backingScale: backing) * backing
                #expect(PixelScale.crispRatios.contains { abs($0 - ratio) < 0.000_001 }, "ratio \(ratio)")
                #expect(ratio >= 1)
            }
        }
    }

    @Test func sharpAndSmoothUseTheExactRequestedSize() {
        #expect(abs(PixelScale.pointsPerPixel(size: 1.1, quality: .sharp, backingScale: 2) - 2.0 / 3.0 * 1.1) < 0.000_001)
        #expect(abs(PixelScale.pointsPerPixel(size: 0.9, quality: .smooth, backingScale: 2) - 2.0 / 3.0 * 0.9) < 0.000_001)
    }

    @Test func everySpriteLandsOnWholeDevicePixels() throws {
        let library = try SpriteLibrary(bundle: .main)
        for size in [1.0, 1.25, 1.5, 2.25] {
            let grid = PixelGrid(backingScale: 2, pointsPerPixel: PixelScale.pointsPerPixel(size: size, quality: .pixelPerfect, backingScale: 2))
            for animation in CatAnimation.allCases {
                let data = try #require(library.animation(animation))
                for flipped in [false, true] {
                    for foot in [CGPoint(x: 159, y: 18), CGPoint(x: 160.5, y: 18.5)] {
                        let frame = grid.spriteFrame(canvas: data.size, anchor: data.anchor, flipped: flipped, foot: foot)
                        #expect([frame.minX, frame.minY, frame.width, frame.height].allSatisfy(grid.isAligned), "\(animation) \(frame)")
                        // The anchor (head centre, ground line) stays on the feet within a device pixel.
                        let anchorX = flipped ? frame.maxX - grid.length(data.anchor.x) : frame.minX + grid.length(data.anchor.x)
                        #expect(abs(anchorX - foot.x) <= 0.5)
                        // Proportions are preserved to within a device pixel.
                        #expect(abs(frame.width / frame.height - data.size.width / data.size.height) < 0.02)
                    }
                }
                for emote in data.emotes {
                    let sprite = grid.spriteFrame(canvas: data.size, anchor: data.anchor, flipped: true, foot: CGPoint(x: 159, y: 18))
                    let prop = grid.propFrame(origin: emote.origin, size: CGSize(width: 20, height: 21), onSprite: sprite, flipped: true)
                    #expect([prop.minX, prop.minY, prop.width, prop.height].allSatisfy(grid.isAligned))
                }
            }
        }
    }
}

// MARK: - Settings

@MainActor
struct AppSettingsTests {
    private func makeDefaults() -> UserDefaults {
        let name = "WhiskumiTests-\(UUID().uuidString)"
        return UserDefaults(suiteName: name) ?? .standard
    }

    @Test func defaultsAreGentle() {
        let settings = AppSettings(defaults: makeDefaults())
        #expect(settings.soundEffects == false)
        #expect(settings.notificationsEnabled == false)
        #expect(settings.catSize == 1)
        #expect(settings.matchingPreset == .balanced)
    }

    @Test func changesPersistAcrossInstances() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.catSize = 1.5
        settings.windowLayer = .desktop
        settings.cursorReactions = false
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.catSize == 1.5)
        #expect(reloaded.windowLayer == .desktop)
        #expect(reloaded.cursorReactions == false)
    }

    @Test func observersHearAboutChanges() {
        let settings = AppSettings(defaults: makeDefaults())
        var heard: [AppSettings.Key] = []
        settings.addObserver { heard.append($0) }
        settings.sleepFrequency = 0.9
        #expect(heard == [.sleepFrequency])
    }

    @Test func legacyDefaultSizeMovesToTheNewSmallerDefault() {
        let defaults = makeDefaults()
        defaults.set(1.0, forKey: "catScale")
        let settings = AppSettings(defaults: defaults)
        #expect(settings.catSize == 1)
        #expect(defaults.object(forKey: "catScale") == nil)
    }

    @Test func legacyCustomSizeKeepsItsOnScreenSize() {
        let defaults = makeDefaults()
        defaults.set(1.5, forKey: "catScale") // 1.5 pt per art pixel
        let settings = AppSettings(defaults: defaults)
        #expect(abs(settings.catSize * Double(PixelScale.basePointsPerPixel) - 1.5) < 0.0001)
    }

    @Test func presetsApplyAndAreRecognised() {
        let settings = AppSettings(defaults: makeDefaults())
        settings.apply(.stayPut)
        #expect(settings.autonomousMovement == false)
        #expect(settings.matchingPreset == .stayPut)
        settings.apply(.lively)
        #expect(settings.matchingPreset == .lively)
        settings.walkingFrequency = 0.11
        #expect(settings.matchingPreset == nil)
    }
}
