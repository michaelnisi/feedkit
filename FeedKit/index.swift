//
//  index.swift - API and common internal functions
//  FeedKit
//
//  Created by Michael Nisi on 17.07.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import Foundation

// MARK: Types

public enum FeedKitError: ErrorType, Equatable {
  case Unknown
  case NIY
  case NotAString
  case General(message: String)
  case CancelledByUser
  case Missing(name: String)
  case NotAFeed
  case NotAnEntry
  case ServiceUnavailable(error: ErrorType, urls: [String])
  case FeedNotCached(urls: [String])
  case UnknownEnclosureType(type: String)
  case Multiple(errors: [ErrorType])
  case UnexpectedJSON
  case SQLFormatting
  case CacheFailure(error: ErrorType)
}

public func == (lhs: FeedKitError, rhs: FeedKitError) -> Bool {
  return lhs._code == rhs._code
}

public struct FeedImages: Equatable {
  public let img: String?
  public let img100: String?
  public let img30: String?
  public let img60: String?
  public let img600: String?
}

public func == (lhs: FeedImages, rhs: FeedImages) -> Bool {
  return (
    lhs.img == rhs.img &&
    lhs.img100 == rhs.img100 &&
    lhs.img30 == rhs.img30 &&
    lhs.img60 == rhs.img60 &&
    lhs.img600 == rhs.img600
  )
}

public protocol Searchable: Equatable {}

public protocol Cachable {
  var ts: NSDate? { get }
  var url: String { get }
}

public struct Feed: Searchable, Cachable {
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

extension Feed: CustomStringConvertible {
  public var description: String {
    return "Feed: \(title) @ \(url)"
  }
}

public func == (lhs: Feed, rhs: Feed) -> Bool {
  return lhs.url == rhs.url
}

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

public func == (lhs: Enclosure, rhs: Enclosure) -> Bool {
  return lhs.url == rhs.url
}

public struct Entry: Equatable, Cachable {
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

public func == (lhs: Entry, rhs: Entry) -> Bool {
  return lhs.id == rhs.id
}

public struct EntryInterval: Equatable {
  public let url: String
  public let since: NSDate
  
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

public func == (lhs: EntryInterval, rhs: EntryInterval) -> Bool {
  return lhs.url == rhs.url && lhs.since == rhs.since
}

public struct Suggestion: Searchable {
  public let term: String
  public var ts: NSDate? // if cached
}

extension Suggestion: CustomStringConvertible {
  public var description: String {
    return "Suggestion: \(term) \(ts)"
  }
}

public func == (lhs: Suggestion, rhs: Suggestion) -> Bool {
  return lhs.term == rhs.term
}

public enum SearchItem: Equatable {
  case Sug(Suggestion)
  case Res(Feed)
  case Fed(Feed)
  var ts: NSDate? {
    switch self {
    case .Res(let it): return it.ts
    case .Sug(let it): return it.ts
    case .Fed(let it): return it.ts
    }
  }
}

public func == (lhs: SearchItem, rhs: SearchItem) -> Bool {
  var lhsRes: Feed?
  var lhsSug: Suggestion?
  var lhsFed: Feed?
  switch lhs {
  case .Res(let res):
    lhsRes = res
  case .Sug(let sug):
    lhsSug = sug
  case .Fed(let fed):
    lhsFed = fed
  }
  var rhsRes: Feed?
  var rhsSug: Suggestion?
  var rhsFed: Feed?
  switch rhs {
  case .Res(let res):
    rhsRes = res
  case .Sug(let sug):
    rhsSug = sug
  case .Fed(let fed):
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

public struct CacheTTL {
  let short: NSTimeInterval
  let medium: NSTimeInterval
  let long: NSTimeInterval
}

public protocol FeedCaching {
  var ttl: CacheTTL { get }
  
  func updateFeeds(feeds:[Feed]) throws
  func feedsWithURLs(urls: [String]) throws -> [Feed]?

  func updateEntries(entries:[Entry]) throws
  func entriesOfIntervals(intervals: [EntryInterval]) throws -> [Entry]?

  func removeFeedsWithURLs(urls: [String]) throws
}

public protocol SearchCaching {
  var ttl: CacheTTL { get }

  func updateSuggestions(suggestions: [Suggestion], forTerm: String) throws
  func suggestionsForTerm(term: String) throws -> [Suggestion]?

  func updateFeeds(feeds: [Feed], forTerm: String) throws
  func feedsForTerm(term: String) throws -> [Feed]?
  func feedsMatchingTerm(term: String) throws -> [Feed]?

  func entriesMatchingTerm(term: String) throws -> [Entry]?
}

public protocol ImageCaching {
  
}

// MARK: Repositories

public protocol Browsing {
  func feeds(urls: [String], cb:(ErrorType?, [Feed]) -> Void) -> NSOperation
  func entries(intervals: [EntryInterval], cb:(ErrorType?, [Entry]) -> Void) -> NSOperation
}

public protocol Subscribing {
  func update() -> NSOperation
  func subscribeToFeedWithURL(url: String, cb:(ErrorType?, Feed?) -> Void) -> NSOperation
  func unsubscribeFromFeedWithURL(url: String, cb:(ErrorType?, Feed?) -> Void) -> NSOperation
}

public protocol Searching {

}

public protocol ImageLibrary {

}

// MARK: Common functions

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