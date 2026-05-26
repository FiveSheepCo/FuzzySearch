import Foundation
import Fuse
import FuzzySearch
import Ifrit

struct Contact: Sendable {
    let id: String
    let firstName: String
    let lastName: String
    let city: String
}

extension Contact: Ifrit::Searchable {
    var props: [FuseProp] {
        [
            FuseProp(firstName),
            FuseProp(lastName),
            FuseProp(city, weight: 0.5),
        ]
    }
}

extension Contact: FuzzySearch::Searchable {
    var searchDescriptor: SearchDescriptor {
        SearchDescriptor()
            .add(firstName)
            .add(lastName)
            .add(city, weight: 0.5)
    }
}

struct QueryCase {
    let query: String
    let relevance: [String: Int]
}

struct EngineReport {
    let name: String
    let topOneAccuracy: Double
    let meanReciprocalRank: Double
    let normalizedDiscountedCumulativeGain: Double
    let misses: [QueryMiss]
}

struct QueryMiss {
    let query: String
    let expected: [String]
    let actualTopFive: [String]
}

@main
struct QualityEval {
    static func main() async throws {
        let contacts = sampleContacts
        let queryCases = sampleQueryCases
        
        let fuzzyRankings = await rankingsForFuzzy(contacts: contacts, queryCases: queryCases)
        let fuseRankings = try rankingsForFuse(contacts: contacts, queryCases: queryCases)
        let ifritRankings = rankingsForIfrit(contacts: contacts, queryCases: queryCases)
        
        let reports = [
            evaluate(name: "FuzzySearch", rankings: fuzzyRankings, queryCases: queryCases),
            evaluate(name: "Fuse", rankings: fuseRankings, queryCases: queryCases),
            evaluate(name: "Ifrit", rankings: ifritRankings, queryCases: queryCases),
        ]
        
        printReport(reports)
    }
    
    private static func rankingsForFuzzy(
        contacts: [Contact],
        queryCases: [QueryCase]
    ) async -> [[String]] {
        let fuzzy = Fuzzy()
        
        var rankings: [[String]] = []
        rankings.reserveCapacity(queryCases.count)
        
        for queryCase in queryCases {
            let results = await fuzzy.search(for: queryCase.query, in: contacts, minimumScore: 0)
            rankings.append(results.map(\.item.id))
        }
        
        return rankings
    }
    
    private static func rankingsForFuse(
        contacts: [Contact],
        queryCases: [QueryCase]
    ) throws -> [[String]] {
        let options = try Fuse::FuseOptions<Contact>(
            includeMatches: true,
            includeScore: true,
            keys: [
                try Fuse::FuseKey<Contact>("firstName", keyPath: \Contact.firstName),
                try Fuse::FuseKey<Contact>("lastName", keyPath: \Contact.lastName),
                try Fuse::FuseKey<Contact>("city", keyPath: \Contact.city, weight: 0.5),
            ]
        )
        let fuse = try Fuse::Fuse.Search<Contact>(contacts, options: options)
        
        return queryCases.map { queryCase in
            fuse.search(queryCase.query).map(\.item.id)
        }
    }
    
    private static func rankingsForIfrit(
        contacts: [Contact],
        queryCases: [QueryCase]
    ) -> [[String]] {
        let fuse = Ifrit::Fuse()
        
        return queryCases.map { queryCase in
            fuse.searchSync(queryCase.query, in: contacts, by: \.props)
                .map { contacts[$0.index].id }
        }
    }
    
    private static func evaluate(
        name: String,
        rankings: [[String]],
        queryCases: [QueryCase]
    ) -> EngineReport {
        var topOneHits = 0
        var reciprocalRankTotal = 0.0
        var ndcgTotal = 0.0
        var misses: [QueryMiss] = []
        
        for (ranking, queryCase) in zip(rankings, queryCases) {
            let bestRelevance = queryCase.relevance.values.max() ?? 0
            let topID = ranking.first
            
            if let topID, queryCase.relevance[topID] == bestRelevance {
                topOneHits += 1
            } else {
                let expected = queryCase.relevance
                    .filter { $0.value == bestRelevance }
                    .map(\.key)
                    .sorted()
                
                misses.append(QueryMiss(
                    query: queryCase.query,
                    expected: expected,
                    actualTopFive: Array(ranking.prefix(5))
                ))
            }
            
            if let relevantIndex = ranking.firstIndex(where: { (queryCase.relevance[$0] ?? 0) > 0 }) {
                reciprocalRankTotal += 1.0 / Double(relevantIndex + 1)
            }
            
            ndcgTotal += ndcg(at: 5, ranking: ranking, relevance: queryCase.relevance)
        }
        
        let count = Double(queryCases.count)
        return EngineReport(
            name: name,
            topOneAccuracy: Double(topOneHits) / count,
            meanReciprocalRank: reciprocalRankTotal / count,
            normalizedDiscountedCumulativeGain: ndcgTotal / count,
            misses: misses
        )
    }
    
