import Foundation

public struct SearchDescriptor: Sendable {
    internal var properties: [SearchableProperty] = []
    
    public init() {}
    
    internal init(properties: [SearchableProperty]) {
        self.properties = properties
    }
    
    @discardableResult
    public func add<V>(_ value: V, weight: Double = 1) -> SearchDescriptor where V: SearchableValue {
        let property = SearchableProperty(value: AnySearchableValue(value), weight: weight)
        var properties = properties
        properties.append(property)
        return SearchDescriptor(properties: properties)
    }
}
