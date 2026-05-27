import Foundation

public struct SearchEvaluation: Sendable {
    public let score: Double
    public let matches: [SearchMatch]
    
    public init(score: Double, matches: [SearchMatch] = []) {
        self.score = score
        self.matches = matches
    }
}
