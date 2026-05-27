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
