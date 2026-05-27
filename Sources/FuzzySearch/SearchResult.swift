import Foundation

public struct SearchMatch: Sendable {
    public let value: String
    public let range: CountableClosedRange<Int>
    public let text: String
    
    public init(value: String, range: CountableClosedRange<Int>, text: String) {
        self.value = value
        self.range = range
        self.text = text
    }
}

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
}
