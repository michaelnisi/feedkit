//
//  index.swift - API and common internal functions
//  FeedKit
//
//  Created by Michael Nisi on 17.07.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import Foundation
import Ola
import Patron
import os.log

/// Adds this framework‘s notification names.
public extension Notification.Name {

  /// Posted when a remote request has been started.
  static var FKRemoteRequest =
    NSNotification.Name("FeedKitRemoteRequest")

  /// Posted when a remote response has been received.
  static var FKRemoteResponse =
    NSNotification.Name("FeedKitRemoteResponse")

  /// Posted after the users‘s subscriptions have been changed.
  public static var FKSubscriptionsDidChange =
    NSNotification.Name("FeedKitSubscriptionsDidChange")

  /// Posted after the user‘s queue has been changed.
  public static var FKQueueDidChange =
    NSNotification.Name("FeedKitQueueDidChange")

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

/// Cachable objects, currently feeds and entries, must adopt this protocol,
/// which requires a globally unique resource locator (url) and a timestamp (ts).
public protocol Cachable {
  var ts: Date? { get }
  var url: String { get }
}

public protocol Redirectable {
  var url: String { get }
  var originalURL: String? { get }
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

public protocol Imaginable {
  var iTunes: ITunesItem? { get }
  var image: String? { get }
}

public struct FeedID: Equatable {
  let rowid: Int64
  let url: String
  
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
  public let url: String
}

extension Feed : CustomStringConvertible {
  public var description: String {
    return "Feed: \(title)"
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
  public let feed: String
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

  public let url: String

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
    url: String,
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

  /// Removes doublets with the same GUID and merges locators with similar
  /// URLs into a single locator with the longest time-to-live for that URL.
  static func reduce(_ locators: [EntryLocator]) -> [EntryLocator] {
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

    for it in withoutGuidsByUrl {
      let sorted = it.value.sorted { $0.since < $1.since }
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

/// Enumerate default time-to-live intervals used for caching.
///
/// - None: Zero seconds.
/// - Short: One hour.
/// - Medium: Eight hours.
/// - Long: 24 hours.
/// - Forever: Infinity.
public enum CacheTTL {
  case none
  case short
  case medium
  case long
  case forever

  /// The time-to-live interval in seconds.
  var seconds: TimeInterval {
    get {
      switch self {
      case .none: return 0
      case .short: return 3600
      case .medium: return 28800
      case .long: return 86400
      case .forever: return Double.infinity
      }
    }
  }
}

// MARK: - Caching

/// A common protocol for local caching.
public protocol Caching {
  /// Flushes any dispensable resources to save memory.
  func flush() throws
}

// MARK: - FeedCaching

/// A persistent cache for feeds and entries.
public protocol FeedCaching: Caching {
  func update(feeds: [Feed]) throws
  func feeds(_ urls: [String]) throws -> [Feed]

  func update(entries: [Entry]) throws
  func entries(within locators: [EntryLocator]) throws -> [Entry]
  func entries(_ guids: [String]) throws -> [Entry]

  func remove(_ urls: [String]) throws
  
  /// Integrates iTunes metadata from `subscriptions`.
  func integrateMetadata(from subscriptions: [Subscription]) throws
}

// MARK: - SearchCaching

/// A persistent cache of things related to searching feeds and entries.
public protocol SearchCaching: Caching {
  func update(suggestions: [Suggestion], for term: String) throws
  func suggestions(for term: String, limit: Int) throws -> [Suggestion]?

  func update(feeds: [Feed], for: String) throws
  func feeds(for term: String, limit: Int) throws -> [Feed]?
  func feeds(matching term: String, limit: Int) throws -> [Feed]?
  func entries(matching term: String, limit: Int) throws -> [Entry]?
}

// MARK: - Searching

/// The search API of the FeedKit framework.
public protocol Searching: Caching {
  
  /// Search for feeds by term using locally cached data requested from a remote
  /// service. This method falls back on cached data if the remote call fails;
  /// the failure is reported by passing an error in the completion block.
  ///
  /// - Parameters:
  ///   - term: The term to search for.
  ///   - perFindGroupBlock: The block to receive finds.
  ///   - searchCompletionBlock: The block to execute after the search
  /// is complete.
  ///
  /// - returns: The, already executing, operation.
  @discardableResult func search(
    _ term: String,
    perFindGroupBlock: @escaping (Error?, [Find]) -> Void,
    searchCompletionBlock: @escaping (Error?) -> Void
  ) -> Operation

  /// Get lexicographical suggestions for a search term combining locally cached
  /// and remote data.
  ///
  /// - Parameters:
  ///   - term: The term to search for.
  ///   - perFindGroupBlock: The block to receive finds, called once
  ///   per find group as enumerated in `Find`.
  ///   - completionBlock: A block called when the operation has finished.
  ///
  /// - Returns: The executing operation.
  @discardableResult func suggest(
    _ term: String,
    perFindGroupBlock: @escaping (Error?, [Find]) -> Void,
    suggestCompletionBlock: @escaping (Error?) -> Void
  ) -> Operation
  
}

// MARK: - Browsing

/// An asynchronous API for accessing feeds and entries. Designed with data
/// aggregation from sources with diverse run times in mind, result blocks might
/// get called multiple times. Completion blocks are called once.
public protocol Browsing: Caching {

  @discardableResult func feeds(
    _ urls: [String],
    feedsBlock: @escaping (Error?, [Feed]) -> Void,
    feedsCompletionBlock: @escaping (Error?) -> Void
  ) -> Operation

  @discardableResult func entries(
    _ locators: [EntryLocator],
    entriesBlock: @escaping (Error?, [Entry]) -> Void,
    entriesCompletionBlock: @escaping (Error?) -> Void
  ) -> Operation

  @discardableResult func entries(
    _ locators: [EntryLocator],
    force: Bool,
    entriesBlock: @escaping (Error?, [Entry]) -> Void,
    entriesCompletionBlock: @escaping (Error?) -> Void
  ) -> Operation
  
  /// Integrates metadata from `subscriptions`.
  func integrateMetadata(
    from subscriptions: [Subscription],
    completionBlock: ((_ error: Error?) -> Void)?
  ) -> Void

}

// MARK: - Queueing

/// An item that can be in the user’s queue. At the moment these are just
/// entries, but we might add seasons, etc.
public enum Queued {
  case entry(EntryLocator, Date)
}

extension Queued: Equatable {
  static public func ==(lhs: Queued, rhs: Queued) -> Bool {
    switch (lhs, rhs) {
    case (.entry(let a, _), .entry(let b, _)):
      return a == b
    }
  }
}

extension Queued: Hashable {
  public var hashValue: Int {
    get {
      switch self {
      case .entry(let locator, _):
        return locator.hashValue
      }
    }
  }
}

/// The local cache of the queue.
public protocol QueueCaching {
  func add(entries: [EntryLocator]) throws
  func remove(guids: [String]) throws
  
  /// Removes all queued entries.
  func removeAll() throws
  
  /// The user‘s queued entries, sorted by time queued.
  func queued() throws -> [Queued]
  
  /// Previously queued entries, limited to the most recent 25.
  func previous() throws -> [Queued]
  
  /// Returns `true` if the enty with `guid` is currently contained in the
  /// locally cached queue.
  func hasQueued(guid: EntryGUID) throws -> Bool
}

/// Coordinates the queue data structure, local persistence, and propagation of
/// change events regarding the user’s queue.
public protocol Queueing {

  /// Adds `entry` to the queue.
  func enqueue(
    entries: [Entry],
    enqueueCompletionBlock: ((_ error: Error?) -> Void)?) throws

  /// Removes `entry` from the queue.
  func dequeue(
    entry: Entry,
    dequeueCompletionBlock: ((_ error: Error?) -> Void)?)
  
  /// Fetches entries in the user‘s queue, populating the `queue` object of this
  /// `UserLibrary` instance.
  ///
  /// - Parameters:
  ///   - entriesBlock: The entries block:
  ///   - entriesError: An optional error, specific to entries.
  ///   - entries: All or some of the requested entries.
  ///
  ///   - fetchQueueCompletionBlock: The completion block:
  ///   - error: Optionally, an error for this operation.
  ///
  /// - Returns: Returns an executing `Operation`.
  @discardableResult func fetchQueue(
    entriesBlock: @escaping (_ queued: [Entry], _ entriesError: Error?) -> Void,
    fetchQueueCompletionBlock: @escaping (_ error: Error?) -> Void
  ) -> Operation

  // MARK: Queue
  
  // These synchronous methods are super fast (AP), but may not be consistent.
  // For example, to meaningfully use these, you must `fetchQueue` first.
  // https://en.wikipedia.org/wiki/CAP_theorem

  func contains(entry: Entry) -> Bool
  func next() -> Entry?
  func previous() -> Entry?
  
  var isEmpty: Bool { get }
}

// MARK: - Updating

public protocol Updating {
  
  /// Updates subscribed entries of subscribed feeds.
  ///
  /// - Parameters:
  ///   - updateComplete: The completion block to apply when done.
  ///   - newData: `true` if new data has been received.
  ///   - error: An if something went wrong.
  func update(updateComplete: @escaping (_ newData: Bool, _ error: Error?) -> Void)
  
}

// MARK: - Downloading

// TODO: Design Downloading API

// MARK: - Subscribing

/// A feed subscription.
public struct Subscription {
  public let url: FeedURL
  public let ts: Date?
  public let iTunes: ITunesItem?

  public init(url: FeedURL, iTunes: ITunesItem? = nil, ts: Date? = nil) {
    self.url = url
    self.iTunes = iTunes
    self.ts = ts
  }
  
  public init(feed: Feed) {
    self.url = feed.url
    self.iTunes = feed.iTunes
    self.ts = nil
  }
}

extension Subscription: Equatable {
  public static func ==(lhs: Subscription, rhs: Subscription) -> Bool {
    return lhs.url == rhs.url
  }
}

extension Subscription: Hashable {
  public var hashValue: Int {
    get { return url.hashValue }
  }
}

public protocol SubscriptionCaching {
  func add(subscriptions: [Subscription]) throws
  func remove(urls: [FeedURL]) throws

  func has(_ url: String) throws -> Bool

  func subscribed() throws -> [Subscription]
}

/// Mangages the user’s feed subscriptions.
public protocol Subscribing: Updating {
  
  /// Adds `subscriptions` to the user’s library.
  ///
  /// - Parameters:
  ///   - subscriptions: The subscriptions to add without timestamps.
  ///   - addComplete: An optional completion block:
  ///   - error: An error if something went wrong.
  func add(
    subscriptions: [Subscription],
    addComplete: ((_ error: Error?) -> Void)?) throws
  
  /// Unsubscribe from `urls`.
  ///
  /// - Parameters:
  ///   - urls: The URLs of feeds to unsubscribe from.
  ///   - unsubscribeComplete: An optional completion block:
  ///   - error: An error if something went wrong.
  func unsubscribe(
    from urls: [FeedURL],
    unsubscribeComplete: ((_ error: Error?) -> Void)?) throws

  /// Fetches the feeds currently subscribed.
  ///
  /// - Parameters:
  ///   - feedsBlock: A block applied with the resulting feeds:
  ///   - feeds: The subscribed feeds.
  ///   - feedsError: Optionally, an error related to feed fetching.
  ///
  ///   - feedsCompletionBlock: The completion block of this operation:
  ///   - error: An error if something went wrong with this operation.
  func fetchFeeds(
    feedsBlock: @escaping (_ feeds: [Feed], _ feedsError: Error?) -> Void,
    feedsCompletionBlock: @escaping (_ error: Error?) -> Void
  ) -> Operation
  
  /// Returns `true` if `url` is subscribed. You must `fetchFeeds` first, before
  /// relying on this.
  func has(subscription url: FeedURL) -> Bool
  
  /// Asynchronously reloads the in-memory cache of locally cached subscription
  /// URLs in the background, returning right away.
  func synchronize()
  
}

// MARK: - UserCaching

/// Caches user data, queue and subscriptions, locally.
public protocol UserCaching: QueueCaching, SubscriptionCaching {}

// MARK: - Syncing

/// Encapsulates `CKRecord` data to **avoid CloudKit dependency within
/// FeedKit** framework.
public struct RecordMetadata {
  let zoneName: String
  let recordName: String
  let changeTag: String?

  public init(zoneName: String, recordName: String, changeTag: String? = nil) {
    self.zoneName = zoneName
    self.recordName = recordName
    self.changeTag = changeTag
  }
}

extension RecordMetadata: Equatable {
  public static func ==(lhs: RecordMetadata, rhs: RecordMetadata) -> Bool {
    guard
      lhs.zoneName == rhs.zoneName,
      lhs.recordName == rhs.recordName,
      lhs.changeTag == rhs.changeTag
      else {
      return false
    }
    return true
  }
}

public typealias FeedURL = String

/// Enumerates data structures that are synchronized with iCloud.
public enum Synced {

  /// A queued entry that has been synchronized with the iCloud database with
  /// these properties: entry locator, the time the entry was added to the
  /// queue, and CloudKit record metadata.
  case entry(EntryLocator, Date, RecordMetadata)
  
  /// A synchronized feed subscription.
  case subscription(Subscription, RecordMetadata)
}

extension Synced: Equatable {
  public static func ==(lhs: Synced, rhs: Synced) -> Bool {
    switch (lhs, rhs) {
    case (.entry(let lloc, let lts, let lrec), .entry(let rloc, let rts, let rrec)):
      return lloc == rloc && lts == rts && lrec == rrec
    case (.subscription(let ls, let lrec), .subscription(let rs, let rrec)):
      return ls == rs && lrec == rrec
    case (.entry, _),
         (.subscription, _):
      return false
    }
  }
}

/// The user cache complies to this protocol to allow iCloud synchronization.
public protocol UserCacheSyncing: QueueCaching {
  
  /// Saves `synced`, synchronized user items, to the local cache.
  func add(synced: [Synced]) throws
  
  /// Removes records with `recordNames` from the local cache.
  func remove(recordNames: [String]) throws

  /// The queued entries, which not have been synced and are only locally
  /// cached, hence the name. Push these items with the next sync.
  func locallyQueued() throws -> [Queued]
  
  /// Returns subscriptions that haven’t been synchronized with iCloud yet, and
  /// are only cached locally so far. Push these items with the next sync.
  func locallySubscribed() throws -> [Subscription]

  /// CloudKit record names of abandoned records by record zone names. These are
  /// records not referenced by queued or previously queued entries, and not
  /// referenced by subscribed feeds. If this collection isn’t empty, items have
  /// been removed from the cache waiting to be synchronized. Include these in
  /// every push.
  func zombieRecords() throws -> [(String, String)]

  /// Deletes unrelated items from the cache. After records have been deleted in
  /// iCloud, and these have been synchronized with the local cache, entries
  /// and feeds might be left without links to their, now deleted, records. This
  /// method deletes those entries and feeds, it also deletes zombie records,
  /// not having links in the other direction. Run this after each sync.
  func deleteZombies() throws
  
  /// Deletes all queue data.
  func removeQueue() throws
  
  /// Deletes all library data.
  func removeLibrary() throws
}

// MARK: - Internal

func nop(_: Any) -> Void {}

/// The common super class of the search repository and the browse repository,
/// which for some reason still is misleadingly called feed repository (TODO).
/// This, of course, assumes one service host per repository.
public class RemoteRepository: NSObject {
  let queue: OperationQueue
  let probe: Reaching

  public init(queue: OperationQueue, probe: Reaching) {
    self.queue = queue
    self.probe = probe
  }

  deinit {
    queue.cancelAllOperations()
  }

  func reachable() -> Bool {
    let r = probe.reach()
    return r == .reachable || r == .cellular
  }

  private var forced = [String : Date]()

  private func forceable(_ uri: String) -> Bool {
    if let prev = forced[uri] {
      if prev.timeIntervalSinceNow < CacheTTL.short.seconds {
        return false
      }
    }
    forced[uri] = Date()
    return true

  }

  /// Return the momentary maximal age for cached items of a specific resource
  /// incorporating reachability and service status. This method's parameters
  /// are all optional.
  ///
  /// - Parameters:
  ///   - uri: The unique resource identifier.
  ///   - force: Force refreshing of cached items.
  ///   - status: The current status of the service, a tuple containing
  /// the latest error code and its timestamp.
  ///   - ttl: Override the default, `CacheTTL.Long`, to return.
  func timeToLive(
    _ uri: String? = nil,
    force: Bool = false,
    reachable: Bool = true,
    status: (Int, TimeInterval)? = nil,
    ttl: CacheTTL = CacheTTL.long
  ) -> CacheTTL {
    guard reachable else {
      return CacheTTL.forever
    }

    if force, let k = uri {
      if forceable(k) {
        return CacheTTL.none
      }
    }

    // TODO: Check if this catches timeouts too

    if let (code, ts) = status {
      let date = Date(timeIntervalSince1970: ts)
      if code != 0 && !FeedCache.stale(date, ttl: CacheTTL.short.seconds) {
        return CacheTTL.forever
      }
    }

    return ttl
  }
}

/// An abstract super class to be extended by concurrent FeedKit operations.
class FeedKitOperation: Operation {
  fileprivate var _executing: Bool = false

  // MARK: Operation

  override final var isExecuting: Bool {
    get { return _executing }
    set {
      guard newValue != _executing else {
        fatalError("FeedKitOperation: already executing")
      }
      willChangeValue(forKey: "isExecuting")
      _executing = newValue
      didChangeValue(forKey: "isExecuting")
    }
  }

  fileprivate var _finished: Bool = false

  override final var isFinished: Bool {
    get { return _finished }
    set {
      guard newValue != _finished else {
        // Just to be extra annoying.
        fatalError("FeedKitOperation: already finished")
      }
      willChangeValue(forKey: "isFinished")
      _finished = newValue
      didChangeValue(forKey: "isFinished")
    }
  }
}

/// A generic concurrent operation providing a URL session task. This abstract
/// class is to be extended.
class SessionTaskOperation: FeedKitOperation {

  /// If you know in advance that the remote service is currently not available,
  /// you might set this to `false` to be more effective.
  var reachable: Bool = true

  /// The maximal age, `CacheTTL.long`, of cached items.
  var ttl: CacheTTL = CacheTTL.long

  func post(name: NSNotification.Name) {
    DispatchQueue.main.async {
      NotificationCenter.default.post(name: name, object: self)
    }
  }

  final var task: URLSessionTask? {
    didSet {
      post(name: Notification.Name.FKRemoteRequest)
    }
  }

  override func cancel() {
    task?.cancel()
    super.cancel()
  }
}


