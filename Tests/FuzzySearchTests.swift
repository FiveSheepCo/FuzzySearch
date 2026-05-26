import Testing
@testable import FuzzySearch

private struct User: Searchable, Sendable, Equatable {
    let firstName: String
    let lastName: String
    let address: String
    
    var searchDescriptor: SearchDescriptor {
        SearchDescriptor()
            .add(firstName)
            .add(lastName)
            .add(address, weight: 0.5)
    }
}

private struct Address: Searchable, Sendable, Equatable {
    let city: String
    let country: String
    
    var searchDescriptor: SearchDescriptor {
        SearchDescriptor()
            .add(city)
            .add(country, weight: 0.5)
    }
}

private struct NestedUser: Searchable, Sendable, Equatable {
    let firstName: String
    let lastName: String
    let address: Address
    
    var searchDescriptor: SearchDescriptor {
        SearchDescriptor()
            .add(firstName)
            .add(lastName)
            .add(address, weight: 0.5)
    }
}

@Test func singleSearchReturnsWeightedScore() async throws {
    let user = User(firstName: "Sarah", lastName: "Connor", address: "Los Angeles")
    
    let result = await Fuzzy().search(for: "Sarah", in: user)
    
    #expect(result?.item == user)
    #expect((result?.score ?? 0) > 0.3)
}

@Test func collectionSearchRanksMostRelevantItemsFirst() async throws {
    let users = [
        User(firstName: "Sam", lastName: "Carter", address: "Sarah Street"),
        User(firstName: "Sarah", lastName: "Connor", address: "Los Angeles"),
        User(firstName: "Zoe", lastName: "Salazar", address: "Bangkok"),
    ]
    
    let results = await Fuzzy().search(for: "Sarah", in: users)
    
    #expect(results.map(\.item.firstName).prefix(2) == ["Sarah", "Sam"])
    #expect(results.map(\.index).prefix(2) == [1, 0])
    #expect(results[0].score > results[1].score)
}

@Test func collectionSearchIncludesSourceIndicesForLargeCollections() async throws {
    var users = (0..<300).map {
        User(firstName: "User\($0)", lastName: "Example", address: "Bangkok")
    }
    users[275] = User(firstName: "Sarah", lastName: "Connor", address: "Los Angeles")
    
    let results = await Fuzzy().search(for: "Sarah", in: users)
    
    #expect(results.first?.item.firstName == "Sarah")
    #expect(results.first?.index == 275)
}

@Test func collectionSearchCanMatchAcrossProperties() async throws {
    let users = [
        User(firstName: "Sarah", lastName: "Connor", address: "Los Angeles"),
        User(firstName: "Sara", lastName: "King", address: "London"),
    ]
    
    let results = await Fuzzy().search(for: "Sarah Connor", in: users)
    
    #expect(results.first?.item.lastName == "Connor")
    #expect((results.first?.score ?? 0) > 0.9)
}

@Test func searchCanMatchNestedSearchableProperties() async throws {
    let users = [
        NestedUser(
            firstName: "Sarah",
            lastName: "Connor",
            address: Address(city: "Los Angeles", country: "United States")
        ),
        NestedUser(
            firstName: "Sara",
            lastName: "King",
            address: Address(city: "London", country: "United Kingdom")
        ),
    ]
    
    let results = await Fuzzy().search(for: "United Kingdom", in: users)
    
    #expect(results.first?.item.lastName == "King")
}

@Test func searchToleratesTyposAndDiacritics() async throws {
    let users = [
        User(firstName: "Søren", lastName: "Kierkegaard", address: "Copenhagen"),
        User(firstName: "Sara", lastName: "King", address: "London"),
    ]
    
    let typoResults = await Fuzzy().search(for: "Saren", in: users)
    let diacriticResult = await Fuzzy().search(for: "Soren", in: users)
    
    #expect(typoResults.first?.item.firstName == "Søren")
    #expect(diacriticResult.first?.item.firstName == "Søren")
}

@Test func searchSupportsLimitAndMinimumScore() async throws {
    let users = [
        User(firstName: "Sarah", lastName: "Connor", address: "Los Angeles"),
        User(firstName: "Sara", lastName: "King", address: "London"),
        User(firstName: "Michael", lastName: "Biehn", address: "Chicago"),
    ]
    
    let limitedResults = await Fuzzy().search(for: "Sara", in: users, limit: 1)
    let strictResults = await Fuzzy().search(for: "Sara", in: users, minimumScore: 0.95)
    
    #expect(limitedResults.count == 1)
    #expect(strictResults.allSatisfy { $0.score >= 0.95 })
}

@Test func customAlgorithmCanBeInjected() async throws {
    struct ConstantAlgorithm: SearchAlgorithm {
        let value: Double
        
        func score(query: String, descriptor: SearchDescriptor) -> Double {
            value
        }
    }
    
    let user = User(firstName: "Sarah", lastName: "Connor", address: "Los Angeles")
    
    let result = await Fuzzy(algorithm: ConstantAlgorithm(value: 0.42))
        .search(for: "anything", in: user, minimumScore: 0)
    
    #expect(result?.score == 0.42)
}

@Test func searchIndexActorSearchesStoredItems() async throws {
    let index = SearchIndex(items: [
        User(firstName: "Sarah", lastName: "Connor", address: "Los Angeles"),
        User(firstName: "Kyle", lastName: "Reese", address: "Los Angeles"),
    ])
    
    await index.append(User(firstName: "John", lastName: "Connor", address: "Mexico"))
    let results = await index.search(for: "John", limit: 1)
    
    #expect(results.first?.item.firstName == "John")
}
