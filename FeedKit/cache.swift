//
//  cache.swift - store and retrieve data
//  FeedKit
//
//  Created by Michael Nisi on 03.11.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import Foundation
import Skull

func stale(ts: NSDate, ttl: NSTimeInterval) -> Bool {
  return ts.timeIntervalSinceNow + ttl < 0
}

public final class Cache {
  let schema: String
  public let ttl: CacheTTL
  public var url: NSURL?
  
  let db: Skull
  let queue: dispatch_queue_t
  let sqlFormatter: SQLFormatter

  var noSuggestions = [String:NSDate]()
  var noSearch = [String:NSDate]()
  var feedIDsCache = NSCache()

  public init(schema: String, ttl: CacheTTL, url: NSURL?) throws {
    self.schema = schema
    self.ttl = ttl
    self.url = url
    
    // If we'd pass these, we could disjoint the cache into separate objects.
    self.db = Skull()
    let label = "com.michaelnisi.feedkit.cache"
    self.queue = dispatch_queue_create(label, DISPATCH_QUEUE_SERIAL)
    self.sqlFormatter = SQLFormatter()

    try open()
  }

  deinit {
    try! db.close()
  }
  
  func open() throws {
    var error: ErrorType?
    
    let db = self.db
    let schema = self.schema
    let maybeURL = self.url

    dispatch_sync(queue) {
      var exists = false
      do {
        if let url = maybeURL {
          let fm = NSFileManager.defaultManager()
          exists = fm.fileExistsAtPath(url.path!)
          try db.open(url)
        } else {
          try db.open()
        }
      } catch let er {
        return error = er
      }
      if !exists {
        do {
          let sql = try String(
            contentsOfFile: schema,
            encoding: NSUTF8StringEncoding
          )
          try db.exec(sql)
        } catch let er {
          return error = er
        }
      }
    }
    if let er = error {
      throw er
    }
  }

  func close() throws {
    try db.close()
  }

  public func flush() throws {
    try db.flush()
  }
  
  func feedIDForURL(url: String) throws -> Int {
    if let cachedFeedID = feedIDsCache.objectForKey(url) as? Int {
      return cachedFeedID
    }
    var er: ErrorType?
    var id: Int?
    let sql = SQLToSelectFeedIDFromURLView(url)
    try db.query(sql) { error, row in
      guard error == nil else {
        er = error!
        return 1
      }
      if let r = row {
        id = r["feedid"] as? Int
      }
      return 0
    }
    guard er == nil else { throw er! }
    guard id != nil else { throw FeedKitError.FeedNotCached(urls: [url]) }
    
    let feedID = id!
    feedIDsCache.setObject(feedID, forKey: url)
    return feedID
  }
  
  // TODO: Write test for feedsForSQL method
  
  func feedsForSQL(sql: String) throws -> [Feed]? {
    let db = self.db
    let fmt = self.sqlFormatter
    
    var er: ErrorType?
    var feeds = [Feed]()
    
    do {
      try db.query(sql) { skullError, row -> Int in
        guard skullError == nil else {
          er = skullError
          return 1
        }
        if let r = row {
          do {
            let result = try fmt.feedFromRow(r)
            feeds.append(result)
          } catch let error {
            er = error
            return 0
          }
        }
        return 0
      }
    } catch let error {
      er = error
    }
    if let error = er {
      throw error
    }
    return feeds.isEmpty ? nil : feeds
  }
}

// MARK: FeedCaching

extension Cache: FeedCaching {
  
  public func updateFeeds(feeds: [Feed]) throws {
    let fmt = self.sqlFormatter
    let db = self.db
    var error: ErrorType?
    dispatch_sync(queue) {
      do {
        let sql = try feeds.reduce([String]()) { acc, feed in
          do {
            let feedID = try self.feedIDForURL(feed.url)
            return acc + [fmt.SQLToUpdateFeed(feed, withID: feedID)]
          } catch FeedKitError.FeedNotCached {
            return acc + [fmt.SQLToInsertFeed(feed)]
          }
        }.joinWithSeparator("\n")
        try db.exec(sql)
      } catch let er {
        error = er
      }
    }
    if let er = error {
      throw er
    }
  }
  
  func feedIDsForURLs(urls: [String]) throws -> [String:Int]? {
    var result = [String:Int]()
    try urls.forEach { url in
      do {
        let feedID = try self.feedIDForURL(url)
        result[url] = feedID
      } catch FeedKitError.FeedNotCached {
        // No need to throw this, our user can ascertain uncached feeds from result.
      }
    }
    if result.isEmpty {
      return nil
    }
    return result
  }
  
