import Foundation

public struct SearchDescriptor: Sendable {
    internal var properties: [SearchableProperty] = []
    
    internal init(properties: [SearchableProperty]) {
        self.properties = properties
    }
    
    public init() {}
    
    public init<V>(_ value: V) where V: SearchableValue {
        self = SearchDescriptor().add(value)
    }
    
    public init<S>(_ searchable: S) where S: Searchable {
        self = SearchDescriptor().add(searchable)
    }
    
    public init<S>(_ searchables: S) where S: Sequence, S.Element: Searchable {
        self = SearchDescriptor().add(searchables)
    }
    
    public init<S>(_ values: S) where S: Sequence, S.Element: SearchableValue {
        self = SearchDescriptor().add(values)
    }
    
    @discardableResult
    public func add<V>(_ value: V, weight: Double = 1) -> SearchDescriptor where V: SearchableValue {
        let property = SearchableProperty(value: AnySearchableValue(value), weight: weight)
        var properties = properties
        properties.append(property)
        return SearchDescriptor(properties: properties)
    }
    
    @discardableResult
    public func add<S>(_ values: S, weight: Double = 1) -> SearchDescriptor where S: Sequence, S.Element: SearchableValue {
        var properties = properties
        for value in values {
            properties.append(SearchableProperty(value: AnySearchableValue(value), weight: weight))
        }
        return SearchDescriptor(properties: properties)
    }
    
    @discardableResult
    public func add<S>(_ searchable: S, weight: Double = 1) -> SearchDescriptor where S: Searchable {
        var properties = properties
        properties.append(contentsOf: searchable.searchDescriptor.properties.map { property in
            SearchableProperty(value: property.value, weight: property.weight * weight)
        })
        return SearchDescriptor(properties: properties)
    }
    
    @discardableResult
    public func add<S>(_ searchables: S, weight: Double = 1) -> SearchDescriptor where S: Sequence, S.Element: Searchable {
        var properties = properties
        for searchable in searchables {
            properties.append(contentsOf: searchable.searchDescriptor.properties.map { property in
                SearchableProperty(value: property.value, weight: property.weight * weight)
            })
        }
        return SearchDescriptor(properties: properties)
    }
}
