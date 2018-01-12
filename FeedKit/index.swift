//
//  index.swift - Core types
//  FeedKit
//
//  Created by Michael Nisi on 17.07.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import Foundation

/// Wraps a value into an `NSObject`.
class ValueObject<T>: NSObject {
  let value: T
  init(_ value: T) {
    self.value = value
  }
}

public extension Notification.Name {

  /// Posted when a remote request has been started.
  static var FKRemoteRequest =
    NSNotification.Name("FeedKitRemoteRequest")

  /// Posted when a remote response has been received.
  static var FKRemoteResponse =
    NSNotification.Name("FeedKitRemoteResponse")
  
}

/// Enumerate all error types possibly thrown within the FeedKit framework.
public enum FeedKitError : Error {
  case unknown
  case niy
  case notAString
  case general(message: String)
  case cancelledByUser
  case notAFeed
  case notAnEntry
  case serviceUnavailable(error: Error)
  case feedNotCached(urls: [String])
  case unknownEnclosureType(type: String)
  case multiple(errors: [Error])
  case unexpectedJSON
  case sqlFormatting
  case cacheFailure(error: Error)
  case invalidSearchTerm(term: String)
  case invalidEntry(reason: String)
  case invalidEntryLocator(reason: String)
  case invalidEnclosure(reason: String)
  case invalidFeed(reason: String)
  case invalidSuggestion(reason: String)
  case offline
  case noForceApplied
  case missingEntries(locators: [EntryLocator])
  case unexpectedDatabaseRow
  case unidentifiedFeed
}

extension FeedKitError: Equatable {
  public static func ==(lhs: FeedKitError, rhs: FeedKitError) -> Bool {
    return lhs._code == rhs._code
  }
}

public protocol Redirectable {
  var url: String { get }
  var originalURL: String? { get }
}

extension Redirectable {

  /// Filters and returns `items` with redirected URLs.
  static func redirects(in items: [Redirectable]) -> [Redirectable] {
    return items.filter {
      guard let originalURL = $0.originalURL, originalURL != $0.url else {
        return false
      }
      return true
    }
  }
  
}

// Additional per podcast information, aquired via iTunes search, entirely
// optional. Especially `guid` isn’t used in this framework. We identify
// feeds by URLs.
public struct ITunesItem {
  public let iTunesID: Int
  public let img100: String
  public let img30: String
  public let img60: String
  public let img600: String

  public init(iTunesID: Int, img100: String, img30: String, img60: String, img600: String) {
    self.iTunesID = iTunesID
    self.img100 = img100
    self.img30 = img30
    self.img60 = img60
    self.img600 = img600
  }
}

extension ITunesItem: Equatable {
  public static func ==(lhs: ITunesItem, rhs: ITunesItem) -> Bool {
    return lhs.iTunesID == rhs.iTunesID
  }
}

extension ITunesItem: CustomStringConvertible {
  public var description: String {
    return "ITunesItem: { \(iTunesID) }"
  }
}

extension ITunesItem: CustomDebugStringConvertible {
  public var debugDescription: String {
    get {
      return """
      ITunesItem: {
        iTunesID: \(iTunesID),
        img100: \(img100),
        img30: \(img30),
        img60: \(img60),
        img600: \(img600)
      }
      """
    }
  }
}

public protocol Imaginable {
  var iTunes: ITunesItem? { get }
  var image: String? { get }
}

public typealias FeedURL = String

public struct FeedID: Equatable {
  let rowid: Int64
  let url: FeedURL

  public static func ==(lhs: FeedID, rhs: FeedID) -> Bool {
    return lhs.rowid == rhs.rowid
  }
}

/// Feeds are the central object of this framework.
///
/// The initializer is inconvenient for a reason: **it shouldn't be used
/// directly**. Instead users are expected to obtain their feeds from the
/// repositories provided by this framework. Two feeds are equal if they
/// have equal URLs.
///
/// A feed is required to, at least, have `title` and `url`.
public struct Feed: Cachable, Redirectable, Imaginable {
  public let author: String?
  public let iTunes: ITunesItem?
  public let image: String?
  public let link: String?
  public let originalURL: String?
  public let summary: String?
  public let title: String
  public let ts: Date?
  public let uid: FeedID? // TODO: Rename to feedID
  public let updated: Date?
  public let url: FeedURL
}

extension Feed : CustomStringConvertible {
  public var description: String {
    return "Feed: \(title)"
  }
}

extension Feed: CustomDebugStringConvertible {
  public var debugDescription: String {
    return """
    Feed(
      title: \(title),
      url: \(url),
      summary: \(String(describing: summary))
    )
    """
  }
}

extension Feed: Equatable {
  static public func ==(lhs: Feed, rhs: Feed) -> Bool {
    return lhs.url == rhs.url
  }
}