  public func feedsWithURLs(urls: [String]) throws -> [Feed] {
    var feeds: [Feed]?
    var error: ErrorType?
    dispatch_sync(queue) {
      do {
        guard let dicts = try self.feedIDsForURLs(urls) else { return }
        let feedIDs = dicts.map { $0.1 }
        guard let sql = SQLToSelectFeedsByFeedIDs(feedIDs) else { return }
        feeds = try self.feedsForSQL(sql)
      } catch let er {
        return error = er
      }
    }
    if let er = error {
      throw er
    }
    return feeds ?? [Feed]()
  }
  
  func hasURL (url: String) -> Bool {
    do {
      try feedIDForURL(url)
    } catch {
      return false
    }
    return true
  }
  
  public func updateEntries(entries: [Entry]) throws {
    let fmt = self.sqlFormatter
    let db = self.db
    var error: ErrorType?
    dispatch_sync(queue) {
      var unidentified = [String]()
      do {
        let sql = entries.reduce([String]()) { acc, entry in
          var feedID: Int?
          do {
            feedID = try self.feedIDForURL(entry.feed)
          } catch {
            let url = entry.feed
            if !unidentified.contains(url) {
              unidentified.append(url)
            }
            return acc
          }
          return acc + [fmt.SQLToInsertEntry(entry, forFeedID: feedID!)]
        }.joinWithSeparator("\n")
        if sql != "\n" {
          try db.exec(sql)
        }
        if !unidentified.isEmpty {
          throw FeedKitError.FeedNotCached(urls: unidentified)
        }
      } catch let er {
        error = er
      }
    }
    if let er = error {
      throw er
    }
  }
  
  func entriesForSQL(sql: String) throws -> [Entry]? {
    let db = self.db
    let df = self.sqlFormatter
    
    var er: ErrorType?
    var entries = [Entry]()
    
    do {
      try db.query(sql) { skullError, row -> Int in
        guard skullError == nil else {
          er = skullError
          return 1
        }
        if let r = row {
          do {
            let result = try df.entryFromRow(r)
            entries.append(result)
          } catch let error {
            er = error
            return 0
          }
        }
        return 0
      }
    } catch let error {
      er = error
    }
    if let error = er {
      throw error
    }
    return entries.isEmpty ? nil : entries
  }
  
  public func entriesOfIntervals(intervals: [EntryInterval]) throws -> [Entry] {
    var entries: [Entry]?
    var error: ErrorType?
    let fmt = self.sqlFormatter
    dispatch_sync(queue) {
      do {
        let urls = intervals.map { $0.url }
        guard let feedIDsByURLs = try self.feedIDsForURLs(urls) else {
          return
        }
        let specs = intervals.reduce([(Int, NSDate)]()) { acc, interval in
          let url = interval.url
          let since = interval.since
          if let feedID = feedIDsByURLs[url] {
            return acc + [(feedID, since)]
          } else {
            return acc
          }
        }
        guard let sql = fmt.SQLToSelectEntriesByIntervals(specs) else {
          return
        }
        entries = try self.entriesForSQL(sql)
      } catch let er {
        return error = er
      }
    }
    if let er = error {
      throw er
    }
    return entries ?? [Entry]()
  }
  
  public func removeFeedsWithURLs(urls: [String]) throws {
    let db = self.db
    let feedIDsCache = self.feedIDsCache
    var error: ErrorType?
    dispatch_sync(queue) {
      do {
        guard let dicts = try self.feedIDsForURLs(urls) else { return }
        let feedIDs = dicts.map { $0.1 }
        guard let sql = SQLToRemoveFeedsWithFeedIDs(feedIDs) else {
          throw FeedKitError.SQLFormatting
        }
        try db.exec(sql)
        urls.forEach {
          feedIDsCache.removeObjectForKey($0)
        }
      } catch let er {
        error = er
      }
    }
    if let er = error {
      throw er
    }
  }
}

// MARK: SearchCaching

/// The `subcached` function scans the provided dictionary, containing
/// timestamps by terms, backwards for a term or its predecessing substrings.
/// If a matching term is found, it is returned in a tuple with its timestamp.
///
/// - Parameter term: The term to look for.
/// - Parameter dict: A dictionary of timestamps by terms.
/// - Returns: A tuple containing the matching term and a timestamp, or, if no
/// matches were found, `nil`.
func subcached(term: String, dict: [String:NSDate]) -> (String, NSDate)? {
  if let ts = dict[term] {
    return (term, ts)
  } else {
    if !term.isEmpty {
      let pre = term.endIndex.predecessor()
      return subcached(term.substringToIndex(pre), dict: dict)
    }
    return nil
  }
}

extension Cache: SearchCaching {
  
