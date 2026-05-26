import Foundation

public struct SearchResult<Item>: Sendable where Item: Sendable {
    public let item: Item
    public let score: Double
    
    public init(item: Item, score: Double) {
        self.item = item
        self.score = score
    }
}