extension Feed: Hashable {
  public var hashValue: Int {
    get { return url.hashValue }
  }
}

/// Enumerate supported enclosure media types. Note that unknown is legit here.
public enum EnclosureType : Int {
  case unknown

  case audioMPEG
  case audioXMPEG
  case videoXM4V
  case audioMP4
  case xm4A
  case videoMP4

  public init (withString type: String) {
    switch type {
    case "audio/mpeg": self = .audioMPEG
    case "audio/x-mpeg": self = .audioXMPEG
    case "video/x-m4v": self = .videoXM4V
    case "audio/mp4": self = .audioMP4
    case "audio/x-m4a": self = .xm4A
    case "video/mp4": self = .videoMP4
    default: self = .unknown
    }
  }

  // TODO: Correct enclosure types

  public var isVideo: Bool {
    get {
      switch self {
      case .videoXM4V, .videoMP4, .unknown:
        return true
      default:
        return false
      }
    }
  }
}

/// The infamous RSS enclosure tag is mapped to this structure.
public struct Enclosure {
  public let url: String
  public let length: Int?
  public let type: EnclosureType
}

extension Enclosure: Equatable {
  public static func ==(lhs: Enclosure, rhs: Enclosure) -> Bool {
    return lhs.url == rhs.url
  }
}

extension Enclosure : CustomStringConvertible {
  public var description: String {
    return "Enclosure: \(url)"
  }
}

// TODO: Type alias guid to EntryGUID
public typealias EntryGUID = String

/// RSS item or Atom entry. In this domain we speak of `entry`.
public struct Entry: Redirectable, Imaginable {
  public let author: String?
  public let duration: Int?
  public let enclosure: Enclosure?
  public let feed: FeedURL
  public let feedImage: String?
  public let feedTitle: String?
  public let guid: String
  public let iTunes: ITunesItem?
  public let image: String?
  public let link: String?
  public let originalURL: String?
  public let subtitle: String?
  public let summary: String?
  public let title: String
  public let ts: Date?
  public let updated: Date
}

extension Entry : Cachable {
  public var url: String {
    get { return feed }
  }
}

extension Entry : CustomStringConvertible {
  public var description: String {
    return "Entry: { \(title), \(guid) }"
  }
}

extension Entry: Equatable {
  static public func ==(lhs: Entry, rhs: Entry) -> Bool {
    return lhs.guid == rhs.guid
  }
}

extension Entry: Hashable {
  public var hashValue: Int {
    get { return guid.hashValue }
  }
}

/// Entry locators identify a specific entry by `guid`, or skirt intervals
/// of entries from a specific feed, between now and `since`.
public struct EntryLocator {

  public let url: FeedURL

  public let since: Date

  public let guid: String?

  public let title: String?

  /// Initializes a newly created entry locator with the specified feed URL,
  /// time interval, and optional guid.
  ///
  /// This object might be used to locate multiple entries within an interval
  /// or to locate a single entry specifically using the guid.
  ///
  /// - Parameters:
  ///   - url: The URL of the feed.
  ///   - since: A date in the past when the interval begins.
  ///   - guid: An identifier to locate a specific entry.
  ///   - title: Arbitrary title for user-facing error messages.
  ///
  /// - Returns: The newly created entry locator.
  public init(
    url: FeedURL,
    since: Date? = nil,
    guid: String? = nil,
    title: String? = nil
  ) {
    self.url = url
    self.since = since ?? Date(timeIntervalSince1970: 0)
    self.guid = guid
    self.title = title
  }

  /// Creates a new locator from `entry`.
  ///
  /// - Parameter entry: The entry to locate.
  public init(entry: Entry) {
    self.init(url: entry.feed, since: entry.updated, guid: entry.guid,
              title: entry.title)
  }

  /// Returns a new `EntryLocator` with a modified *inclusive* `since`.
  public var including: EntryLocator { get {
    return EntryLocator(url: url, since: since.addingTimeInterval(-1), guid: guid)
  }}
}

extension EntryLocator: Hashable {
  public var hashValue: Int {
    get {
      guard let guid = self.guid else {
        return url.hashValue ^ since.hashValue
      }
      return guid.hashValue
    }
  }
}

extension EntryLocator: Equatable {
  public static func ==(lhs: EntryLocator, rhs: EntryLocator) -> Bool {
    return lhs.hashValue == rhs.hashValue
  }
}

extension EntryLocator : CustomStringConvertible {
  public var description: String {
    guard let title = self.title else {
      return """
      EntryLocator: {
        url: \(url),
        guid: \(String(describing: guid)),
        since: \(since)
      }
      """
    }
    return "EntryLocator: { \(title) }"
  }
}

extension EntryLocator {

  public func encode(with coder: NSCoder) {
    coder.encode(self.guid, forKey: "guid")
    coder.encode(self.url, forKey: "url")
    coder.encode(self.since, forKey: "since")
    coder.encode(self.title, forKey: "title")
  }

