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
        let evaluation = evaluate(searchable.searchDescriptor, query: string, preparedQuery: nil)
        guard evaluation.score >= minimumScore else { return nil }
        return SearchResult(item: searchable, score: evaluation.score, matches: evaluation.matches)
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
                    let evaluation = evaluate(descriptor(item), query: string, preparedQuery: preparedQuery)
                    guard evaluation.score >= minimumScore else { return nil }
                    return SearchResult(
                        item: item,
                        score: evaluation.score,
                        index: offset,
                        matches: evaluation.matches
                    )
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
                        let evaluation: SearchEvaluation
                        if let preparedQuery, let preparingAlgorithm = algorithm as? any QueryPreparingSearchEvaluatingAlgorithm {
                            evaluation = preparingAlgorithm.evaluate(preparedQuery: preparedQuery, descriptor: itemDescriptor)
                        } else if let evaluatingAlgorithm = algorithm as? any SearchEvaluatingAlgorithm {
                            evaluation = evaluatingAlgorithm.evaluate(query: string, descriptor: itemDescriptor)
                        } else if let preparedQuery, let preparingAlgorithm = algorithm as? any QueryPreparingSearchAlgorithm {
                            evaluation = SearchEvaluation(
                                score: preparingAlgorithm.score(preparedQuery: preparedQuery, descriptor: itemDescriptor)
                            )
                        } else {
                            evaluation = SearchEvaluation(score: algorithm.score(query: string, descriptor: itemDescriptor))
                        }
                        guard evaluation.score >= minimumScore else { return nil }
                        return SearchResult(
                            item: item,
                            score: evaluation.score,
                            index: chunkLowerBound + offset,
                            matches: evaluation.matches
                        )
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
    
    private func evaluate(
        _ descriptor: SearchDescriptor,
        query: String,
        preparedQuery: PreparedSearchQuery?
    ) -> SearchEvaluation {
        if let preparingAlgorithm = algorithm as? any QueryPreparingSearchEvaluatingAlgorithm {
            let preparedQuery = preparedQuery ?? preparingAlgorithm.prepare(query: query)
            return preparingAlgorithm.evaluate(preparedQuery: preparedQuery, descriptor: descriptor)
        }
        if let evaluatingAlgorithm = algorithm as? any SearchEvaluatingAlgorithm {
            return evaluatingAlgorithm.evaluate(query: query, descriptor: descriptor)
        }
        if let preparingAlgorithm = algorithm as? any QueryPreparingSearchAlgorithm {
            let preparedQuery = preparedQuery ?? preparingAlgorithm.prepare(query: query)
            return SearchEvaluation(score: preparingAlgorithm.score(preparedQuery: preparedQuery, descriptor: descriptor))
        }
        return SearchEvaluation(score: algorithm.score(query: query, descriptor: descriptor))
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
