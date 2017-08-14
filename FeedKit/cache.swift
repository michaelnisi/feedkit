//
//  cache.swift - store and retrieve data
//  FeedKit
//
//  Created by Michael Nisi on 03.11.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import Foundation
import Skull
import os.log

// TODO: Harmonize implementation and style

// MARK: - Logging

@available(iOS 10.0, *)
fileprivate let log = OSLog(subsystem: "ink.codes.feedkit", category: "cache")

// MARK: - SQLite Database Super Class

/// Abstract super class for embedded (SQLite) databases.
public class LocalCache {
  
  fileprivate let schema: String
  
  var url: URL?
  
  let db: Skull
  
  /// Strictly submit to this queue to serialize database access.
  let queue: DispatchQueue
  
  let sqlFormatter: SQLFormatter
  
  fileprivate func open() throws {
    var er: Error?
    
    let db = self.db
    let schema = self.schema
    
    queue.sync {
      do {
        let sql = try String(contentsOfFile: schema, encoding: String.Encoding.utf8)
        try db.exec(sql)
      } catch {
        er = error
      }
    }
    
    if let error = er {
      throw error
    }
  }
  
  /// Initializes a newly created cache.
  ///
  /// - Parameters:
  ///   - schema: The path of the database schema file.
  ///   - url: The file URL of the database to use—and create if necessary.
  public init(schema: String, url: URL?) throws {
    self.schema = schema
    self.url = url
    
    // Comment-in to remove all database files at start-up.
    if let p = url { try FileManager.default.removeItem(at: p) }
    
    self.db = try Skull(url)
    
    let me = type(of: self)
    self.queue = DispatchQueue(label: "ink.codes.\(me)", attributes: [])
    
    self.sqlFormatter = SQLFormatter()
    
    try open()
  }
  
  fileprivate func close() throws {
    try db.close()
  }
  
  deinit {
    try! db.close()
  }
  
  public func flush() throws {
    try db.flush()
  }
}

// MARK: - Base

public final class Cache: LocalCache {
  
  // TODO: Replace noSuggestions Dictionary with NSCache
  fileprivate var noSuggestions = [String : Date]()
  
  // TODO: Replace noSearch Dictionary with NSCache
  fileprivate var noSearch = [String : Date]()

  fileprivate var feedIDsCache = NSCache<NSString, NSNumber>()

  fileprivate func cachedFeedID(for url: String) -> Int? {
    return feedIDsCache.object(forKey: url as NSString) as? Int
  }

  fileprivate func cache(feedID: Int, for url: String) -> Int {
    feedIDsCache.setObject(feedID as NSNumber, forKey: url as NSString)
    return feedID
  }

  fileprivate func removeFeedID(for url: String) {
    feedIDsCache.removeObject(forKey: url as NSString)
  }

  /// Returns the local feed identifier, its rowid in the database feed table, 
  /// for the given URL. Retrieved identifiers are being cached in memory, for
  /// faster access, although this should probably be measured for prove.
  func feedID(for url: String) throws -> Int {
    if let cachedFeedID = cachedFeedID(for: url) {
      return cachedFeedID
    }
    
    var er: Error?
    var id: Int?
    let sql = SQLFormatter.SQLToSelectFeedIDFromURLView(url)
    
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
    guard id != nil else { throw FeedKitError.feedNotCached(urls: [url]) }

    return cache(feedID: id!, for: url)
  }

}

// MARK: - Internal query functions for inlining

extension Cache {
  
  private static func isMainThread() -> Bool {
    guard ProcessInfo.processInfo.processName != "xctest" else {
      return false
    }
    return Thread.isMainThread
  }
  
  /// Queries the database for feeds. If no feeds were found, instead of an 
  /// empty array, `nil` is returned.
  static fileprivate func queryFeeds(
    _ db: Skull, with sql: String, using formatter: SQLFormatter
  ) throws -> [Feed]? {
    assert(!Cache.isMainThread())
    
    var er: Error?
    var feeds = [Feed]()

    try db.query(sql) { error, row -> Int in
      guard error == nil else {
        er = error
        return 1
      }
      if let r = row {
        do {
          let result = try formatter.feedFromRow(r)
          feeds.append(result)
        } catch {
          er = error
          return 1
        }
      }
      return 0
    }
    
    if let error = er {
      throw error
    }
    
    return feeds.isEmpty ? nil : feeds
  }
  
