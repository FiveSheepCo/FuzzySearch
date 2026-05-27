import Foundation

public struct SearchDescriptor: Sendable {
    public let fields: [SearchField]
    
    public init(fields: [SearchField]) {
        self.fields = fields
    }
    
    public init() {
        self.fields = []
    }
    
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
        let field = SearchField(value.searchableString, weight: weight)
        var fields = fields
        fields.append(field)
        return SearchDescriptor(fields: fields)
    }
    
    @discardableResult
    public func add<S>(_ values: S, weight: Double = 1) -> SearchDescriptor where S: Sequence, S.Element: SearchableValue {
        var fields = fields
        for value in values {
            fields.append(SearchField(value.searchableString, weight: weight))
        }
        return SearchDescriptor(fields: fields)
    }
    
    @discardableResult
    public func add<S>(_ searchable: S, weight: Double = 1) -> SearchDescriptor where S: Searchable {
        var fields = fields
        fields.append(contentsOf: searchable.searchDescriptor.fields.map { field in
            SearchField(field.value, weight: field.weight * weight)
        })
        return SearchDescriptor(fields: fields)
    }
    
    @discardableResult
    public func add<S>(_ searchables: S, weight: Double = 1) -> SearchDescriptor where S: Sequence, S.Element: Searchable {
        var fields = fields
        for searchable in searchables {
            fields.append(contentsOf: searchable.searchDescriptor.fields.map { field in
                SearchField(field.value, weight: field.weight * weight)
            })
        }
        return SearchDescriptor(fields: fields)
    }
}
