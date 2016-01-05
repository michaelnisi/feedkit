//
//  index.swift - API and common internal functions
//  FeedKit
//
//  Created by Michael Nisi on 17.07.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import Foundation

// MARK: Types

/// The sole error type of the FeedKit module.
public enum FeedKitError : ErrorType, Equatable {
  case Unknown
  case NIY
  case NotAString
  case General(message: String)
  case CancelledByUser
  case Missing(name: String)
  case NotAFeed
  case NotAnEntry
  case ServiceUnavailable(error: ErrorType)
  case FeedNotCached(urls: [String])
  case UnknownEnclosureType(type: String)
  case Multiple(errors: [ErrorType])
  case UnexpectedJSON
  case SQLFormatting
  case CacheFailure(error: ErrorType)
  case UnexpectedDeallocation
}

public func ==(lhs: FeedKitError, rhs: FeedKitError) -> Bool {
  return lhs._code == rhs._code
}

/// A set of images associated with a feed.
public struct FeedImages : Equatable {
  public let img: String?
  public let img100: String?
  public let img30: String?
  public let img60: String?
  public let img600: String?
}

public func ==(lhs: FeedImages, rhs: FeedImages) -> Bool {
  return (
    lhs.img == rhs.img &&
    lhs.img100 == rhs.img100 &&
    lhs.img30 == rhs.img30 &&
    lhs.img60 == rhs.img60 &&
    lhs.img600 == rhs.img600
  )
}

/// Mark objects as searchable.
public protocol Searchable : Equatable {}

/// Objects that need to be cached must implement this protocol.
public protocol Cachable {
  var ts: NSDate? { get }
  var url: String { get }
}

/// Feeds are the central object of this framework.
public struct Feed : Searchable, Cachable {
  public let author: String?
  public let guid: Int?
  public let images: FeedImages?
  public let link: String?
  public let summary: String?
  public let title: String
  public let ts: NSDate?
  public let uid: Int?
  public let updated: NSDate?
  public let url: String
}

extension Feed : CustomStringConvertible {
  public var description: String {
    return "Feed: \(title)"
  }
}

public func ==(lhs: Feed, rhs: Feed) -> Bool {
  return lhs.url == rhs.url
}

/// Enumerates possible media types enclosures are allowed to have.
public enum EnclosureType: Int {
  case AudioMPEG
  case AudioXMPEG
  case VideoXM4V
  // TODO: Add more types
  public init (withString type: String) throws {
    switch type {
    case "audio/mpeg": self = .AudioMPEG
    case "audio/x-mpeg": self = .AudioXMPEG
    case "video/x-m4v": self = .VideoXM4V
    default: throw FeedKitError.UnknownEnclosureType(type: type)
    }
  }
}

/// The infamous RSS enclosure tag is mapped to this structure.
public struct Enclosure: Equatable {
  let url: String
  let length: Int?
  let type: EnclosureType
}

extension Enclosure: CustomStringConvertible {
  public var description: String {
    return "Enclosure: \(url)"
  }
}

public func ==(lhs: Enclosure, rhs: Enclosure) -> Bool {
  return lhs.url == rhs.url
}

/// Feeds transport streams of entries.
public struct Entry: Searchable, Cachable {
  public let author: String?
  public let enclosure: Enclosure?
  public let duration: String?
  public let feed: String
  public let id: String
  public let img: String?
  public let link: String?
  public let subtitle: String?
  public let summary: String?
  public let title: String
  public let ts: NSDate?
  public let updated: NSDate?
  
  public var url: String {
    get { return feed }
  }
}

extension Entry: CustomStringConvertible {
  public var description: String {
    return "Entry: \(title)"
  }
}

public func ==(lhs: Entry, rhs: Entry) -> Bool {
  return lhs.id == rhs.id
}

/// Entry intervals are used to specify intervals of entries of a specific
/// feed.
public struct EntryInterval: Equatable {
  public let url: String
  public let since: NSDate
  
  /// Returns a new interval.
  /// - Parameter url: The URL of the feed.
  /// - Parameter since: A date in the past where the interval begins.
  /// - Returns: The newly created interval.
  public init(url: String, since: NSDate = NSDate(timeIntervalSince1970: 0)) {
    self.url = url
    self.since = since
  }
}

