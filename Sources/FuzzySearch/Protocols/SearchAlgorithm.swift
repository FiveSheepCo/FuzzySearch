import Foundation

public protocol SearchAlgorithm: Sendable {
    associatedtype PreparedQuery: Sendable = String
    
    func prepare(query: String) -> PreparedQuery
    func shouldSearch(preparedQuery: PreparedQuery) -> Bool
    func evaluate(preparedQuery: PreparedQuery, descriptor: SearchDescriptor) -> SearchEvaluation
}

public extension SearchAlgorithm {
    func shouldSearch(preparedQuery: PreparedQuery) -> Bool {
        true
    }
    
    func evaluate(query: String, descriptor: SearchDescriptor) -> SearchEvaluation {
        let preparedQuery = prepare(query: query)
        guard shouldSearch(preparedQuery: preparedQuery) else { return SearchEvaluation(score: 0) }
        return evaluate(preparedQuery: preparedQuery, descriptor: descriptor)
    }
    
    func score(query: String, descriptor: SearchDescriptor) -> Double {
        evaluate(query: query, descriptor: descriptor).score
    }
    
    func score(preparedQuery: PreparedQuery, descriptor: SearchDescriptor) -> Double {
        evaluate(preparedQuery: preparedQuery, descriptor: descriptor).score
    }
}

public extension SearchAlgorithm where PreparedQuery == String {
    func prepare(query: String) -> String {
        query
    }
}
