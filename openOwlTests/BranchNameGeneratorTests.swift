import Testing
@testable import openOwl

@Suite("BranchNameGenerator")
struct BranchNameGeneratorTests {

    @Test func generate_format() {
        let result = BranchNameGenerator.generate(prefix: "sanvi")
        #expect(result.branchName.hasPrefix("sanvi/"))
        #expect(result.branchName.contains("-"))
        #expect(result.dirName.contains("-"))
        #expect(result.branchName == "sanvi/\(result.dirName)")
    }

    @Test func generate_differentResults() {
        // Generate multiple and check we get at least 2 distinct values (randomness)
        let results = (0..<20).map { _ in BranchNameGenerator.generate(prefix: "dev") }
        let unique = Set(results.map(\.dirName))
        #expect(unique.count > 1)
    }

    @Test func generate_slugFormat() {
        let result = BranchNameGenerator.generate(prefix: "p")
        let parts = result.dirName.split(separator: "-")
        #expect(parts.count == 2)
        // Both parts should be lowercase alphabetic
        let allLower = parts.allSatisfy { $0.allSatisfy { $0.isLowercase } }
        #expect(allLower)
    }
}
