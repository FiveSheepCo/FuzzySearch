#if canImport(SwiftUI)
import SwiftUI

@available(macOS 12, iOS 15, *)
extension LocalizedStringKey: SearchableValue {
    public var searchableString: String {
        let key = Mirror(reflecting: self).children.first(where: { $0.label == "key" })?.value as? String
        guard let key else { return "" }
        return String(localized: String.LocalizationValue(stringLiteral: key))
    }
}
#endif