    private static func ndcg(
        at limit: Int,
        ranking: [String],
        relevance: [String: Int]
    ) -> Double {
        let actual = discountedCumulativeGain(
            relevanceScores: ranking.prefix(limit).map { relevance[$0] ?? 0 }
        )
        
        let ideal = discountedCumulativeGain(
            relevanceScores: relevance.values.sorted(by: >).prefix(limit)
        )
        
        guard ideal > 0 else { return 0 }
        return actual / ideal
    }
    
    private static func discountedCumulativeGain<S>(
        relevanceScores: S
    ) -> Double where S: Sequence, S.Element == Int {
        relevanceScores.enumerated().reduce(0.0) { total, element in
            let relevance = element.element
            guard relevance > 0 else { return total }
            
            let rank = Double(element.offset + 2)
            let gain = pow(2.0, Double(relevance)) - 1.0
            return total + gain / log2(rank)
        }
    }
    
    private static func printReport(_ reports: [EngineReport]) {
        print("Quality evaluation")
        print("==================")
        print("Metrics: Top1, MRR, nDCG@5. Higher is better.\n")
        
        for report in reports {
            print(report.name)
            print("- Top1:  \(format(report.topOneAccuracy))")
            print("- MRR:   \(format(report.meanReciprocalRank))")
            print("- nDCG:  \(format(report.normalizedDiscountedCumulativeGain))")
            
            if report.misses.isEmpty {
                print("- Misses: none")
            } else {
                print("- Misses:")
                for miss in report.misses {
                    print("  query=\(miss.query.debugDescription) expected=\(miss.expected) actualTop5=\(miss.actualTopFive)")
                }
            }
            
            print("")
        }
    }
    
    private static func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}

private let sampleContacts: [Contact] = [
    Contact(id: "sarah-connor", firstName: "Sarah", lastName: "Connor", city: "Los Angeles"),
    Contact(id: "sara-king", firstName: "Sara", lastName: "King", city: "London"),
    Contact(id: "john-connor", firstName: "John", lastName: "Connor", city: "Mexico City"),
    Contact(id: "jonathan-kent", firstName: "Jonathan", lastName: "Kent", city: "Smallville"),
    Contact(id: "thomas-shelby", firstName: "Thomas", lastName: "Shelby", city: "Birmingham"),
    Contact(id: "arthur-shelby", firstName: "Arthur", lastName: "Shelby", city: "Birmingham"),
    Contact(id: "polly-gray", firstName: "Polly", lastName: "Gray", city: "Birmingham"),
    Contact(id: "michael-gray", firstName: "Michael", lastName: "Gray", city: "Birmingham"),
    Contact(id: "alice-johnson", firstName: "Alice", lastName: "Johnson", city: "Seattle"),
    Contact(id: "alicia-jones", firstName: "Alicia", lastName: "Jones", city: "Portland"),
    Contact(id: "grace-taylor", firstName: "Grace", lastName: "Taylor", city: "Austin"),
    Contact(id: "frank-wilson", firstName: "Frank", lastName: "Wilson", city: "Chicago"),
    Contact(id: "eve-miller", firstName: "Eve", lastName: "Miller", city: "Boston"),
    Contact(id: "hank-anderson", firstName: "Hank", lastName: "Anderson", city: "Detroit"),
    Contact(id: "soeren-kierkegaard", firstName: "Søren", lastName: "Kierkegaard", city: "Copenhagen"),
    Contact(id: "zoe-salazar", firstName: "Zoë", lastName: "Salazar", city: "Bangkok"),
]

private let sampleQueryCases: [QueryCase] = [
    QueryCase(query: "Sarah", relevance: ["sarah-connor": 3, "sara-king": 2]),
    QueryCase(query: "Sara", relevance: ["sara-king": 3, "sarah-connor": 2]),
    QueryCase(query: "Saren", relevance: ["sarah-connor": 3, "sara-king": 1]),
    QueryCase(query: "Sarah Connor", relevance: ["sarah-connor": 3, "john-connor": 1]),
    QueryCase(query: "Connor", relevance: ["sarah-connor": 3, "john-connor": 3]),
    QueryCase(query: "Tom Shelby", relevance: ["thomas-shelby": 3, "arthur-shelby": 1]),
    QueryCase(query: "Shelby", relevance: ["thomas-shelby": 3, "arthur-shelby": 3]),
    QueryCase(query: "Arthur Shelbi", relevance: ["arthur-shelby": 3, "thomas-shelby": 1]),
    QueryCase(query: "Pol Gray", relevance: ["polly-gray": 3, "michael-gray": 1]),
    QueryCase(query: "Alice John", relevance: ["alice-johnson": 3, "alicia-jones": 1]),
    QueryCase(query: "Alicia", relevance: ["alicia-jones": 3, "alice-johnson": 2]),
    QueryCase(query: "Birmingam", relevance: ["thomas-shelby": 2, "arthur-shelby": 2, "polly-gray": 2, "michael-gray": 2]),
    QueryCase(query: "Soren", relevance: ["soeren-kierkegaard": 3]),
    QueryCase(query: "Zoe", relevance: ["zoe-salazar": 3]),
    QueryCase(query: "Los Angles", relevance: ["sarah-connor": 2]),
]