  /// Queries the database for entries. If no entries were found, instead of an 
  /// empty array, `nil` is returned.
  fileprivate static func queryEntries(
    _ db: Skull, with sql: String, using formatter: SQLFormatter
  ) throws -> [Entry]? {
    assert(!Cache.isMainThread())
    
    var er: Error?
    var entries = [Entry]()
    
    try db.query(sql) { error, row -> Int in
      guard error == nil else {
        er = error
        return 1
      }
      if let r = row {
        do {
          let entry = try formatter.entryFromRow(r)
          entries.append(entry)
        } catch {
          er = error
          return 1
        }
      }
      return 0
    }
    
    if let error = er {
      throw error
    }
    
    return entries.isEmpty ? nil : entries
  }
  
  /// Queries the database for suggestions. If no entries were found, instead of
  /// an empty array, `nil` is returned.
  fileprivate static func querySuggestions(
    _ db: Skull, with sql: String, using formatter: SQLFormatter
  ) throws -> [Suggestion]? {
    assert(!Cache.isMainThread())

    var er: Error?
    var sugs = [Suggestion]()
    
    try db.query(sql) { error, row -> Int in
      guard error == nil else {
        er = error
        return 1
      }
      if let r = row {
        do {
          let sug = try formatter.suggestionFromRow(r)
          sugs.append(sug)
        } catch {
          er = error
          return 1
        }
      }
      return 0
    }
    
    if let error = er {
      throw error
    }
    
    return sugs.isEmpty ? nil : sugs
  }

}

// MARK: - FeedCaching

extension Cache: FeedCaching {

