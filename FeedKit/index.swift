//
//  index.swift - API and common internal functions
//  FeedKit
//
//  Created by Michael Nisi on 17.07.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import Foundation

// MARK: Types

/// Enumerate all error types possibly thrown within the FeedKit framework.
public enum FeedKitError : ErrorType, Equatable {
  case Unknown
  case NIY
  case NotAString
  case General(message: String)
  case CancelledByUser
  case NotAFeed
  case NotAnEntry
  case ServiceUnavailable(error: ErrorType)
  case FeedNotCached(urls: [String])
  case UnknownEnclosureType(type: String)
  case Multiple(errors: [ErrorType])
  case UnexpectedJSON
  case SQLFormatting
  case CacheFailure(error: ErrorType)
  case InvalidSearchTerm(term: String)
  case InvalidEntry(reason: String)
  case InvalidEnclosure(reason: String)
  case InvalidFeed(reason: String)
  case InvalidSuggestion(reason: String)
  case Offline
  case NoForceApplied
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

/// Cachable objects, currently feeds and entries, must adopt this protocol,
/// which requires a globally unique resource locator (url) and a timestamp (ts).
public protocol Cachable {
  var ts: NSDate? { get }
  var url: String { get }
}

/// Feeds are the central object of this framework.
///
/// The initializer is inconvenient for a reason: **it shouldn't be used
/// directly**. Instead users are expected to obtain their feeds from the
/// repositories provided by this framework.
///
/// A feed is required to, at least, have a `title` and a `url`.
public struct Feed : Equatable, Cachable {
  public let author: String?
  public let iTunesGuid: Int?
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

/// Feeds are identified, thus compared, by their feed URLs.
public func ==(lhs: Feed, rhs: Feed) -> Bool {
  return lhs.url == rhs.url
}

/// Enumerate supported enclosure media types. Note that unknown is legit here.
public enum EnclosureType : Int {
  case Unknown
  case AudioMPEG
  case AudioXMPEG
  case VideoXM4V
  case AudioMP4
  case XM4A

  public init (withString type: String) {
    switch type {
    case "audio/mpeg": self = .AudioMPEG
    case "audio/x-mpeg": self = .AudioXMPEG
    case "video/x-m4v": self = .VideoXM4V
    case "audio/mp4": self = .AudioMP4
    case "audio/x-m4a": self = .XM4A
    default: self = .Unknown
    }
  }
}

/// The infamous RSS enclosure tag is mapped to this structure.
public struct Enclosure : Equatable {
  let url: String
  let length: Int?
  let type: EnclosureType
}

extension Enclosure : CustomStringConvertible {
  public var description: String {
    return "Enclosure: \(url)"
  }
}

public func ==(lhs: Enclosure, rhs: Enclosure) -> Bool {
  return lhs.url == rhs.url
}

/// RSS item or Atom entry. In this domain we speak of `entry`.
public struct Entry : Equatable {
  public let author: String?
  public let enclosure: Enclosure?
  public let duration: String?
  public let feed: String
  public let feedTitle: String? // convenience
  public let guid: String
  public let id: String
  public let img: String?
  public let link: String?
  public let subtitle: String?
  public let summary: String?
  public let title: String
  public let ts: NSDate?
  public let updated: NSDate
}

extension Entry : Cachable {
  public var url: String {
    get { return feed }
  }
}

extension Entry : CustomStringConvertible {
  public var description: String {
    return "Entry: \(title)"
  }
}

public func ==(lhs: Entry, rhs: Entry) -> Bool {
  return lhs.guid == rhs.guid
}

/// Entry locators identify a specific entry using the GUID, or skirt intervals
/// of entries from a specific feed.
public struct EntryLocator : Equatable {
  public let url: String
  public let since: NSDate
  public let guid: String?
  
  /// Initializes a newly created entry locator with the specified feed URL,
  /// time interval, and optional guid.
  ///
  /// This object might be used to locate multiple entries within an interval
  /// or to locate a single entry specifically using the guid.
  ///
  /// - Parameter url: The URL of the feed.
  /// - Parameter since: A date in the past when the interval begins.
  /// - Parameter guid: An identifier to locate a specific entry.
  /// - Returns: The newly created entry locator.
  public init(
    url: String,
    since: NSDate = NSDate(timeIntervalSince1970: 0),
    guid: String? = nil
  ) {
    self.url = url
    self.since = since
    self.guid = guid
  }
}

extension EntryLocator : CustomStringConvertible {
  public var description: String {
    return "EntryLocator: \(url) since: \(since) guid: \(guid)"
  }
}

public func ==(lhs: EntryLocator, rhs: EntryLocator) -> Bool {
  return lhs.url == rhs.url && lhs.since == rhs.since && lhs.guid == rhs.guid
}

/// A suggested search term, bearing the timestamp of when it was added
/// (to the cache) or updated.
public struct Suggestion : Equatable {
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
public enum Find : Equatable {
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

/// Enumerate reasonable time-to-live intervals.
///
/// - None: Zero seconds.
/// - Short: One hour.
/// - Medium: Eight hours.
/// - Long: 24 hours.
/// - Forever: Infinity.
public enum CacheTTL {
  case None
  case Short
  case Medium
  case Long
  case Forever
  
