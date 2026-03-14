import Foundation

enum BranchNameGenerator {
    private static let adjectives = [
        "swift", "bright", "calm", "dark", "eager", "fair", "glad", "bold",
        "keen", "lazy", "neat", "proud", "quick", "rare", "safe", "warm",
        "wild", "cool", "deep", "flat", "gold", "iron", "jade", "lush",
        "mild", "pale", "rich", "slim", "soft", "tall", "vast", "wise",
    ]

    private static let nouns = [
        "fox", "oak", "river", "stone", "wind", "hawk", "pine", "lake",
        "bear", "dawn", "fern", "grove", "hill", "jade", "leaf", "moss",
        "owl", "peak", "rain", "sage", "tide", "vale", "wolf", "cedar",
        "cliff", "dusk", "elm", "flame", "glow", "haze", "iris", "lark",
    ]

    struct Result {
        let branchName: String  // e.g. "openowl/calm-vale"
        let dirName: String     // e.g. "calm-vale"
    }

    static func generate(prefix: String) -> Result {
        let slug = "\(adjectives.randomElement()!)-\(nouns.randomElement()!)"
        return Result(
            branchName: "\(prefix)/\(slug)",
            dirName: slug
        )
    }
}
