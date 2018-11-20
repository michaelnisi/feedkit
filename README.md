# FeedKit

The FeedKit framework provides feeds and entries. It implements searching, browsing, and caching feeds, as well as subscription management for a single user.

FeedKit sits at the core of the [Podest](https://github.com/michaelnisi/podest) podcast app.

## Dependencies

- [fanboy-kit](https://github.com/michaelnisi/fanboy-kit), Search podcasts via proxy
- [manger-kit](https://github.com/michaelnisi/manger-kit), Request podcasts via proxy
- [nuke](https://github.com/michaelnisi/nuke), A powerful image loading and caching system
- [ola](https://github.com/michaelnisi/ola), Check reachability
- [skull](https://github.com/michaelnisi/skull), Swift SQLite

## Services

- [fanboy-http](https://github.com/michaelnisi/fanboy-http), Search podcasts
- [manger-http](https://github.com/michaelnisi/manger-http), Browse podcasts

## Core

The FeedKit framework is focussed around feeds and their entries. Its purpose is providing these items.

```swift
struct Feed
```

A feed is identified by its URL, it contains information about the feed.

```swift
struct Entry
```

An entry is related to a single feed by its URL and contains information specific to a single item *within* the feed. Since FeedKit prefers flat data structures, calling entries children of feeds would not be correct.

## Cache

FeedKit maintains a local cache of feeds, entries, and search results.

## Search

To get data into the system you have to discover it first.

## Browsing

Access specific entries and ranges of entries with locators.

## User

FeedKit manages feed subscriptions of a single user.

## Installation

Integrate the FeedKit framework into your Xcode workspace.

## Testing

Most tests expect to find [fanboy-http](https://github.com/michaelnisi/fanboy-http) and [manger-http](https://github.com/michaelnisi/manger-http) locally.

## License

[MIT License](https://github.com/michaelnisi/feedkit/blob/master/LICENSE)
