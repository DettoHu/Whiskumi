import os

nonisolated enum Log {
    static let app = Logger(subsystem: "dettohu.Whiskumi", category: "app")
    static let sprites = Logger(subsystem: "dettohu.Whiskumi", category: "sprites")
    static let behavior = Logger(subsystem: "dettohu.Whiskumi", category: "behavior")
    static let persistence = Logger(subsystem: "dettohu.Whiskumi", category: "persistence")
    static let audio = Logger(subsystem: "dettohu.Whiskumi", category: "audio")
}
