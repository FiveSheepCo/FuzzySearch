import Foundation

public struct Fuzzy: Sendable {
    private let algorithm: any SearchAlgorithm
    
    public init(algorithm: any SearchAlgorithm = DefaultFuzzySearchAlgorithm()) {
        self.algorithm = algorithm
    }
    
    public func search<S>(
        for string: String,
        in searchable: S,
        minimumScore: Double = 0.2
    ) async -> SearchResult<S>? where S: Searchable & Sendable {
        let score = score(searchable.searchDescriptor, query: string, preparedQuery: nil)
        guard score >= minimumScore else { return nil }
        return SearchResult(item: searchable, score: score)
    }
    
    public func search<C>(
        for string: String,
        in collection: C,
        limit: Int? = nil,
        minimumScore: Double = 0.2
    ) async -> [SearchResult<C.Element>] where C: Collection & Sendable, C.Element: Searchable & Sendable {
        await search(
            for: string,
            in: collection,
            limit: limit,
            minimumScore: minimumScore,
            descriptor: \.searchDescriptor
        )
    }
    
    public func search<C>(
        for string: String,
        in collection: C,
        limit: Int? = nil,
        minimumScore: Double = 0.2
    ) async -> [SearchResult<C.Element>] where C: Collection & Sendable, C.Element: SearchableValue & Sendable {
        await search(
            for: string,
            in: collection,
            limit: limit,
            minimumScore: minimumScore,
            descriptor: { SearchDescriptor($0) }
        )
    }
    
    private func search<C>(
        for string: String,
        in collection: C,
        limit: Int?,
        minimumScore: Double,
        descriptor: @escaping @Sendable (C.Element) -> SearchDescriptor
    ) async -> [SearchResult<C.Element>] where C: Collection & Sendable, C.Element: Sendable {
        guard !string.isEmpty else { return [] }
        guard !collection.isEmpty else { return [] }
        
        let preparedQuery = (algorithm as? any QueryPreparingSearchAlgorithm)?.prepare(query: string)
        if preparedQuery?.isEmpty == true { return [] }
        
        if collection.count < 256 {
            return rankedResults(
                collection.enumerated().lazy.compactMap { offset, item in
                    let score = score(descriptor(item), query: string, preparedQuery: preparedQuery)
                    guard score >= minimumScore else { return nil }
                    return SearchResult(item: item, score: score, index: offset)
                },
                limit: limit
            )
        }
        
        let items = Array(collection)
        let chunkSize = max(64, min(512, items.count / max(1, ProcessInfo.processInfo.activeProcessorCount)))
        let resultBatches = await withTaskGroup(of: [SearchResult<C.Element>].self) { group in
            var lowerBound = 0
            
            while lowerBound < items.count {
                let upperBound = min(items.count, lowerBound + chunkSize)
                let chunk = Array(items[lowerBound..<upperBound])
                let chunkLowerBound = lowerBound
                let algorithm = self.algorithm
                
                group.addTask {
                    chunk.enumerated().compactMap { offset, item in
                        let itemDescriptor = descriptor(item)
                        let score: Double
                        if let preparedQuery, let preparingAlgorithm = algorithm as? any QueryPreparingSearchAlgorithm {
                            score = preparingAlgorithm.score(preparedQuery: preparedQuery, descriptor: itemDescriptor)
                        } else {
                            score = algorithm.score(query: string, descriptor: itemDescriptor)
                        }
                        guard score >= minimumScore else { return nil }
                        return SearchResult(item: item, score: score, index: chunkLowerBound + offset)
                    }
                }
                
                lowerBound = upperBound
            }
            
            var batches: [[SearchResult<C.Element>]] = []
            for await batch in group {
                batches.append(batch)
            }
            return batches
        }
        
        return rankedResults(resultBatches.flatMap(\.self), limit: limit)
    }
    
    private func score(
        _ descriptor: SearchDescriptor,
        query: String,
        preparedQuery: PreparedSearchQuery?
    ) -> Double {
        if let preparedQuery, let preparingAlgorithm = algorithm as? any QueryPreparingSearchAlgorithm {
            return preparingAlgorithm.score(preparedQuery: preparedQuery, descriptor: descriptor)
        }
        return algorithm.score(query: query, descriptor: descriptor)
    }
    
    private func rankedResults<Item, S>(
        _ results: S,
        limit: Int?
    ) -> [SearchResult<Item>] where S: Sequence, S.Element == SearchResult<Item> {
        let sortedResults = results.sorted { lhs, rhs in
            if lhs.score == rhs.score { return false }
            return lhs.score > rhs.score
        }
        
        guard let limit else { return sortedResults }
        return Array(sortedResults.prefix(max(0, limit)))
    }
}
