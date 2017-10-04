//
//  FeedCache.swift
//  FeedKit
//
//  Created by Michael on 9/5/17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import Foundation
import Skull
import os.log

// TODO: Harmonize implementation and style

// MARK: - Logging

@available(iOS 10.0, *)
fileprivate let log = OSLog(subsystem: "ink.codes.feedkit", category: "cache")

public final class FeedCache: LocalCache {
  
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

extension FeedCache {
  
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
    assert(!FeedCache.isMainThread())
    
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
    assert(!FeedCache.isMainThread())
    
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
    assert(!FeedCache.isMainThread())
    
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

extension FeedCache: FeedCaching {
  
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
          
          // TODO: Use feed guid
          
          guard let guid = feed.iTunes?.iTunesID else {
            return acc + [self.sqlFormatter.SQLToInsertFeed(feed)]
          }
          
          // Removing feed with this guid before inserting, to avoid doublets
          // if the feed URL changed while the iTunes GUID stayed the same,
          // leading to a unique constraint failure:
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
      let feeds = try FeedCache.queryFeeds(self.db, with: sql, using: formatter)
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
      
      let entries = try FeedCache.queryEntries(self.db, with: sql, using: formatter)
      
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
      // TODO: Consider renaming to entries(having guids:)
      let chunks = FeedCache.slice(elements: guids, with: 512)
      
      return try chunks.reduce([Entry]()) { acc, guids in
        guard let sql = SQLFormatter.SQLToSelectEntries(by: guids) else {
          return acc
        }
        let fmt = self.sqlFormatter
        guard let entries = try FeedCache.queryEntries(
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

// TODO: Use prepared statements in SearchCaching

extension FeedCache: SearchCaching {
  
  // TODO: Review subcached function
  
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
        let substring = String(term[..<pre])
        return subcached(substring, dict: dict)
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
      if let (predecessor, _) = FeedCache.subcached(term, dict: noSuggestions) {
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
  
  // TODO: Review feeds(for term), rowid issues
  
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
        if FeedCache.stale(ts, ttl: CacheTTL.long.seconds) {
          self.noSearch[term] = nil
          return nil
        } else {
          return []
        }
      }
      
      let sql = SQLFormatter.SQLToSelectFeedsByTerm(term, limit: limit)
      
      return try FeedCache.queryFeeds(self.db, with: sql, using: self.sqlFormatter)
    }
  }
  
  /// Returns feeds matching `term` using full-text-search.
  public func feeds(matching term: String, limit: Int) throws -> [Feed]? {
    let db = self.db
    let fmt = self.sqlFormatter
    
    return try queue.sync { [unowned db, unowned fmt] in
      let sql = SQLFormatter.SQLToSelectFeedsMatchingTerm(term, limit: limit)
      return try FeedCache.queryFeeds(db, with: sql, using: fmt)
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
      return try FeedCache.queryEntries(db, with: sql, using: fmt)
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
      
      if let (cachedTerm, _) = FeedCache.subcached(term, dict: noSuggestions) {
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
      if let (cachedTerm, ts) = FeedCache.subcached(term, dict: noSuggestions) {
        if FeedCache.stale(ts, ttl: CacheTTL.long.seconds) {
          noSuggestions[cachedTerm] = nil
          return nil
        } else {
          return []
        }
      }
      let sql = SQLFormatter.SQLToSelectSuggestionsForTerm(term, limit: limit)
      return try FeedCache.querySuggestions(db, with: sql, using: sqlFormatter)
    }
  }
}