  /// Update feeds in the cache. Feeds that are not cached yet are inserted.
  ///
  /// - Parameter feeds: The feeds to insert or update.
  ///
  /// - Throws: Skull errors originating from SQLite.
  public func update(feeds: [Feed]) throws {
    return try queue.sync {
      let sql = try feeds.reduce([String]()) { acc, feed in
        do {
          let feedID = try self.feedID(for: feed.url)
          return acc + [self.sqlFormatter.SQLToUpdateFeed(feed, withID: feedID)]
        } catch FeedKitError.feedNotCached {
          
          guard let guid = feed.iTunes?.guid else {
            return acc + [self.sqlFormatter.SQLToInsertFeed(feed)]
          }
          
          // Removing feed with this guid before inserting, to avoid doublets
          // if the feed URL changed while the GUID stayed the same, leading
          // to a unique constraint failure:
          //
          // unhandled error: Skull: 19: UNIQUE constraint failed: feed.guid
          
          if #available(iOS 10.0, *) {
            os_log("replacing feed with guid: %{public}@",
                   log: log,
                   type: .debug,
                   String(describing: guid))
          }
          
          return acc + [
            SQLFormatter.toRemoveFeed(with: guid),
            self.sqlFormatter.SQLToInsertFeed(feed)
          ]
        }
      }.joined(separator: "\n")
      
      try self.db.exec(sql)
    }
  }

  /// Retrieve feeds from the cache identified by their URLs.
  ///
  /// - Parameter urls: An array of feed URL strings.
  ///
  /// - Returns: An array of feeds currently in the cache.
  func feedIDsForURLs(_ urls: [String]) throws -> [String : Int]? {
    assert(!urls.isEmpty)
    
    var result = [String : Int]()
    try urls.forEach { url in
      do {
        let feedID = try self.feedID(for: url)
        result[url] = feedID
      } catch FeedKitError.feedNotCached {
        if #available(iOS 10.0, *) {
          os_log("feed not cached: %{public}@", log: log,  type: .debug, url)
        }
      }
    }
    
    guard !result.isEmpty else  {
      return nil
    }
    
    return result
  }
  
  /// Returns feeds for `urls` or an empty array.
  public func feeds(_ urls: [String]) throws -> [Feed] {
    return try queue.sync {
      guard let dicts = try self.feedIDsForURLs(urls) else {
        return []
      }
      let feedIDs = dicts.map { $0.1 }
      guard let sql = SQLFormatter.SQLToSelectFeedsByFeedIDs(feedIDs) else {
        return []
      }
      let formatter = self.sqlFormatter
      let feeds = try Cache.queryFeeds(self.db, with: sql, using: formatter)
      return feeds ?? []
    }
  }

  func hasURL(_ url: String) -> Bool {
    do { let _ = try feedID(for: url) } catch { return false }
    return true
  }

  /// Update entries in the cache, inserting new ones.
  ///
  /// - Parameter entries: An array of entries to be cached.
  ///
  /// - Throws: You cannot update entries of feeds that are not cached yet,
  /// if you do, this method will throw `FeedKitError.FeedNotCached`,
  /// containing the respective URLs.
  public func update(entries: [Entry]) throws {
    try queue.sync {
      var unidentified = [String]()
      
      let sql = entries.reduce([String]()) { acc, entry in
        var feedID: Int?
        do {
          feedID = try self.feedID(for: entry.feed)
        } catch {
          let url = entry.feed
          if !unidentified.contains(url) {
            unidentified.append(url)
          }
          return acc
        }
        let formatter = self.sqlFormatter
        return acc + [formatter.SQLToInsertEntry(entry, forFeedID: feedID!)]
      }.joined(separator: "\n")
      
      if sql != "\n" {
        try self.db.exec(sql)
      }
      
      if !unidentified.isEmpty {
        throw FeedKitError.feedNotCached(urls: unidentified)
      }
    }
  }

  /// Retrieve entries within the specified locators.
  ///
  /// - Parameter locators: An array of time intervals between now and the past.
  ///
  /// - Returns: The matching array of entries currently cached.
  public func entries(within locators: [EntryLocator]) throws -> [Entry] {
    guard !locators.isEmpty else {
      return []
    }
    
    return try queue.sync {
      let urls = locators.map { $0.url }
      
      guard let feedIDsByURLs = try self.feedIDsForURLs(urls) else {
        return []
      }
      
      let specs = locators.reduce([(Int, Date)]()) { acc, interval in
        let url = interval.url
        let since = interval.since
        if let feedID = feedIDsByURLs[url] {
          return acc + [(feedID, since)]
        } else {
          return acc
        }
      }
      
      let formatter = self.sqlFormatter
      guard let sql = formatter.SQLToSelectEntriesByIntervals(specs) else {
        return []
      }
      
      let entries = try Cache.queryEntries(self.db, with: sql, using: formatter)
      
      return entries ?? []
    }
  }

  /// Selects entries with matching guids.
  ///
  /// - Parameter guids: An array of entry identifiers.
  /// 
  /// - Returns: An array of matching the specified guids entries.
  ///
  /// - Throws: Might throw database errors.
  public func entries(_ guids: [String]) throws -> [Entry] {
    return try queue.sync {
      // TODO: Test and review entries(having guids:)
      let chunks = Cache.slice(elements: guids, with: 512)

      return try chunks.reduce([Entry]()) { acc, guids in
        guard let sql = SQLFormatter.SQLToSelectEntries(by: guids) else {
          return acc
        }
        let fmt = self.sqlFormatter
        guard let entries = try Cache.queryEntries(
          self.db, with: sql, using: fmt) else {
          return acc
        }
        return acc + entries
      }
    }
  }

  /// Remove feeds and, respectively, their associated entries.
  ///
  /// - Parameter urls: The URL strings of the feeds to remove.
  public func remove(_ urls: [String]) throws {
    try queue.sync {
      guard let dicts = try self.feedIDsForURLs(urls) else { return }
      let feedIDs = dicts.map { $0.1 }
      guard let sql = SQLFormatter.SQLToRemoveFeedsWithFeedIDs(feedIDs) else {
        throw FeedKitError.sqlFormatting
      }
      try db.exec(sql)
      urls.forEach { self.removeFeedID(for: $0) }
    }
  }
  
}

// MARK: - SearchCaching

extension Cache: SearchCaching {
  
  /// Scan dictionary for a term and its lexicographical predecessors.
  ///
  /// The specified dictionary, containing timestamps by terms, is scanned
  /// backwards for a term or its predecessing substrings. If a matching term is
  /// found, it is returned in a tuple with its timestamp.
  ///
  /// - Parameters:
  ///   - term: The term to look for.
  ///   - dict: A dictionary of timestamps by terms.
  ///
  /// - Returns: A tuple containing the matching term and a timestamp, or, if no
  /// matches were found, `nil` is returned.
  static func subcached(_ term: String, dict: [String:Date]) -> (String, Date)? {
    if let ts = dict[term] {
      return (term, ts)
    } else {
      if !term.isEmpty {
        let pre = term.characters.index(before: term.endIndex)
        return subcached(term.substring(to: pre), dict: dict)
      }
      return nil
    }
  }

