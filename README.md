# FuzzySearch

FuzzySearch is a small Swift package for making any type searchable with a simple descriptor-based API. It provides async search, weighted fields, ranked results, a replaceable search algorithm, and concurrency-friendly collection search.

The default algorithm is tuned for practical fuzzy lookup across names, addresses, labels, and other short to medium text fields. It handles case folding, diacritics, token matching, prefix/substring matches, ordered subsequences, and edit-distance fallback.

## Installation

Add FuzzySearch to your Swift package dependencies:

```swift
.package(url: "https://github.com/your-org/FuzzySearch.git", branch: "main")
```

Then add it to a target:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "FuzzySearch", package: "FuzzySearch"),
    ]
)
```

## Basic Usage

Conform your model to `Searchable` and build a `SearchDescriptor` from the fields that should be searched.

```swift
import FuzzySearch

struct User: Sendable {
    let firstName: String
    let lastName: String
    let address: String
}

extension User: Searchable {
    var searchDescriptor: SearchDescriptor {
        SearchDescriptor()
            .add(firstName)
            .add(lastName)
            .add(address, weight: 0.5)
    }
}
```

Search a collection:

```swift
let users: [User] = [
    User(firstName: "Sarah", lastName: "Connor", address: "Los Angeles"),
    User(firstName: "Sara", lastName: "King", address: "London"),
]

let results = await Fuzzy().search(for: "Sarah", in: users)

for result in results {
    print(result.item, result.score)
}
```

Search a collection of values directly:

```swift
let cities = ["Bangkok", "London", "Los Angeles", "Mexico City"]
let cityResults = await Fuzzy().search(for: "Angeles", in: cities)
```

Search a single value:

```swift
let result = await Fuzzy().search(for: "Sarah", in: users[0])
```

## Results

Collection search returns `[SearchResult<Item>]`, sorted from highest score to lowest score.

```swift
public struct SearchResult<Item>: Sendable where Item: Sendable {
    public let item: Item
    public let score: Double
    public let index: Int?
    public let matches: [SearchMatch]
}

public struct SearchMatch: Sendable {
    public let value: String
    public let range: ClosedRange<Int>
    public let text: String
}
```

Scores are normalized from `0.0` to `1.0`, where higher is better.
For collection searches, `index` is the source collection offset for the matched item. Single-item searches return `nil`.
The default algorithm also returns `matches` for the searched fields that matched. Each match includes the original searchable string, a character-offset range in that original string, and the matched text.

```swift
let cities = ["Bangkok", "London", "Los Angeles", "Mexico City"]
let results = await Fuzzy().search(for: "Angeles", in: cities)

let match = results[0].matches[0]
print(match.value) // "Los Angeles"
print(match.range) // 4...10
print(match.text)  // "Angeles"
```

You can limit result count or filter weak matches:

```swift
let results = await Fuzzy().search(
    for: "Tom Shelby",
    in: people,
    limit: 10,
    minimumScore: 0.35
)
```

## Weighted Fields

Use field weights when some values should matter less than others.

```swift
var searchDescriptor: SearchDescriptor {
    SearchDescriptor()
        .add(firstName)
        .add(lastName)
        .add(city, weight: 0.5)
}
```

Weights are relative. A field with `weight: 0.5` contributes less strongly than fields with the default `weight: 1.0`.

Descriptors can also include nested `Searchable` values, including arrays of `Searchable` values. Nested field weights are preserved and multiplied by the outer weight.

```swift
struct Address: Searchable {
    let city: String
    let country: String

    var searchDescriptor: SearchDescriptor {
        SearchDescriptor()
            .add(city)
            .add(country, weight: 0.5)
    }
}

struct User: Searchable {
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
```

Descriptors can include arrays of `SearchableValue` values too. For example, `[String]` works because `String` conforms to `SearchableValue`.

```swift
struct Article: Searchable {
    let title: String
    let tags: [String]

    var searchDescriptor: SearchDescriptor {
        SearchDescriptor()
            .add(title)
            .add(tags, weight: 0.5)
    }
}
```

## SearchIndex Actor

For a reusable dataset, `SearchIndex` stores items behind an actor and exposes async search.

```swift
let index = SearchIndex(items: users)

await index.append(User(
    firstName: "John",
    lastName: "Connor",
    address: "Mexico City"
))

let results = await index.search(for: "John", limit: 5)
```

This is useful when multiple tasks need to read or update a shared search corpus.

## Custom Algorithms

`FuzzySearch` supports custom search algorithms by providing any `SearchAlgorithm`.

```swift
struct MyAlgorithm: SearchAlgorithm {
    func score(query: String, descriptor: SearchDescriptor) -> Double {
        // Return a normalized score from 0.0 to 1.0.
        0
    }
}

let fuzzy = Fuzzy(algorithm: MyAlgorithm())
```

Algorithms that can preprocess the query once per collection search can conform to `QueryPreparingSearchAlgorithm`:

```swift
struct MyPreparedAlgorithm: QueryPreparingSearchAlgorithm {
    func prepare(query: String) -> PreparedSearchQuery {
        PreparedSearchQuery(query)
    }

    func score(query: String, descriptor: SearchDescriptor) -> Double {
        score(preparedQuery: prepare(query: query), descriptor: descriptor)
    }

    func score(preparedQuery: PreparedSearchQuery, descriptor: SearchDescriptor) -> Double {
        // Score using the prepared query.
        0
    }
}
```

Custom algorithms can return match ranges by conforming to `SearchEvaluatingAlgorithm` or `QueryPreparingSearchEvaluatingAlgorithm` and returning `SearchEvaluation(score:matches:)`.

## Concurrency

The public search methods are async. Small collections are scored inline to avoid task overhead. Larger collections are split into chunks and scored with Swift task groups.

Model types searched in collections must be `Sendable`:

```swift
public func search<C>(
    for string: String,
    in collection: C,
    limit: Int? = nil,
    minimumScore: Double = 0.2
) async -> [SearchResult<C.Element>]
where C: Collection & Sendable, C.Element: Searchable & Sendable
```

Collections whose elements conform to `SearchableValue`, such as `[String]`, can be searched with the same API.

## Running Tests

Run the unit tests with:

```sh
swift test
```

## Performance Benchmarks

The package includes a benchmark target that compares FuzzySearch against [Ifrit](https://github.com/ukushu/Ifrit) and [Fuse](https://github.com/krisk/fuse-swift).

Run:

```sh
swift package benchmark --target CompetitorBench
```

Use this when changing:

- scoring logic
- normalization
- result sorting
- concurrency thresholds
- descriptor construction

Benchmark results are workload-sensitive. Run the benchmark more than once before drawing conclusions from small differences.

## Quality Evaluation

Speed alone is not enough for fuzzy search. The package also includes a quality evaluator that compares FuzzySearch, Fuse, and Ifrit against a judged query set.

Run:

```sh
swift run QualityEval
```

The evaluator reports:

- `Top1`: whether a best expected result was ranked first
- `MRR`: mean reciprocal rank of the first relevant result
- `nDCG@5`: top-five ranking quality with graded relevance
- per-query misses, including expected IDs and actual top-five IDs

## Suggested Development Workflow

When changing the algorithm:

```sh
swift test
swift run QualityEval
swift package benchmark
```

Use tests for API behavior, `QualityEval` for relevance/ranking changes, and benchmarks for speed and allocation changes.
