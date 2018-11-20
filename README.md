# FeedKit

The FeedKit framework provides core functionality for building a feed reader. It implements searching, browsing, and caching RSS feeds, as well as subscription management.

FeedKit sits at the core of the [Podest](https://github.com/michaelnisi/podest) podcast app.

## Dependencies

- [fanboy-kit](https://github.com/michaelnisi/fanboy-kit), Search podcasts via proxy
- [manger-kit](https://github.com/michaelnisi/manger-kit), Request podcasts via proxy
- [ola](https://github.com/michaelnisi/ola), Check reachability
- [skull](https://github.com/michaelnisi/skull), Swift SQLite

## Core Symbols

### Enums

#### FeedKitError

```swift
enum FeedKitError: Error, Equatable
```

### Protocols

#### Redirectable

```swift
protocol Redirectable
```

### Structs

#### FeedID

```swift
struct FeedID: Codable, Equatable, Hashable
```

#### Feed

```swift
struct Feed: Codable, Equatable, Hashable, Cachable, Redirectable, Imaginable
```

#### EntryLocator

```swift
struct EntryLocator: Equatable, Hashable
```

#### Entry

```swift
struct Entry: Codable, Equatable, Hashable, Cachable, Redirectable, Imaginable
```

## Installation

Integrate the FeedKit framework into your Xcode workspace.

## License

[MIT License](https://github.com/michaelnisi/feedkit/blob/master/LICENSE)
