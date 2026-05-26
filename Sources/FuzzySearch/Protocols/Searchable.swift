import Foundation

/// This protocol must be implemented for searchable types.
public protocol Searchable {
    var searchDescriptor: SearchDescriptor { get }
}
