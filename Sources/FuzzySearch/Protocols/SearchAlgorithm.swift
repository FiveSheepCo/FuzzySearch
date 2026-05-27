import Foundation

public protocol SearchAlgorithm: Sendable {
    func score(query: String, descriptor: SearchDescriptor) -> Double
}

public protocol QueryPreparingSearchAlgorithm: SearchAlgorithm {
    func prepare(query: String) -> PreparedSearchQuery
    func score(preparedQuery: PreparedSearchQuery, descriptor: SearchDescriptor) -> Double
}

public protocol SearchEvaluatingAlgorithm: SearchAlgorithm {
    func evaluate(query: String, descriptor: SearchDescriptor) -> SearchEvaluation
}

public protocol QueryPreparingSearchEvaluatingAlgorithm: QueryPreparingSearchAlgorithm {
    func evaluate(preparedQuery: PreparedSearchQuery, descriptor: SearchDescriptor) -> SearchEvaluation
}
