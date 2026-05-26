import Foundation

@available(macOS 13, iOS 16, *)
extension LocalizedStringResource: SearchableValue {
    public var searchableString: String { String(localized: self) }
}
