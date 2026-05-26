import Foundation

internal struct AnySearchableValue: SearchableValue, @unchecked Sendable {
    private let value: any SearchableValue
    
    init(_ value: any SearchableValue) {
        self.value = value
    }
    
    var searchableString: String {
        value.searchableString
    }
}
