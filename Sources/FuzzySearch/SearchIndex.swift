import Foundation

public actor SearchIndex<Item, Algorithm> where Item: Searchable & Sendable, Algorithm: SearchAlgorithm {
    private var items: [Item]
    private let fuzzy: Fuzzy<Algorithm>
    
    public init(
        items: [Item] = [],
        algorithm: Algorithm
    ) {
        self.items = items
        self.fuzzy = Fuzzy(algorithm: algorithm)
    }
    
    public func search(
        for string: String,
        limit: Int? = nil,
        minimumScore: Double = 0.2
    ) async -> [SearchResult<Item>] {
        await fuzzy.search(for: string, in: items, limit: limit, minimumScore: minimumScore)
    }
    
    public func replaceItems(_ items: [Item]) {
        self.items = items
    }
    
    public func append(_ item: Item) {
        items.append(item)
    }
    
    public func append<S>(contentsOf newItems: S) where S: Sequence, S.Element == Item {
        items.append(contentsOf: newItems)
    }
    
    public func removeAll(keepingCapacity keepCapacity: Bool = false) {
        items.removeAll(keepingCapacity: keepCapacity)
    }
}

public extension SearchIndex where Algorithm == DefaultFuzzySearchAlgorithm {
    init(items: [Item] = []) {
        self.init(items: items, algorithm: DefaultFuzzySearchAlgorithm())
    }
}
