import Foundation

public struct DefaultFuzzySearchPreparedQuery: Sendable {
    public let rawValue: String
    internal let preparedText: PreparedText
    
    public var isEmpty: Bool {
        preparedText.text.isEmpty
    }
    
    public init(_ rawValue: String) {
        self.rawValue = rawValue
        self.preparedText = PreparedText(rawValue)
    }
    
    internal init(rawValue: String, preparedText: PreparedText) {
        self.rawValue = rawValue
        self.preparedText = preparedText
    }
}

public struct DefaultFuzzySearchAlgorithm: SearchAlgorithm {
    public typealias PreparedQuery = DefaultFuzzySearchPreparedQuery
    
    public init() {}
    
    public func prepare(query: String) -> DefaultFuzzySearchPreparedQuery {
        DefaultFuzzySearchPreparedQuery(rawValue: query, preparedText: PreparedText(query))
    }
    
    public func shouldSearch(preparedQuery: DefaultFuzzySearchPreparedQuery) -> Bool {
        !preparedQuery.isEmpty
    }
    
    public func evaluate(preparedQuery query: DefaultFuzzySearchPreparedQuery, descriptor: SearchDescriptor) -> SearchEvaluation {
        let preparedQuery = query.preparedText
        guard !preparedQuery.text.isEmpty else { return SearchEvaluation(score: 0) }
        
        let fields = descriptor.fields.filter { $0.weight > 0 }
        guard !fields.isEmpty else { return SearchEvaluation(score: 0) }
        
        let maximumWeight = fields.map(\.weight).max() ?? 1
        let combinedText = fields
            .map(\.value)
            .joined(separator: " ")
        
        var bestPropertyScore = 0.0
        var weightedScore = 0.0
        var totalWeight = 0.0
        var matches: [SearchMatch] = []
        
        for field in fields {
            let weight = field.weight
            let fieldEvaluation = evaluate(preparedQuery, against: PreparedText(field.value))
            let fieldScore = fieldEvaluation.score
            let relativeWeight = maximumWeight > 0 ? weight / maximumWeight : 1
            
            bestPropertyScore = max(bestPropertyScore, fieldScore * relativeWeight)
            weightedScore += fieldScore * weight
            totalWeight += weight
            matches.append(contentsOf: fieldEvaluation.matches)
        }
        
        guard totalWeight > 0 else { return SearchEvaluation(score: 0) }
        
        let averagePropertyScore = weightedScore / totalWeight
        let combinedScore = preparedQuery.tokens.count > 1
            ? score(preparedQuery, against: PreparedText(combinedText))
            : 0
        
        let score = min(1, max(0, bestPropertyScore, averagePropertyScore, combinedScore))
        return SearchEvaluation(score: score, matches: matches.deduplicated())
    }
    
    private func score(_ query: PreparedText, against candidate: PreparedText) -> Double {
        evaluate(query, against: candidate).score
    }
    
    private func evaluate(_ query: PreparedText, against candidate: PreparedText) -> SearchEvaluation {
        guard !candidate.text.isEmpty else { return SearchEvaluation(score: 0) }
        let queryText = query.text[query.text.startIndex..<query.text.endIndex]
        let candidateText = candidate.text[candidate.text.startIndex..<candidate.text.endIndex]
        if query.text == candidate.text {
            return SearchEvaluation(
                score: 1,
                matches: candidate.match(for: candidateText.startIndex..<candidateText.endIndex).map { [$0] } ?? []
            )
        }
        
        let fullTextEvaluation = evaluateTerm(queryText, against: candidateText)
        let tokenEvaluation = averageBestTokenEvaluation(query.tokens, against: candidate.tokens, in: candidate)
        let acronymScore = candidate.acronym.isEmpty ? 0 : scoreTerm(queryText, against: candidate.acronym[...]) * 0.92
        
        let score = max(fullTextEvaluation.score, tokenEvaluation.score, acronymScore)
        if tokenEvaluation.score >= fullTextEvaluation.score {
            return SearchEvaluation(score: score, matches: tokenEvaluation.matches)
        }
        return SearchEvaluation(
            score: score,
            matches: fullTextEvaluation.range.flatMap { candidate.match(for: $0) }.map { [$0] } ?? []
        )
    }
    
    private func averageBestTokenScore(_ queryTokens: [Substring], against candidateTokens: [Substring]) -> Double {
        averageBestTokenEvaluation(queryTokens, against: candidateTokens, in: nil).score
    }
    
    private func averageBestTokenEvaluation(
        _ queryTokens: [Substring],
        against candidateTokens: [Substring],
        in candidate: PreparedText?
    ) -> SearchEvaluation {
        guard !queryTokens.isEmpty, !candidateTokens.isEmpty else { return SearchEvaluation(score: 0) }
        
        var total = 0.0
        var matches: [SearchMatch] = []
        for queryToken in queryTokens {
            let best = candidateTokens.lazy
                .map { token -> TermEvaluation in
                    evaluateTerm(queryToken, against: token)
                }
                .max { $0.score < $1.score } ?? TermEvaluation(score: 0)
            total += best.score
            if let candidate, let range = best.range, let match = candidate.match(for: range) {
                matches.append(match)
            }
        }
        
        return SearchEvaluation(score: total / Double(queryTokens.count), matches: matches.deduplicated())
    }
    
