import Foundation

public struct SearchField: Sendable, Equatable {
    public let value: String
    public let weight: Double
    
    public init(_ value: String, weight: Double = 1) {
        self.value = value
        self.weight = weight
    }
}
