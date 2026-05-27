import Foundation

public struct AnySearchAlgorithm: SearchAlgorithm {
    public struct PreparedQuery: Sendable {
        fileprivate let storage: any Sendable
    }
    
    private let prepareQuery: @Sendable (String) -> PreparedQuery
    private let shouldRunSearch: @Sendable (PreparedQuery) -> Bool
    private let evaluateQuery: @Sendable (PreparedQuery, SearchDescriptor) -> SearchEvaluation
    
    public init<Algorithm>(_ algorithm: Algorithm) where Algorithm: SearchAlgorithm {
        prepareQuery = { query in
            PreparedQuery(storage: algorithm.prepare(query: query))
        }
        shouldRunSearch = { preparedQuery in
            guard let preparedQuery = preparedQuery.storage as? Algorithm.PreparedQuery else { return false }
            return algorithm.shouldSearch(preparedQuery: preparedQuery)
        }
        evaluateQuery = { preparedQuery, descriptor in
            guard let preparedQuery = preparedQuery.storage as? Algorithm.PreparedQuery else {
                return SearchEvaluation(score: 0)
            }
            return algorithm.evaluate(preparedQuery: preparedQuery, descriptor: descriptor)
        }
    }
    
    public func prepare(query: String) -> PreparedQuery {
        prepareQuery(query)
    }
    
    public func shouldSearch(preparedQuery: PreparedQuery) -> Bool {
        shouldRunSearch(preparedQuery)
    }
    
    public func evaluate(preparedQuery: PreparedQuery, descriptor: SearchDescriptor) -> SearchEvaluation {
        evaluateQuery(preparedQuery, descriptor)
    }
}