  /// The time-to-live interval in seconds.
  var seconds: NSTimeInterval {
    get {
      switch self {
      case .None: return 0
      case .Short: return 3600
      case .Medium: return 28800
      case .Long: return 86400
      case .Forever: return Double.infinity
      }
    }
  }
}

// MARK: FeedCaching

/// A persistent cache for feeds and entries.
public protocol FeedCaching {
  func updateFeeds(feeds: [Feed]) throws
  func feeds(urls: [String]) throws -> [Feed]

  func updateEntries(entries:[Entry]) throws
  func entries(locators: [EntryLocator]) throws -> [Entry]
  func entries(guids: [String]) throws -> [Entry]

  func remove(urls: [String]) throws
}

// MARK: SearchCaching

/// A persistent cache of things related to searching feeds and entries.
public protocol SearchCaching {
  func updateSuggestions(suggestions: [Suggestion], forTerm: String) throws
  func suggestionsForTerm(term: String, limit: Int) throws -> [Suggestion]?

  func updateFeeds(feeds: [Feed], forTerm: String) throws
  func feedsForTerm(term: String, limit: Int) throws -> [Feed]?
  func feedsMatchingTerm(term: String, limit: Int) throws -> [Feed]?
  func entriesMatchingTerm(term: String, limit: Int) throws -> [Entry]?
}

// MARK: Searching

/// The search API of the FeedKit framework.
public protocol Searching {
  func search(
    term: String,
    perFindGroupBlock: (ErrorType?, [Find]) -> Void,
    searchCompletionBlock: (ErrorType?) -> Void
  ) -> NSOperation

  func suggest(
    term: String,
    perFindGroupBlock: (ErrorType?, [Find]) -> Void,
    suggestCompletionBlock: (ErrorType?) -> Void
  ) -> NSOperation
}

// MARK: Browsing

/// An asynchronous API for accessing feeds and entries. Designed with data
/// aggregation from sources with diverse run times in mind, result blocks might
/// get called multiple times. Completion blocks are called once.
public protocol Browsing {
  func feeds(
    urls: [String],
    feedsBlock: (ErrorType?, [Feed]) -> Void,
    feedsCompletionBlock: (ErrorType?) -> Void
  ) -> NSOperation
  
  func entries(
    locators: [EntryLocator],
    entriesBlock: (ErrorType?, [Entry]) -> Void,
    entriesCompletionBlock: (ErrorType?) -> Void
  ) -> NSOperation
  
  func entries(
    locators: [EntryLocator],
    force: Bool,
    entriesBlock: (ErrorType?, [Entry]) -> Void,
    entriesCompletionBlock: (ErrorType?) -> Void
  ) -> NSOperation
}

// MARK: Queueing

public protocol Queueing {
  // var next: Entry { get }
  // var previous: Entry { get }
  // var entry: Entry { get }

  func entries(
    entriesBlock: (ErrorType?, [Entry]) -> Void,
    entriesCompletionBlock: (ErrorType?) -> Void
  ) -> NSOperation

  func push(entry: Entry) throws
  func pop(entry: Entry) throws
}

// MARK: Internal

let FOREVER: NSTimeInterval = NSTimeInterval(Double.infinity)

func nop(_: Any) -> Void {}

/// Create and return dispatch source with a timer set up to fire on the
/// specified queue, in an interval specified in seconds.
///
/// - Parameter queue: The dispatch queue to use.
/// - Parameter seconds: The time for this timer to run in seconds.
/// - Parameter timeoutBlock: The block getting dispatched to the provided queue
/// after the given time.
/// - Returns: A dispatch source with a timer.
public func createTimer(
  queue: dispatch_queue_t,
  seconds: NSTimeInterval,
  timeoutBlock: dispatch_block_t
) -> dispatch_source_t {
  let timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue)
  let delta = seconds * NSTimeInterval(NSEC_PER_SEC)
  let start = dispatch_time(DISPATCH_TIME_NOW, Int64(delta))
  dispatch_source_set_timer(timer, start, 0, 0)
  dispatch_source_set_event_handler(timer, timeoutBlock)
  dispatch_resume(timer)
  return timer
}

/// A generic concurrent operation providing a URL session task and an error
/// property. This abstract class exists to be extended.
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
        return print("warning: SessionTaskOperation: already finished")
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
