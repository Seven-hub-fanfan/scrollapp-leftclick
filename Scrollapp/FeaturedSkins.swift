import Foundation

/// Public metadata and verified source downloads for personal local use.
struct FeaturedSkin: Identifiable {
    let id: String
    let slug: String
    let englishTitle: String
    let chineseTitle: String
    let englishCategory: String
    let chineseCategory: String
    let addedCountSnapshot: Int
    let sourceAddedText: String

    var sourceURL: URL { URL(string: "https://sweezy-cursors.com/cursor/\(slug)/")! }
    var archiveByteCount: Int { Self.archives[id]!.0 }
    var archiveSHA256: String { Self.archives[id]!.1 }
    private static let archives: [String: (Int, String)] = [
        "sweezy-sukuna": (42015, "d2db25312d3ab70e4dec5e95db95d8d046062ee8e7464789a0b9b49f9917007d"),
        "sweezy-hello-kitty": (40084, "b33d2ae24a81ba3ae7ccbba9c2b0a5fa61d1a5cffd223d7e328358a7d606b064"),
        "sweezy-lava": (46340, "d675c310432dcccd8b535487f4f8e955b2b18ec14bdeb1f7a291a1a628b856ee"),
        "sweezy-cinnamoroll-white": (31443, "211f15298c60e1ac71d2f1b0b27bc9b0b70f1aa2dab13303b2d223d8ab399d7c"),
        "sweezy-cinnamoroll-strawberry": (27557, "970e2a671f7c523613b03e7040c75b8b9da41c537bf5c1bea721a1d48bb6c8a2"),
        "sweezy-bmw-m4": (57195, "2e47b7ed1ab992d51c20275bdd896e663859de8a1e24a3c7b76a3cfe6506ae68"),
        "sweezy-old-roblox": (28771, "1aeec637277830044a56b791087cba947cad2d63268f8c828610eda52489be1b")
    ]
    var title: String {
        switch L10n.current {
        case .english: return englishTitle
        case .chineseSimplified: return chineseTitle
        }
    }
    var category: String {
        switch L10n.current {
        case .english: return englishCategory
        case .chineseSimplified: return chineseCategory
        }
    }

    // The source rounds some counters; preserve its displayed text and the
    // observation date rather than presenting a simulated live popularity feed.
    static let snapshotDate = "2026-11-15"
    static let all: [FeaturedSkin] = [
        .init(id: "sweezy-sukuna", slug: "jujutsu-kaisen-sukuna-flame-arrow-hand",
              englishTitle: "Sukuna Flame", chineseTitle: "宿傩 · 火焰",
              englishCategory: "Anime", chineseCategory: "动漫",
              addedCountSnapshot: 314_000, sourceAddedText: "314K"),
        .init(id: "sweezy-hello-kitty", slug: "sanrio-hello-kitty-white-arrow",
              englishTitle: "Hello Kitty", chineseTitle: "Hello Kitty · 白色箭头",
              englishCategory: "Cute", chineseCategory: "可爱",
              addedCountSnapshot: 235_000, sourceAddedText: "235K"),
        .init(id: "sweezy-lava", slug: "lava",
              englishTitle: "Lava", chineseTitle: "熔岩",
              englishCategory: "Basic", chineseCategory: "简约",
              addedCountSnapshot: 159_000, sourceAddedText: "159K"),
        .init(id: "sweezy-cinnamoroll-white", slug: "sanrio-cinnamoroll-white-arrow-head",
              englishTitle: "Cinnamoroll White", chineseTitle: "大耳狗 · 白色箭头",
              englishCategory: "Cute", chineseCategory: "可爱",
              addedCountSnapshot: 134_000, sourceAddedText: "134K"),
        .init(id: "sweezy-cinnamoroll-strawberry", slug: "sanrio-cinnamoroll-strawberry",
              englishTitle: "Cinnamoroll & Strawberry", chineseTitle: "大耳狗 · 草莓",
              englishCategory: "Cute", chineseCategory: "可爱",
              addedCountSnapshot: 102_000, sourceAddedText: "102K"),
        .init(id: "sweezy-bmw-m4", slug: "pixel-bmw-m4-racing-car",
              englishTitle: "Pixel BMW M4", chineseTitle: "BMW M4 · 像素赛车",
              englishCategory: "Cars", chineseCategory: "汽车",
              addedCountSnapshot: 94_100, sourceAddedText: "94.1K"),
        .init(id: "sweezy-old-roblox", slug: "old-roblox",
              englishTitle: "Old Roblox", chineseTitle: "经典 Roblox",
              englishCategory: "Games", chineseCategory: "游戏",
              addedCountSnapshot: 40_013, sourceAddedText: "40,013")
    ]
    static var ranked: [FeaturedSkin] {
        all.sorted {
            $0.addedCountSnapshot == $1.addedCountSnapshot
                ? $0.id < $1.id : $0.addedCountSnapshot > $1.addedCountSnapshot
        }
    }
    static func find(_ id: String) -> FeaturedSkin? { all.first { $0.id == id } }
}
