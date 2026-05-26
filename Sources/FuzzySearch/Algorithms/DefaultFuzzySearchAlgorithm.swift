import Foundation

public struct DefaultFuzzySearchAlgorithm: QueryPreparingSearchAlgorithm {
    public init() {}
    
    public func score(query: String, descriptor: SearchDescriptor) -> Double {
        score(preparedQuery: prepare(query: query), descriptor: descriptor)
    }
    
    public func prepare(query: String) -> PreparedSearchQuery {
        PreparedSearchQuery(rawValue: query, preparedText: PreparedText(query))
    }
    
    public func score(preparedQuery query: PreparedSearchQuery, descriptor: SearchDescriptor) -> Double {
        let preparedQuery = query.preparedText
        guard !preparedQuery.text.isEmpty else { return 0 }
        
        let properties = descriptor.properties.filter { $0.weight > 0 }
        guard !properties.isEmpty else { return 0 }
        
        let maximumWeight = properties.map(\.weight).max() ?? 1
        let combinedText = properties
            .map { $0.value.searchableString }
            .joined(separator: " ")
        
        var bestPropertyScore = 0.0
        var weightedScore = 0.0
        var totalWeight = 0.0
        
        for property in properties {
            let weight = property.weight
            let propertyScore = score(preparedQuery, against: PreparedText(property.value.searchableString))
            let relativeWeight = maximumWeight > 0 ? weight / maximumWeight : 1
            
            bestPropertyScore = max(bestPropertyScore, propertyScore * relativeWeight)
            weightedScore += propertyScore * weight
            totalWeight += weight
        }
        
        guard totalWeight > 0 else { return 0 }
        
        let averagePropertyScore = weightedScore / totalWeight
        let combinedScore = preparedQuery.tokens.count > 1
            ? score(preparedQuery, against: PreparedText(combinedText))
            : 0
        
        return min(1, max(0, bestPropertyScore, averagePropertyScore, combinedScore))
    }
    
    private func score(_ query: PreparedText, against candidate: PreparedText) -> Double {
        guard !candidate.text.isEmpty else { return 0 }
        if query.text == candidate.text { return 1 }
        
        let fullTextScore = scoreTerm(query.text, against: candidate.text)
        let tokenScore = averageBestTokenScore(query.tokens, against: candidate.tokens)
        let acronymScore = candidate.acronym.isEmpty ? 0 : scoreTerm(query.text, against: candidate.acronym) * 0.92
        
        return max(fullTextScore, tokenScore, acronymScore)
    }
    
    private func averageBestTokenScore(_ queryTokens: [Substring], against candidateTokens: [Substring]) -> Double {
        guard !queryTokens.isEmpty, !candidateTokens.isEmpty else { return 0 }
        
        var total = 0.0
        for queryToken in queryTokens {
            let best = candidateTokens.lazy
                .map { scoreTerm(queryToken, against: $0) }
                .max() ?? 0
            total += best
        }
        
        return total / Double(queryTokens.count)
    }
    
    private func scoreTerm<Q, C>(_ query: Q, against candidate: C) -> Double where Q: StringProtocol, C: StringProtocol {
        guard !query.isEmpty, !candidate.isEmpty else { return 0 }
        if query == candidate { return 1 }
        
        if candidate.hasPrefix(query) {
            let lengthRatio = Double(query.count) / Double(candidate.count)
            return 0.88 + (0.10 * lengthRatio)
        }
        
        if let range = candidate.range(of: query) {
            let offset = candidate.distance(from: candidate.startIndex, to: range.lowerBound)
            let lengthRatio = Double(query.count) / Double(candidate.count)
            let positionPenalty = min(0.12, Double(offset) * 0.015)
            return max(0.72, 0.86 + (0.08 * lengthRatio) - positionPenalty)
        }
        
        let subsequenceScore = orderedSubsequenceScore(query, candidate)
        if subsequenceScore >= 0.64 {
            return subsequenceScore
        }
        
        if let queryFirst = query.first, candidate.first != queryFirst, !candidate.contains(queryFirst) {
            return subsequenceScore
        }
        
        let editSimilarity = normalizedEditSimilarity(query, candidate)
        return max(subsequenceScore, editSimilarity)
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
    
    private func orderedSubsequenceScore<Q, C>(_ query: Q, _ candidate: C) -> Double where Q: StringProtocol, C: StringProtocol {
        var searchStart = candidate.startIndex
        var previousMatch: C.Index?
        var gaps = 0
        var firstOffset = 0
        
        for queryCharacter in query {
            guard let match = candidate[searchStart...].firstIndex(of: queryCharacter) else {
                return 0
            }
            
            if previousMatch == nil {
                firstOffset = candidate.distance(from: candidate.startIndex, to: match)
            } else if let previousMatch {
                gaps += candidate.distance(from: previousMatch, to: match) - 1
            }
            
            previousMatch = match
            searchStart = candidate.index(after: match)
        }
        
        let coverage = Double(query.count) / Double(candidate.count)
        let gapPenalty = min(0.24, Double(gaps) * 0.025)
        let startPenalty = min(0.12, Double(firstOffset) * 0.015)
        return max(0, 0.62 + (coverage * 0.18) - gapPenalty - startPenalty)
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

internal struct PreparedText: Sendable {
    let text: String
    let tokens: [Substring]
    let acronym: String
    
    init(_ rawValue: String) {
        text = PreparedText.normalizedText(rawValue)
        tokens = text.split(separator: " ")
        acronym = String(tokens.compactMap(\.first))
    }
    
    private static func normalizedText(_ rawValue: String) -> String {
        if rawValue.utf8.allSatisfy(\.isASCII) {
            return asciiNormalizedText(rawValue)
        }
        
        return rawValue
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
    
    private static func asciiNormalizedText(_ rawValue: String) -> String {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(rawValue.utf8.count)
        
        var previousWasSeparator = true
        for byte in rawValue.utf8 {
            switch byte {
            case 48...57, 97...122:
                bytes.append(byte)
                previousWasSeparator = false
            case 65...90:
                bytes.append(byte + 32)
                previousWasSeparator = false
            default:
                if !previousWasSeparator {
                    bytes.append(32)
                    previousWasSeparator = true
                }
            }
        }
        
        if bytes.last == 32 {
            bytes.removeLast()
        }
        
        return String(decoding: bytes, as: UTF8.self)
    }
}

private extension UInt8 {
    var isASCII: Bool {
        self < 128
    }
}
