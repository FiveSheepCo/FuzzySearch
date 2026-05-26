import Foundation

/// This protocol must be implemented for searchable values.
public protocol SearchableValue {
    var searchableString: String { get }
}