extension EntryInterval: CustomStringConvertible {
  public var description: String {
    return "EntryInterval: \(url) since: \(since)"
  }
}

public func ==(lhs: EntryInterval, rhs: EntryInterval) -> Bool {
  return lhs.url == rhs.url && lhs.since == rhs.since
}

/// A suggested search term, bearing the timestamp of when it was added
/// (to the cache) or updated.
public struct Suggestion: Searchable {
  public let term: String
  public var ts: NSDate? // if cached
}

extension Suggestion : CustomStringConvertible {
  public var description: String {
    return "Suggestion: \(term) \(ts)"
  }
}

public func ==(lhs: Suggestion, rhs: Suggestion) -> Bool {
  return lhs.term == rhs.term
}

/// Enumerates findable things hiding their type.
public enum Find : Searchable {
  case RecentSearch(Feed)
  case SuggestedTerm(Suggestion)
  case SuggestedEntry(Entry)
  case SuggestedFeed(Feed)
  
  /// The timestamp applied by the database.
  var ts: NSDate? {
    switch self {
    case .RecentSearch(let it): return it.ts
    case .SuggestedTerm(let it): return it.ts
    case .SuggestedEntry(let it): return it.ts
    case .SuggestedFeed(let it): return it.ts
    }
  }
}

public func ==(lhs: Find, rhs: Find) -> Bool {
  var lhsRes: Entry?
  var lhsSug: Suggestion?
  var lhsFed: Feed?
  
  switch lhs {
  case .SuggestedEntry(let res):
    lhsRes = res
  case .SuggestedTerm(let sug):
    lhsSug = sug
  case .SuggestedFeed(let fed):
    lhsFed = fed
  case .RecentSearch(let fed):
    lhsFed = fed
  }
  
  var rhsRes: Entry?
  var rhsSug: Suggestion?
  var rhsFed: Feed?
  
  switch rhs {
  case .SuggestedEntry(let res):
    rhsRes = res
  case .SuggestedTerm(let sug):
    rhsSug = sug
  case .SuggestedFeed(let fed):
    rhsFed = fed
  case .RecentSearch(let fed):
    rhsFed = fed
  }
  
  if lhsRes != nil && rhsRes != nil {
    return lhsRes == rhsRes
  } else if lhsSug != nil && rhsSug != nil {
    return lhsSug == rhsSug
  } else if lhsFed != nil && rhsFed != nil {
    return lhsFed == rhsFed
  }
  return false
}

// MARK: Caching

/// The time-to live settings for caching.
public struct CacheTTL {
  let short: NSTimeInterval
  let medium: NSTimeInterval
  let long: NSTimeInterval
}

/// A persistent cache for feeds and entries.
public protocol FeedCaching {
  
  /// The time to live settings of this cache.
  var ttl: CacheTTL { get }
  
  /// Update feeds in the cache. Feeds that are not cached yet are inserted.
  /// - Parameter feeds: The feeds to insert or update.
  func updateFeeds(feeds: [Feed]) throws
  
  /// Retrieve feeds from the cache identified by their URLs.
  /// - Parameter urls: An array of feed URL strings.
  /// - Returns: An array of feeds currently in the cache.
  func feedsWithURLs(urls: [String]) throws -> [Feed]

  /// Update entries in the cache inserting new ones.
  /// - Parameter entries: An array of entries to be cached.
  func updateEntries(entries:[Entry]) throws
  
  /// Retrieve entries within the specified intervals.
  /// - Parameter intervals: An array of time intervals between now and the past.
  /// - Returns: The matching array of entries currently cached.
  func entriesOfIntervals(intervals: [EntryInterval]) throws -> [Entry]

  /// Remove feeds and, respectively, their associated entries.
  /// - Parameter urls: The URL strings of the feeds to remove.
  func removeFeedsWithURLs(urls: [String]) throws
}

/// A persistent cache of things related to searching feeds and entries.
///
/// Note that this API, addtionally to empty arrays, uses optionals to be more 
/// expressive. Empty array means the item is cached but has no results; nil 
/// means the item has not been cached yet.
public protocol SearchCaching {
  var ttl: CacheTTL { get }