  public func updateFeeds(feeds: [Feed], forTerm term: String) throws {
    if feeds.isEmpty {
      // We keep the feeds.
      noSearch[term] = NSDate()
    } else {
      try updateFeeds(feeds)
      noSearch[term] = nil
    }
    
    let db = self.db
    var error: ErrorType?
    
    // To stay synchronized with the remote state, we, before inserting 
    // feed identifiers, firstly delete all searches for this term.
    
    dispatch_sync(queue) {
      do {
        let delete = SQLToDeleteSearchForTerm(term)
        let insert = try feeds.reduce([String]()) { acc, feed in
          let feedID = try feed.uid ?? self.feedIDForURL(feed.url)
          return acc + [SQLToInsertFeedID(feedID, forTerm: term)]
        }.joinWithSeparator("\n")
        let sql = [
          "BEGIN;",
          delete,
          insert,
          "COMMIT;"
        ].joinWithSeparator("\n")
        try db.exec(sql)
      } catch let er {
        error = er
      }
    }
    if let er = error {
      throw er
    }
  }

  public func feedsForTerm(term: String, limit: Int) throws -> [Feed]? {
    var feeds: [Feed]?
    var error: ErrorType?
    let ttl = self.ttl
    let noSearch = self.noSearch

    dispatch_sync(queue) { [unowned self] in
      if let ts = noSearch[term] {
        if stale(ts, ttl: ttl.medium) {
          self.noSearch[term] = nil
          return
        } else {
          return feeds = []
        }
      }
      let sql = SQLToSelectFeedsByTerm(term, limit: limit)
      do {
        feeds = try self.feedsForSQL(sql)
      } catch let er {
        error = er
      }
    }
    if let er = error {
      throw er
    }
    return feeds
  }

  public func feedsMatchingTerm(term: String, limit: Int) throws -> [Feed]? {
    var feeds: [Feed]?
    var error: ErrorType?
    
    dispatch_sync(queue) {
      let sql = SQLToSelectFeedsMatchingTerm(term, limit: limit)
      do {
        feeds = try self.feedsForSQL(sql)
      } catch let er {
        error = er
      }
    }
    if let er = error {
      throw er
    }
    return feeds
  }
  
  public func entriesMatchingTerm(term: String, limit: Int) throws -> [Entry]? {
    var entries: [Entry]?
    var error: ErrorType?
    
    dispatch_sync(queue) {
      let sql = SQLToSelectEntriesMatchingTerm(term, limit: limit)
      do {
        entries = try self.entriesForSQL(sql)
      } catch let er {
        error = er
      }
    }
    if let er = error {
      throw er
    }
    return entries
  }
  
  public func updateSuggestions(suggestions: [Suggestion], forTerm term: String) throws {
    let db = self.db
    
    guard !suggestions.isEmpty else {
      noSuggestions[term] = NSDate()
      var er: ErrorType?
      dispatch_sync(queue) {
        let sql = SQLToDeleteSuggestionsMatchingTerm(term)
        do {
          try db.exec(sql)
        } catch let error {
          er = error
        }
      }
      if let error = er {
        throw error
      }
      return
    }
    
    if let (cachedTerm, _) = subcached(term, dict: noSuggestions) {
      noSuggestions[cachedTerm] = nil
    }

    var er: ErrorType?
    dispatch_sync(queue, {
      do {
        let sql = [
          "BEGIN;",
          suggestions.map {
            SQLToInsertSuggestionForTerm($0.term)
          }.joinWithSeparator("\n"),
          "COMMIT;"
        ].joinWithSeparator("\n")
        try db.exec(sql)
      } catch let error {
        er = error
      }
    })
    if let error = er {
      throw error
    }
  }

  func suggestionsForSQL(sql: String) throws -> [Suggestion]? {
    let db = self.db
    let df = self.sqlFormatter
    var optErr: ErrorType?
    var sugs = [Suggestion]()
    dispatch_sync(queue, {
      do {
        try db.query(sql) { er, row -> Int in
          if let r = row {
            do {
              let sug = try df.suggestionFromRow(r)
              sugs.append(sug)
            } catch let error {
              optErr = error
            }
          }
          return 0
        }
      } catch let error {
        optErr = error
      }
    })
    if let error = optErr {
      throw error
    }
    return sugs.isEmpty ? nil : sugs
  }

  /// Retrieve cached suggestions matching a term from the database. If no 
  /// suggestions are cached `nil` is returned. Having no suggestions can also
  /// be cached and is expressed by returning an empty array.
  public func suggestionsForTerm(term: String, limit: Int) throws -> [Suggestion]? {
    let ttl = self.ttl
    if let (cachedTerm, ts) = subcached(term, dict: noSuggestions) {
      if stale(ts, ttl: ttl.long) {
        noSuggestions[cachedTerm] = nil
        return nil
      } else {
        return []
      }
    }
    let sql = SQLToSelectSuggestionsForTerm(term, limit: limit)
    return try suggestionsForSQL(sql)
  }
}
