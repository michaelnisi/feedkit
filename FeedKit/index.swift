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

// TODO: Free tests from network dependencies

// TODO: Rename probe parameter to probe

// MARK: Notifications

/// Posted when a remote request has been started.
public let FeedKitRemoteRequestNotification = "FeedKitRemoteRequest"

/// Posted when a remote response has been received.
public let FeedKitRemoteResponseNotification = "FeedKitRemoteResponse"

// MARK: Types

/// Enumerate all error types possibly thrown within the FeedKit framework.
public enum FeedKitError : Error, Equatable {
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
  case invalidEnclosure(reason: String)
  case invalidFeed(reason: String)
  case invalidSuggestion(reason: String)
  case offline
  case noForceApplied
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
  var ts: Date? { get }
  var url: String { get }
}

/// Feeds are the central object of this framework.
///
/// The initializer is inconvenient for a reason: **it shouldn't be used
/// directly**. Instead users are expected to obtain their feeds from the
/// repositories provided by this framework.
///
/// A feed is required to, at least, have a `title` and an `url`.
public struct Feed : Hashable, Cachable {
  public let author: String?
  public let iTunesGuid: Int?
  public let images: FeedImages?
  public let link: String?
  public let summary: String?
  public let title: String
  public let ts: Date?
  public let uid: Int?
  public let updated: Date?
  public let url: String
  
  public var hashValue: Int {
    get { return uid! }
  }
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
  case unknown
  case audioMPEG
  case audioXMPEG
  case videoXM4V
  case audioMP4
  case xm4A