    private func scoreTerm(_ query: Substring, against candidate: Substring) -> Double {
        evaluateTerm(query, against: candidate).score
    }
    
    private func evaluateTerm(_ query: Substring, against candidate: Substring) -> TermEvaluation {
        guard !query.isEmpty, !candidate.isEmpty else { return TermEvaluation(score: 0) }
        if query == candidate { return TermEvaluation(score: 1, range: candidate.startIndex..<candidate.endIndex) }
        
        if candidate.hasPrefix(query) {
            let lengthRatio = Double(query.count) / Double(candidate.count)
            let endIndex = candidate.index(candidate.startIndex, offsetBy: query.count)
            return TermEvaluation(score: 0.88 + (0.10 * lengthRatio), range: candidate.startIndex..<endIndex)
        }
        
        if let range = candidate.range(of: query) {
            let offset = candidate.distance(from: candidate.startIndex, to: range.lowerBound)
            let lengthRatio = Double(query.count) / Double(candidate.count)
            let positionPenalty = min(0.12, Double(offset) * 0.015)
            return TermEvaluation(score: max(0.72, 0.86 + (0.08 * lengthRatio) - positionPenalty), range: range)
        }
        
        let subsequenceEvaluation = orderedSubsequenceEvaluation(query, candidate)
        if subsequenceEvaluation.score >= 0.64 {
            return TermEvaluation(score: subsequenceEvaluation.score)
        }
        
        if let queryFirst = query.first, candidate.first != queryFirst, !candidate.contains(queryFirst) {
            return TermEvaluation(score: subsequenceEvaluation.score)
        }
        
        let editSimilarity = normalizedEditSimilarity(query, candidate)
        if editSimilarity > subsequenceEvaluation.score {
            return TermEvaluation(score: editSimilarity)
        }
        return TermEvaluation(score: subsequenceEvaluation.score)
    }
    
    private func normalizedEditSimilarity<Q, C>(_ query: Q, _ candidate: C) -> Double where Q: StringProtocol, C: StringProtocol {
        let queryLength = query.count
        let candidateLength = candidate.count
        guard queryLength > 0, candidateLength > 0 else { return 0 }
        
        let maxDistance = max(2, Int(ceil(Double(max(queryLength, candidateLength)) * 0.42)))
        guard abs(queryLength - candidateLength) <= maxDistance else { return 0 }
        
        guard let distance = boundedLevenshteinDistance(query, candidate, maximumDistance: maxDistance) else {
            return 0
        }
        
        let ratio = 1 - (Double(distance) / Double(max(queryLength, candidateLength)))
        return max(0, ratio * 0.84)
    }
    
    private func orderedSubsequenceScore(_ query: Substring, _ candidate: Substring) -> Double {
        orderedSubsequenceEvaluation(query, candidate).score
    }
    
    private func orderedSubsequenceEvaluation(_ query: Substring, _ candidate: Substring) -> TermEvaluation {
        var searchStart = candidate.startIndex
        var previousMatch: String.Index?
        var gaps = 0
        var firstOffset = 0
        var firstMatch: String.Index?
        
        for queryCharacter in query {
            guard let match = candidate[searchStart...].firstIndex(of: queryCharacter) else {
                return TermEvaluation(score: 0)
            }
            
            if previousMatch == nil {
                firstOffset = candidate.distance(from: candidate.startIndex, to: match)
                firstMatch = match
            } else if let previousMatch {
                gaps += candidate.distance(from: previousMatch, to: match) - 1
            }
            
            previousMatch = match
            searchStart = candidate.index(after: match)
        }
        
        let coverage = Double(query.count) / Double(candidate.count)
        let gapPenalty = min(0.24, Double(gaps) * 0.025)
        let startPenalty = min(0.12, Double(firstOffset) * 0.015)
        let score = max(0, 0.62 + (coverage * 0.18) - gapPenalty - startPenalty)
        let range = firstMatch.flatMap { firstMatch -> Range<String.Index>? in
            guard let previousMatch else { return nil }
            return firstMatch..<candidate.index(after: previousMatch)
        }
        return TermEvaluation(score: score, range: range)
    }
    
