import Foundation

public struct PreparedSearchQuery: Sendable {
    public let rawValue: String
    internal let preparedText: PreparedText
    
    public var isEmpty: Bool {
        preparedText.text.isEmpty
    }
    
    public init(_ rawValue: String) {
        self.rawValue = rawValue
        self.preparedText = PreparedText(rawValue)
    }
    
    internal init(rawValue: String, preparedText: PreparedText) {
        self.rawValue = rawValue
        self.preparedText = preparedText
    }
}