  /// Update feeds and associate them with the specified search term, which is
  /// also added to the suggestions table of the database.
  ///
  /// If feeds is not empty, we got at least one suggestion for the specified
  /// term, therefore we need to update the subcached dictionary accordingly, to
  /// make sure this term is not skipped the next time a user is requesting
  /// suggestions for this term or its predecessors.
  ///
  /// - Parameters:
  ///   - feeds: The feeds to cache.
  ///   - term: The term to associate the specified feeds with.
  ///
  /// - Throws: Might throw database errors: various `SkullError` types.
  public func update(feeds: [Feed], for term: String) throws {
    if feeds.isEmpty {
      noSearch[term] = Date()
    } else {
      try update(feeds: feeds)
      noSearch[term] = nil
      if let (predecessor, _) = Cache.subcached(term, dict: noSuggestions) {
        noSuggestions[predecessor] = nil
      }
    }

    // To stay synchronized with the remote state, before inserting feed
    // identifiers, we delete searches for this term wholesale.

    try queue.sync {
      do {
        let delete = SQLFormatter.SQLToDeleteSearch(for: term)
        let insert = try feeds.reduce([String]()) { acc, feed in
          let feedID: Int
          do {
            feedID = try feed.uid ?? self.feedID(for: feed.url)
          } catch {
            switch error {
            case FeedKitError.feedNotCached(let urls):
              if #available(iOS 10.0, *) {
                os_log("feed not cached: %{public}@", log: log,  type: .error, urls)
              }
              return acc
            default: throw error
            }
          }
          return acc + [SQLFormatter.SQLToInsertFeedID(feedID, forTerm: term)]
        }.joined(separator: "\n")
        
        let sql = [
          "BEGIN;",
          delete,
          insert,
          "COMMIT;"
        ].joined(separator: "\n")
        
        try self.db.exec(sql)
      }
    }

  }

  /// Return distinct feeds cached for the specified term, the number of feeds
  /// may be limited.
  ///
  /// - Parameters:
  ///   - term: The search term.
  ///   - limit: The maximal number of feeds to return.
  ///
  /// - Returns: An array of feeds that can be empty, meaning: no feeds matching
  /// this term, or `nil`: meaning no feeds cached for this term.
  ///
  /// - Throws: Might throw FeedKit or Skull errors.
  public func feeds(for term: String, limit: Int) throws -> [Feed]? {
    return try queue.sync {
      if let ts = self.noSearch[term] {
        if Cache.stale(ts, ttl: CacheTTL.long.seconds) {
          self.noSearch[term] = nil
          return nil
        } else {
          return []
        }
      }
      
      let sql = SQLFormatter.SQLToSelectFeedsByTerm(term, limit: limit)
      
      return try Cache.queryFeeds(self.db, with: sql, using: self.sqlFormatter)
    }
  }

  /// Returns feeds matching `term` using full-text-search.
  public func feeds(matching term: String, limit: Int) throws -> [Feed]? {
    let db = self.db
    let fmt = self.sqlFormatter

    return try queue.sync { [unowned db, unowned fmt] in
      let sql = SQLFormatter.SQLToSelectFeedsMatchingTerm(term, limit: limit)
      return try Cache.queryFeeds(db, with: sql, using: fmt)
    }
  }

  /// Run a full text search on all cached entries for the specified term.
  ///
  /// - Parameters:
  ///   - term: The search term to use.
  ///   - limit: The maximum number of entries to return.
  ///
  /// - Returns: Entries with matching author, summary, subtitle, or title.
  ///
  /// - Throws: Might throw SQL errors via Skull.
  public func entries(matching term: String, limit: Int) throws -> [Entry]? {
    let db = self.db
    let fmt = self.sqlFormatter
    
    return try queue.sync { [unowned db, unowned fmt] in
      let sql = SQLFormatter.SQLToSelectEntries(matching: term, limit: limit)
      return try Cache.queryEntries(db, with: sql, using: fmt)
    }
  }

  /// Update suggestions for a given `term`. You might pass an empty array to 
  /// signal that the remote server didn‘t supply any suggestions for this term.
  /// This state would than also be cache, so that the server doesn‘t has to be
  /// hit again, within the respective time-to-live interval.
  public func update(suggestions: [Suggestion], for term: String) throws {
    try queue.sync {
      guard !suggestions.isEmpty else {
        noSuggestions[term] = Date()
        let sql = SQLFormatter.SQLToDeleteSuggestionsMatchingTerm(term)
        try self.db.exec(sql)
        return
      }
      
      if let (cachedTerm, _) = Cache.subcached(term, dict: noSuggestions) {
        noSuggestions[cachedTerm] = nil
      }
      
      let sql = [
        "BEGIN;",
        suggestions.map {
          SQLFormatter.SQLToInsertSuggestionForTerm($0.term)
          }.joined(separator: "\n"),
        "COMMIT;"
      ].joined(separator: "\n")
      
      try db.exec(sql)
    }
  }

  /// Retrieve cached suggestions matching a term from the database.
  /// 
  /// - Parameters:
  ///   - term: The term to query the database for suggestions with.
  ///   - limit: The maximum number of suggestions to return.
  ///
  /// - Returns: An array of matching suggestions. If the term isn't cached yet
  /// `nil` is returned. Having no suggestions is cached too: it is expressed by
  /// returning an empty array.
  /// 
  /// - Throws: Might throw FeedKit and Skull errors.
  public func suggestions(for term: String, limit: Int) throws -> [Suggestion]? {
    return try queue.sync {
      if let (cachedTerm, ts) = Cache.subcached(term, dict: noSuggestions) {
        if Cache.stale(ts, ttl: CacheTTL.long.seconds) {
          noSuggestions[cachedTerm] = nil
          return nil
        } else {
          return []
        }
      }
      let sql = SQLFormatter.SQLToSelectSuggestionsForTerm(term, limit: limit)
      return try Cache.querySuggestions(db, with: sql, using: sqlFormatter)
    }
  }
}

