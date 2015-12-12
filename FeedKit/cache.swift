//
//  cache.swift - store and retrieve data
//  FeedKit
//
//  Created by Michael Nisi on 03.11.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import Foundation
import Skull

// TODO: Understand this recursive function

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

func stale(ts: NSDate, ttl: NSTimeInterval) -> Bool {
  return ts.timeIntervalSinceNow + ttl < 0
}

public class Cache {
  let schema: String
  public let ttl: CacheTTL
  public var url: NSURL?
  
  let db: Skull
  let queue: dispatch_queue_t
  let sqlFormatter: SQLFormatter

  var noSuggestions = [String:NSDate]()
  var noResults = [String:NSDate]()
  var feedIDsCache = NSCache()

  public init (schema: String, ttl: CacheTTL, url: NSURL?) throws {
    self.schema = schema
    self.ttl = ttl
    self.url = url
    
    self.db = Skull()
    self.queue = dispatch_queue_create("com.michaelnisi.feedkit.cache", DISPATCH_QUEUE_SERIAL)
    self.sqlFormatter = SQLFormatter()

    try open()
  }

  deinit {
    try! db.close()
  }
  
  func open () throws {
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

  func close () throws {
    try db.close()
  }

  public func flush () throws {
    try db.flush()
  }
  
  func feedIDForURL (url: String) throws -> Int {
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
}

// MARK: FeedCaching

extension Cache: FeedCaching {
  
  public func updateFeeds (feeds: [Feed]) throws {
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
  
  func feedIDsForURLs (urls: [String]) throws -> [String:Int]? {
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
  
  public func feedsWithURLs (urls: [String]) throws -> [Feed]? {
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
    return feeds
  }
  
  func hasURL (url: String) -> Bool {
    do {
      try feedIDForURL(url)
    } catch {
      return false
    }
    return true
  }
  
  public func updateEntries (entries: [Entry]) throws {
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
  
  func entriesForSQL (sql: String) throws -> [Entry]? {
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
  
  public func entriesOfIntervals (intervals: [EntryInterval]) throws -> [Entry]? {
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
    return entries
  }
  
  public func removeFeedsWithURLs (urls: [String]) throws {
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

extension Cache: SearchCaching {
  public func updateFeeds(feeds: [Feed], forTerm term: String) throws {
    let db = self.db
    if feeds.count == 0 {
      noResults[term] = NSDate()
      var error: ErrorType?
      dispatch_sync(queue, {
        let sql = [
          "DELETE FROM feed ",
          "WHERE guid = (",
          "SELECT * FROM search ",
          "WHERE term = \(term));"
        ].joinWithSeparator("")
        do {
          try db.exec(sql)
        } catch let er {
          error = er
        }
      })
      if let er = error {
        throw er
      }
    }
    if let (cachedTerm, _) = subcached(term, dict: noResults) {
      noResults[cachedTerm] = nil
    }
    if let (cachedTerm, _) = subcached(term, dict: noSuggestions) {
      noSuggestions[cachedTerm] = nil
    }

    var errors = [ErrorType]()
    let df = self.sqlFormatter
    dispatch_sync(queue, {
      do {
        try db.exec("BEGIN IMMEDIATE;")
      } catch let er {
        errors.append(er)
      }
      // TODO: Make this more elegant by using reduce
      for feed in feeds {
        let guid = feed.guid
        let sql = [
          "INSERT OR REPLACE INTO search(guid, term) ",
          "VALUES(\(guid), '\(term)');",
          df.SQLToInsertFeed(feed)
        ].joinWithSeparator("")
        do {
          try  db.exec(sql)
        } catch let er {
          errors.append(er)
        }
      }
      do {
        try db.exec("COMMIT;")
      } catch let er {
        errors.append(er)
      }
    })
    if errors.count > 0 {
      throw FeedKitError.Unknown
    }
  }
  
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

  public func feedsForTerm(term: String) throws -> [Feed]? {
    let ttl = self.ttl
    if let (cachedTerm, ts) = subcached(term, dict: noResults) {
      if stale(ts, ttl: ttl.medium) {
        noResults[cachedTerm] = nil
        return nil
      } else {
        return []
      }
    }
    return try feedsForSQL([
      "SELECT * FROM feed WHERE guid IN (",
      "SELECT guid FROM search_fts ",
      "WHERE term MATCH '\(term)') ",
      "ORDER BY ts DESC ",
      "LIMIT 50;"
    ].joinWithSeparator(""))
  }

  public func feedsMatchingTerm(term: String) throws -> [Feed]? {
    return try feedsForSQL([
      "SELECT * FROM feed WHERE guid IN (",
      "SELECT guid FROM feed_fts ",
      "WHERE feed_fts MATCH '\(term)*') ",
      "ORDER BY ts DESC ",
      "LIMIT 3;"
    ].joinWithSeparator(""))
  }
  
  public func entriesMatchingTerm(term: String) throws -> [Entry]? {
    throw FeedKitError.NIY
  }

  public func updateSuggestions(suggestions: [Suggestion], forTerm term: String) throws {
    let db = self.db
    if suggestions.count == 0 {
      noSuggestions[term] = NSDate()
      var er: ErrorType?
      dispatch_sync(queue, {
        let sql = [
          "DELETE FROM sug ",
          "WHERE rowid = (",
          "SELECT rowid FROM sug_fts WHERE term MATCH '\(term)*');"
        ].joinWithSeparator("")
        do {
          try db.exec(sql)
        } catch let error {
          er = error
        }
      })
      if let error = er {
        throw error
      }
    }
    if let (cachedTerm, _) = subcached(term, dict: noSuggestions) {
      noSuggestions[cachedTerm] = nil
    }
    var errors = [ErrorType]()
    dispatch_sync(queue, {
      do {
        try db.exec("BEGIN IMMEDIATE;")
        for suggestion in suggestions {
          let term = suggestion.term
          let sql = [
            "INSERT OR REPLACE INTO sug(rowid, term) ",
            "VALUES((SELECT rowid FROM sug ",
            "WHERE term = '\(term)'), '\(term)');"
            ].joinWithSeparator("")
          try db.exec(sql)
        }
        try db.exec("COMMIT;")
      } catch let er {
        errors.append(er)
      }
    })
    if !errors.isEmpty {
      throw FeedKitError.General(message: "cache: multiple errors occured")
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

  public func suggestionsForTerm(term: String) throws -> [Suggestion]? {
    let ttl = self.ttl
    if let (cachedTerm, ts) = subcached(term, dict: noSuggestions) {
      if stale(ts, ttl: ttl.medium) {
        noSuggestions[cachedTerm] = nil
        return nil
      } else {
        return []
      }
    }
    return try suggestionsForSQL([
      "SELECT * FROM sug_fts ",
      "WHERE term MATCH '\(term)*' ",
      "ORDER BY ts DESC ",
      "LIMIT 5;"
    ].joinWithSeparator(""))
  }
}