  public init?(coder: NSCoder) {
    guard
      let guid = coder.decodeObject(forKey: "guid") as? String,
      let url = coder.decodeObject(forKey: "url") as? String else {
        return nil
    }
    let since = coder.decodeObject(forKey: "since") as? Date
    let title = coder.decodeObject(forKey: "title") as? String

    self.url = url
    self.since = since ?? Date(timeIntervalSince1970: 0)
    self.guid = guid
    self.title = title
  }
}

extension EntryLocator {

  /// Removes doublets, having the same GUID, and merges locators with similar
  /// URLs into a single locator with the longest time-to-live for that URL.
  static func reduce(_ locators: [EntryLocator], expanding: Bool = true) -> [EntryLocator] {
    guard !locators.isEmpty else {
      return []
    }

    let unique = Array(Set(locators))

    var withGuids = [EntryLocator]()
    var withoutGuidsByUrl = [String : [EntryLocator]]()

    for loc in unique {
      if loc.guid == nil {
        let url = loc.url
        if let prev = withoutGuidsByUrl[url] {
          withoutGuidsByUrl[url] = prev + [loc]
        } else {
          withoutGuidsByUrl[url] = [loc]
        }
      } else {
        withGuids.append(loc)
      }
    }

    guard !withoutGuidsByUrl.isEmpty else {
      return withGuids
    }

    var withoutGuids = [EntryLocator]()

    let areInIncreasingOrder: (EntryLocator, EntryLocator) -> Bool = {
      return expanding ?
        { $0.since < $1.since } :
        { $0.since > $1.since }
    }()

    for it in withoutGuidsByUrl {
      let sorted = it.value.sorted(by: areInIncreasingOrder)
      guard let loc = sorted.first else {
        continue
      }
      withoutGuids.append(loc)
    }

    return withGuids + withoutGuids
  }
}

/// A suggested search term, bearing the timestamp of when it was added
/// (to the cache) or updated.
public struct Suggestion {
  public let term: String
  public var ts: Date? // if cached
}

extension Suggestion : CustomStringConvertible {
  public var description: String {
    return "Suggestion: \(term) \(String(describing: ts))"
  }
}

extension Suggestion: Equatable {
  static public func ==(lhs: Suggestion, rhs: Suggestion) -> Bool {
    return lhs.term == rhs.term
  }
}

extension Suggestion: Hashable {
  public var hashValue: Int {
    get { return term.hashValue }
  }
}

// Supplied by a single UITableViewDataSource class. Or maybe two, like Find and
// Item, but the question is: how different would they be, really? Considering
// that with an holistic search, the kind we want to offer, a Find may be
// literally anything in the system. Doesn’t this make Find just an Item? To
// figure this out, create item lists of all expected combinations.
//
// A couple of days later, I’m not convinced about this—a global master thing
// always ends in flames, not a good argument, I know, but all I muster to come
// up with now. Keep enumerating for specific needs!

/// Enumerates findable things hiding their type. The word 'suggested' is used
/// synonymously with 'found' here: a suggested feed is also a found feed, etc.
public enum Find {
  case recentSearch(Feed)
  case suggestedTerm(Suggestion)
  case suggestedEntry(Entry)
  case suggestedFeed(Feed)
  case foundFeed(Feed)

  /// The timestamp applied by the database.
  var ts: Date? {
    switch self {
    case .recentSearch(let it): return it.ts
    case .suggestedTerm(let it): return it.ts
    case .suggestedEntry(let it): return it.ts
    case .suggestedFeed(let it): return it.ts
    case .foundFeed(let it): return it.ts
    }
  }
}

extension Find: Equatable {
  static public func ==(lhs: Find, rhs: Find) -> Bool {
    switch (lhs, rhs) {
    case (.suggestedEntry(let a), .suggestedEntry(let b)):
      return a == b
    case (.suggestedTerm(let a), .suggestedTerm(let b)):
      return a == b
    case (.suggestedFeed(let a), .suggestedFeed(let b)):
      return a == b
    case (.recentSearch(let a), .recentSearch(let b)):
      return a == b
    case (.foundFeed(let a), .foundFeed(let b)):
      return a == b
    case (.suggestedEntry, _),
         (.suggestedTerm, _),
         (.suggestedFeed, _),
         (.recentSearch, _),
         (.foundFeed, _):
      return false
    }
  }
}

extension Find: Hashable {
  public var hashValue: Int {
    get {
      switch self {
      case .foundFeed(let feed),
           .recentSearch(let feed),
           .suggestedFeed(let feed):
        return feed.hashValue
      case .suggestedEntry(let entry):
        return entry.hashValue
      case .suggestedTerm(let suggestion):
        return suggestion.hashValue
      }
    }
  }
}