// MARK: - Utilities

extension Cache {
  
  /// Slices an array into fixed sized arrays.
  ///
  /// - Parameters:
  ///   - elements: The array to slice.
  ///   - count: The number of elements in the returned arrays.
  ///
  /// - Returns: An array of arrays with count`.
  static func slice<T>(elements: [T], with count: Int) -> [Array<T>] {
    guard elements.count > count else {
      return [elements]
    }
    
    var i = 0
    var start = 0
    var end = 0
    var slices = [[T]]()
    
    repeat {
      start = min(count * i, elements.count)
      end = min(start + count, elements.count)
      
      let slice = elements[start..<end]
      if !slice.isEmpty {
        slices.append(Array(slice))
      }
      
      i += 1
    } while start != end
    
    return slices
  }
  
  /// Returns `true` if the specified timestamp is older than the specified time
  /// to live.
  ///
  /// - Parameters:
  ///   - ts: The timestamp to check if it's older than the specified ttl.
  ///   - ttl: The maximal age to allow.
  ///
  /// - Returns: `true` if the timestamp is older than the maximal age.
  static func stale(_ ts: Date, ttl: TimeInterval) -> Bool {
    return ts.timeIntervalSinceNow + ttl < 0
  }
  
  /// Returns the median timestamp of the specified cachable items.
  ///
  /// - Parameters:
  ///   - items: The cachable items of which to locate the median.
  ///   - sorting: To skip the sorting but lose warranty of correctness.
  ///
  /// - Returns: The median timestamp of these cachable items; or nil, if you pass
  /// an empty array.
  static func medianTS <T: Cachable> (_ items: [T], sorting: Bool = true) -> Date? {
    guard !items.isEmpty else { return nil }
    let sorted: [T]
    if sorting {
      sorted = items.sorted {
        guard $0.ts != nil else { return false }
        guard $1.ts != nil else { return true }
        return $0.ts!.compare($1.ts! as Date) == ComparisonResult.orderedDescending
      }
    } else {
      sorted = items
    }
    
    let index = sorted.count / 2
    let median = sorted[index].ts
    
    return median as Date?
  }
  
}
