import Foundation

public struct SearchResult<Item>: Sendable where Item: Sendable {
    public let item: Item
    public let score: Double
    public let index: Int?
    public let matches: [SearchMatch]
    
    public init(
        item: Item,
        score: Double,
        index: Int? = nil,
        matches: [SearchMatch] = []
    ) {
        self.item = item
        self.score = score
        self.index = index
        self.matches = matches
    }
    
    public var ranges: [CountableClosedRange<Int>] {
        matches.map(\.range)
    }
}