  func updateSuggestions(suggestions: [Suggestion], forTerm: String) throws
  func suggestionsForTerm(term: String, limit: Int) throws -> [Suggestion]?

  func updateFeeds(feeds: [Feed], forTerm: String) throws
  func feedsForTerm(term: String, limit: Int) throws -> [Feed]?
  
  func feedsMatchingTerm(term: String, limit: Int) throws -> [Feed]?
  func entriesMatchingTerm(term: String, limit: Int) throws -> [Entry]?
}

// MARK: API

public protocol Searching {
  
  /// Search for feeds by term.
  ///
  /// - Parameter term: The term to search for.
  /// - Parameter cb: The block to receive feeds.
  /// - Parameter searchCompletionBlock: The block to execute after the 
  ///   search is complete.
  func search(
    term: String,
    feedsBlock: (ErrorType?, [Feed]) -> Void,
    searchCompletionBlock: (ErrorType?) -> Void
  ) -> NSOperation
  
  /// Get lexicographical suggestions for a search term combining locally cached
  /// and remote data.
  ///
  /// - Parameter term: The search term.
  /// - Parameter perFindGroupBlock: The block to receive finds - called once 
  ///   per find group as enumerated in `Find`.
  /// - Parameter completionBlock: A block called when the operation has finished.
  func suggest(
    term: String,
    perFindGroupBlock: (ErrorType?, [Find]) -> Void,
    suggestCompletionBlock: (ErrorType?) -> Void
  ) -> NSOperation
}

public protocol Browsing {
  func feeds(urls: [String], cb: (ErrorType?, [Feed]) -> Void) -> NSOperation
  func entries(intervals: [EntryInterval], cb: (ErrorType?, [Entry]) -> Void) -> NSOperation
}

public protocol Subscribing {
  func subscribeURLs(urls: [String], cb: (ErrorType?, Feed?) -> Void) -> NSOperation
  func unsubscribeURLs(urls: [String], cb: (ErrorType?, Feed?) -> Void) -> NSOperation
  func subscribed(cb: (ErrorType?, [Feed]?) -> Void) -> NSOperation
  func unsubscribed(recent: Int, cb: (ErrorType?, [Feed]?) -> Void) -> NSOperation
}

public protocol Sequencing {
  var nextEntry: Entry { get }
  var previousEntry: Entry { get }
  var currentEntry: Entry { get }
  var entries: [Entry] { get }
  func setCurrentEntry(entry: Entry) throws
}

// MARK: Common functions and classes]

func nop(_: Any) -> Void {}

func createTimer(
  queue: dispatch_queue_t,
  time: Double,
  cb: dispatch_block_t) -> dispatch_source_t {
    
  let timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue)
  let delta = time * Double(NSEC_PER_SEC)
  let start = dispatch_time(DISPATCH_TIME_NOW, Int64(delta))
  dispatch_source_set_timer(timer, start, 0, 0)
  dispatch_source_set_event_handler(timer, cb)
  dispatch_resume(timer)
  return timer
}

/// A generic concurrent operation providing a task and an error property.
/// This abstract class is to be extended.
class SessionTaskOperation: NSOperation {
  final var task: NSURLSessionTask?
  
  private var _executing: Bool = false
  
  override final var executing: Bool {
    get { return _executing }
    set {
      guard newValue != _executing else {
        fatalError("SessionTaskOperation: already executing")
      }
      willChangeValueForKey("isExecuting")
      _executing = newValue
      didChangeValueForKey("isExecuting")
    }
  }
  
  private var _finished: Bool = false
  
  override final var finished: Bool {
    get { return _finished }
    set {
      guard newValue != _finished else {
        fatalError("SessionTaskOperation: already finished")
      }
      willChangeValueForKey("isFinished")
      _finished = newValue
      didChangeValueForKey("isFinished")
    }
  }
  
  override func cancel() {
    task?.cancel()
    super.cancel()
  }
}

// TODO: Remove temporary class

class TmpSessionTaskOperation: SessionTaskOperation {
  final var error: ErrorType?
  override func cancel() {
    error = FeedKitError.CancelledByUser
    super.cancel()
  }
}