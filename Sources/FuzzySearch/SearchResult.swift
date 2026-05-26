import Foundation

public struct SearchResult<Item>: Sendable where Item: Sendable {
    public let item: Item
    public let score: Double
    public let index: Int?
    
    public init(item: Item, score: Double, index: Int? = nil) {
        self.item = item
        self.score = score
        self.index = index
    }
}