    private func boundedLevenshteinDistance<L, R>(
        _ lhs: L,
        _ rhs: R,
        maximumDistance: Int
    ) -> Int? where L: StringProtocol, R: StringProtocol {
        let lhsCharacters = Array(lhs)
        let rhsCharacters = Array(rhs)
        
        if lhsCharacters.isEmpty { return rhsCharacters.count <= maximumDistance ? rhsCharacters.count : nil }
        if rhsCharacters.isEmpty { return lhsCharacters.count <= maximumDistance ? lhsCharacters.count : nil }
        
        var previous = Array(0...rhsCharacters.count)
        var current = Array(repeating: 0, count: rhsCharacters.count + 1)
        
        for lhsIndex in 1...lhsCharacters.count {
            current[0] = lhsIndex
            var rowMinimum = current[0]
            
            for rhsIndex in 1...rhsCharacters.count {
                let substitutionCost = lhsCharacters[lhsIndex - 1] == rhsCharacters[rhsIndex - 1] ? 0 : 1
                current[rhsIndex] = min(
                    previous[rhsIndex] + 1,
                    current[rhsIndex - 1] + 1,
                    previous[rhsIndex - 1] + substitutionCost
                )
                rowMinimum = min(rowMinimum, current[rhsIndex])
            }
            
            guard rowMinimum <= maximumDistance else { return nil }
            swap(&previous, &current)
        }
        
        let distance = previous[rhsCharacters.count]
        return distance <= maximumDistance ? distance : nil
    }
}

private struct TermEvaluation {
    let score: Double
    let range: Range<String.Index>?
    
    init(score: Double, range: Range<String.Index>? = nil) {
        self.score = score
        self.range = range
    }
}

internal struct PreparedText: Sendable {
    let source: String
    let text: String
    let tokens: [Substring]
    let acronym: String
    let sourceRanges: [ClosedRange<Int>]
    
    init(_ rawValue: String) {
        source = rawValue
        let normalized = PreparedText.normalizedText(rawValue)
        text = normalized.text
        sourceRanges = normalized.sourceRanges
        tokens = text.split(separator: " ")
        acronym = String(tokens.compactMap(\.first))
    }
    
    func match(for normalizedRange: Range<String.Index>) -> SearchMatch? {
        let lowerOffset = text.distance(from: text.startIndex, to: normalizedRange.lowerBound)
        let upperOffset = text.distance(from: text.startIndex, to: normalizedRange.upperBound) - 1
        guard lowerOffset >= 0,
              upperOffset >= lowerOffset,
              lowerOffset < sourceRanges.count,
              upperOffset < sourceRanges.count else {
            return nil
        }
        
        let sourceRange = sourceRanges[lowerOffset].lowerBound...sourceRanges[upperOffset].upperBound
        return SearchMatch(value: source, range: sourceRange, text: source.substring(in: sourceRange))
    }
    
    private static func normalizedText(_ rawValue: String) -> (text: String, sourceRanges: [ClosedRange<Int>]) {
        if rawValue.utf8.allSatisfy({ $0 < 128 }) {
            return asciiNormalizedText(rawValue)
        }
        
        var text = ""
        var sourceRanges: [ClosedRange<Int>] = []
        var previousWasSeparator = true
        
        for (offset, character) in rawValue.enumerated() {
            let folded = String(character)
                .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            let normalizedScalars = folded.unicodeScalars.filter {
                CharacterSet.alphanumerics.contains($0)
            }
            
            if normalizedScalars.isEmpty {
                if !previousWasSeparator {
                    text.append(" ")
                    sourceRanges.append(offset...offset)
                    previousWasSeparator = true
                }
                continue
            }
            
            for scalar in normalizedScalars {
                text.unicodeScalars.append(scalar)
                sourceRanges.append(offset...offset)
            }
            previousWasSeparator = false
        }
        
        if text.last == " " {
            text.removeLast()
            sourceRanges.removeLast()
        }
        
        return (text, sourceRanges)
    }
    
    private static func asciiNormalizedText(_ rawValue: String) -> (text: String, sourceRanges: [ClosedRange<Int>]) {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(rawValue.utf8.count)
        var sourceRanges: [ClosedRange<Int>] = []
        
        var previousWasSeparator = true
        for (offset, byte) in rawValue.utf8.enumerated() {
            switch byte {
            case 48...57, 97...122:
                bytes.append(byte)
                sourceRanges.append(offset...offset)
                previousWasSeparator = false
            case 65...90:
                bytes.append(byte + 32)
                sourceRanges.append(offset...offset)
                previousWasSeparator = false
            default:
                if !previousWasSeparator {
                    bytes.append(32)
                    sourceRanges.append(offset...offset)
                    previousWasSeparator = true
                }
            }
        }
        
        if bytes.last == 32 {
            bytes.removeLast()
            sourceRanges.removeLast()
        }
        
        return (String(decoding: bytes, as: UTF8.self), sourceRanges)
    }
}

private extension Array where Element == SearchMatch {
    func deduplicated() -> [SearchMatch] {
        var matches: [SearchMatch] = []
        for match in self where !matches.contains(where: {
            $0.value == match.value && $0.range == match.range
        }) {
            matches.append(match)
        }
        return matches
    }
}

private extension String {
    func substring(in range: ClosedRange<Int>) -> String {
        let lowerBound = index(startIndex, offsetBy: range.lowerBound)
        let upperBound = index(startIndex, offsetBy: range.upperBound)
        return String(self[lowerBound...upperBound])
    }
}