  public init (withString type: String) {
    switch type {
    case "audio/mpeg": self = .audioMPEG
    case "audio/x-mpeg": self = .audioXMPEG
    case "video/x-m4v": self = .videoXM4V
    case "audio/mp4": self = .audioMP4
    case "audio/x-m4a": self = .xm4A
    default: self = .unknown
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
  public let duration: Int?
  public let feed: String
  public let feedTitle: String? // convenience
  public let guid: String
  public let img: String?
  public let link: String?
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
  public let since: Date
  public let guid: String?
  
  /// Initializes a newly created entry locator with the specified feed URL,
  /// time interval, and optional guid.
  ///
  /// This object might be used to locate multiple entries within an interval
  /// or to locate a single entry specifically using the guid.
  ///
  /// - parameter url: The URL of the feed.
  /// - parameter since: A date in the past when the interval begins.
  /// - parameter guid: An identifier to locate a specific entry.
  /// - returns: The newly created entry locator.
  public init(
    url: String,
    since: Date = Date(timeIntervalSince1970: 0),
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
  public var ts: Date? // if cached
}

extension Suggestion : CustomStringConvertible {
  public var description: String {
    return "Suggestion: \(term) \(ts)"
  }
}

public func ==(lhs: Suggestion, rhs: Suggestion) -> Bool {
  return lhs.term == rhs.term
}

/// Enumerates findable things hiding their type. The word 'suggested' is used
/// synonymously with 'found' here: a suggested feed is also a found feed, etc.
public enum Find : Equatable {
  case recentSearch(Feed)
  case suggestedTerm(Suggestion)
  case suggestedEntry(Entry)
  case suggestedFeed(Feed)

  /// The timestamp applied by the database.
  var ts: Date? {
    switch self {
    case .recentSearch(let it): return it.ts
    case .suggestedTerm(let it): return it.ts
    case .suggestedEntry(let it): return it.ts
    case .suggestedFeed(let it): return it.ts
    }
  }
}

public func ==(lhs: Find, rhs: Find) -> Bool {
  var lhsRes: Entry?
  var lhsSug: Suggestion?
  var lhsFed: Feed?

  switch lhs {
  case .suggestedEntry(let res):
    lhsRes = res
  case .suggestedTerm(let sug):
    lhsSug = sug
  case .suggestedFeed(let fed):
    lhsFed = fed
  case .recentSearch(let fed):
    lhsFed = fed
  }

  var rhsRes: Entry?
  var rhsSug: Suggestion?
  var rhsFed: Feed?

  switch rhs {
  case .suggestedEntry(let res):
    rhsRes = res
  case .suggestedTerm(let sug):
    rhsSug = sug
  case .suggestedFeed(let fed):
    rhsFed = fed
  case .recentSearch(let fed):
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

// MARK: FeedCaching

/// A persistent cache for feeds and entries.
public protocol FeedCaching {
  func updateFeeds(_ feeds: [Feed]) throws
  func feeds(_ urls: [String]) throws -> [Feed]

  func updateEntries(_ entries:[Entry]) throws
  func entries(_ locators: [EntryLocator]) throws -> [Entry]
  func entries(_ guids: [String]) throws -> [Entry]

  func remove(_ urls: [String]) throws
}

// MARK: SearchCaching

/// A persistent cache of things related to searching feeds and entries.
public protocol SearchCaching {
  func updateSuggestions(_ suggestions: [Suggestion], forTerm: String) throws
  func suggestionsForTerm(_ term: String, limit: Int) throws -> [Suggestion]?

  func updateFeeds(_ feeds: [Feed], forTerm: String) throws
  func feedsForTerm(_ term: String, limit: Int) throws -> [Feed]?
  func feedsMatchingTerm(_ term: String, limit: Int) throws -> [Feed]?
  func entriesMatchingTerm(_ term: String, limit: Int) throws -> [Entry]?
}

// MARK: Searching

/// The search API of the FeedKit framework.
public protocol Searching {
  @discardableResult func search(
    _ term: String,
    perFindGroupBlock: @escaping (Error?, [Find]) -> Void,
    searchCompletionBlock: @escaping (Error?) -> Void
  ) -> Operation

  @discardableResult func suggest(
    _ term: String,
    perFindGroupBlock: @escaping (Error?, [Find]) -> Void,
    suggestCompletionBlock: @escaping (Error?) -> Void
  ) -> Operation
}

// MARK: Browsing

// TODO: Introduce paging

/// An asynchronous API for accessing feeds and entries. Designed with data
/// aggregation from sources with diverse run times in mind, result blocks might
/// get called multiple times. Completion blocks are called once.
public protocol Browsing {
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
}

// MARK: Queueing

public protocol Queueing {
  // var next: Entry { get }
  // var previous: Entry { get }
  // var entry: Entry { get }

  @discardableResult func entries(
    _ entriesBlock: @escaping (Error?, [Entry]) -> Void,
    entriesCompletionBlock: @escaping (Error?) -> Void
  ) -> Operation

  func push(_ entry: Entry) throws
  func pop(_ entry: Entry) throws
  
  // TODO: func insert(entry: Entry) throws
}

// MARK: Internal

let FOREVER: TimeInterval = TimeInterval(Double.infinity)

func nop(_: Any) -> Void {}

/// The common super class of the search repository and the browse repository,
/// which for some reason still is misleadingly called feed repository (TODO).
/// This, of course, assumes one service host per repository.
open class RemoteRepository {
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
  /// - parameter uri: The unique resource identifier.
  /// - parameter force: Force refreshing of cached items.
  /// - parameter status: The current status of the service, a tuple containing
  /// the latest error code and its timestamp.
  /// - parameter ttl: Override the default, `CacheTTL.Long`, to return.
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
    
    if let (code, ts) = status {
      let date = Date(timeIntervalSince1970: ts)
      if code != 0 && !stale(date, ttl: CacheTTL.short.seconds) {
        return CacheTTL.forever
      }
    }
    
    return ttl
  }
}

/// A generic concurrent operation providing a URL session task. This abstract
/// class is to be extended.
class SessionTaskOperation: Operation {
  
  // MARK: Properties
  
  /// If you know in advance that the remote service is currently not available,
  /// you might set this to `false` to be more effective.
  var reachable: Bool = true
  
  /// The maximal age, `CacheTTL.Long`,  of cached items.
  var ttl: CacheTTL = CacheTTL.long
  
  final var task: URLSessionTask? {
    didSet {
      post(FeedKitRemoteRequestNotification)
    }
  }

  fileprivate var _executing: Bool = false
  
  // MARK: NSOperation

  override final var isExecuting: Bool {
    get { return _executing }
    set {
      guard newValue != _executing else {
        fatalError("SessionTaskOperation: already executing")
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
        fatalError("SessionTaskOperation: already finished")
      }
      willChangeValue(forKey: "isFinished")
      _finished = newValue
      didChangeValue(forKey: "isFinished")
    }
  }

  override func cancel() {
    task?.cancel()
    super.cancel()
  }
}
