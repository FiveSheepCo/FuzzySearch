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

private struct MultiAddressUser: Searchable, Sendable, Equatable {
    let firstName: String
    let lastName: String
    let addresses: [Address]
    
    var searchDescriptor: SearchDescriptor {
        SearchDescriptor()
            .add(firstName)
            .add(lastName)
            .add(addresses, weight: 0.5)
    }
}

private struct TaggedUser: Searchable, Sendable, Equatable {
    let firstName: String
    let lastName: String
    let tags: [String]
    
    var searchDescriptor: SearchDescriptor {
        SearchDescriptor()
            .add(firstName)
            .add(lastName)
            .add(tags, weight: 0.5)
    }
}

private struct ManualComponent: Searchable, Sendable, Equatable {
    let title: String
    
    var searchDescriptor: SearchDescriptor {
        SearchDescriptor(title)
    }
}

private struct ManualEntry: Searchable, Sendable, Equatable {
    let title: String
    let components: [ManualComponent]
    
    var searchDescriptor: SearchDescriptor {
        SearchDescriptor()
            .add(title)
            .add(components, weight: 0.75)
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

@Test func searchCanMatchArraysOfNestedSearchableProperties() async throws {
    let users = [
        MultiAddressUser(
            firstName: "Sarah",
            lastName: "Connor",
            addresses: [
                Address(city: "Los Angeles", country: "United States"),
                Address(city: "Mexico City", country: "Mexico"),
            ]
        ),
        MultiAddressUser(
            firstName: "Sara",
            lastName: "King",
            addresses: [
                Address(city: "London", country: "United Kingdom"),
                Address(city: "Bangkok", country: "Thailand"),
            ]
        ),
    ]
    
    let results = await Fuzzy().search(for: "Thailand", in: users)
    
    #expect(results.first?.item.lastName == "King")
}

@Test func searchCanMatchArraysOfSearchableValues() async throws {
    let users = [
        TaggedUser(firstName: "Sarah", lastName: "Connor", tags: ["resistance", "los-angeles"]),
        TaggedUser(firstName: "Sara", lastName: "King", tags: ["travel", "thailand"]),
    ]
    
    let results = await Fuzzy().search(for: "Thailand", in: users)
    
    #expect(results.first?.item.lastName == "King")
}

@Test func searchCanMatchWeightedArraysWhoseElementsUseConvenienceDescriptors() async throws {
    let entries = [
        ManualEntry(title: "Getting started", components: [
            ManualComponent(title: "Installation"),
            ManualComponent(title: "Configuration"),
        ]),
        ManualEntry(title: "Travel tools", components: [
            ManualComponent(title: "Thailand TDAC"),
            ManualComponent(title: "Ninety day reporting"),
        ]),
    ]
    
    let results = await Fuzzy().search(for: "TDAC", in: entries)
    
    #expect(results.first?.item.title == "Travel tools")
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

@Test func collectionSearchSupportsSearchableValues() async throws {
    let values = ["Bangkok", "London", "Los Angeles", "Mexico City"]
    
    let results = await Fuzzy().search(for: "Angeles", in: values)
    
    #expect(results.first?.item == "Los Angeles")
    #expect(results.first?.index == 2)
}

@Test func collectionSearchIncludesMatchRangesForSearchableValues() async throws {
    let values = ["Bangkok", "London", "Los Angeles", "Mexico City"]
    
    let results = await Fuzzy().search(for: "Angeles", in: values)
    
    #expect(results.first?.matches.first?.value == "Los Angeles")
    #expect(results.first?.matches.first?.range == 4...10)
    #expect(results.first?.matches.first?.text == "Angeles")
}

@Test func singleSearchIncludesMatchRangesForSearchableProperties() async throws {
    let user = User(firstName: "Sarah", lastName: "Connor", address: "Los Angeles")
    
    let result = await Fuzzy().search(for: "Angeles", in: user)
    
    #expect(result?.matches.first?.value == "Los Angeles")
    #expect(result?.matches.first?.range == 4...10)
    #expect(result?.matches.first?.text == "Angeles")
}

@Test func matchRangesUseOriginalStringOffsetsAfterNormalization() async throws {
    let users = [
        User(firstName: "Søren", lastName: "Kierkegaard", address: "Copenhagen"),
        User(firstName: "Sara", lastName: "King", address: "London"),
    ]
    
    let results = await Fuzzy().search(for: "søren", in: users)
    
    #expect(results.first?.matches.first?.value == "Søren")
    #expect(results.first?.matches.first?.range == 0...4)
    #expect(results.first?.matches.first?.text == "Søren")
}

@Test func multiTokenSearchIncludesMatchRangesFromMultipleProperties() async throws {
    let users = [
        User(firstName: "Sarah", lastName: "Connor", address: "Los Angeles"),
        User(firstName: "Sara", lastName: "King", address: "London"),
    ]
    
    let results = await Fuzzy().search(for: "Sarah Connor", in: users)
    
    #expect(results.first?.matches.map(\.text).contains("Sarah") == true)
    #expect(results.first?.matches.map(\.text).contains("Connor") == true)
}

@Test func matchesDoNotReportSubsequenceFallbackRanges() async throws {
    let values = ["https://youtu.be/uN_Vb4ZnD4Q?si=redirect"]
    
    let results = await Fuzzy().search(for: "Visa", in: values, minimumScore: 0)
    
    #expect(results.first?.matches.isEmpty == true)
}

@Test func literalSubstringMatchesAreReportedWhenFallbacksAlsoExist() async throws {
    let values = [
        "https://youtu.be/uN_Vb4ZnD4Q?si=redirect",
        "ThaiVisaTracker helps travelers",
    ]
    
    let results = await Fuzzy().search(for: "Visa", in: values, minimumScore: 0)
    let thaiVisaMatch = results
        .flatMap(\.matches)
        .first { $0.value == "ThaiVisaTracker helps travelers" }
    
    #expect(thaiVisaMatch?.range == 4...7)
    #expect(thaiVisaMatch?.text == "Visa")
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
