//
//  cache.swift - store and retrieve data
//  FeedKit
//
//  Created by Michael Nisi on 03.11.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import Foundation
import Skull

/// Return true if the specified timestamp is older than the specified time to
/// live.
///
/// - parameter ts: The timestamp to check if it's older than the specified ttl.
/// - parameter ttl: The maximal age to allow.
///
/// - returns: True if the timestamp is older than the maximal age.
func stale(_ ts: Date, ttl: TimeInterval) -> Bool {
  return ts.timeIntervalSinceNow + ttl < 0
}

/// Return the median timestamp of the specified cachable items.
///
/// - parameter items: The cachable items of which to locate the median.
/// - parameter sorting: To skip the sorting but lose warranty of correctness.
///
/// - returns: The median timestamp of these cachable items; or nil, if you pass
/// an empty array.
func medianTS <T: Cachable> (_ items: [T], sorting: Bool = true) -> Date? {
  guard !items.isEmpty else { return nil }
  var sorted: [T]
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

public final class Cache {

  fileprivate let schema: String

  var url: URL?

  fileprivate let db: Skull
  fileprivate let queue: DispatchQueue
  fileprivate let sqlFormatter: SQLFormatter

  fileprivate var noSuggestions = [String:Date]()
  fileprivate var noSearch = [String:Date]()
  
  fileprivate var feedIDsCache = NSCache<NSString, NSNumber>()

  fileprivate func open() throws {
    var error: Error?

    let db = self.db
    let schema = self.schema

    queue.sync {
      do {
        let sql = try String(contentsOfFile: schema, encoding: String.Encoding.utf8)
        try db.exec(sql)
      } catch let er {
        error = er
      }
    }
    if let er = error {
      throw er
    }
  }

  /// Initializes a newly created cache.
  ///
  /// - parameter schema: The path of the database schema file.
  /// - parameter url: The file URL of the database to use—and create if necessary.
  public init(schema: String, url: URL?) throws {
    self.schema = schema
    self.url = url

    // If we'd pass these, we could disjoint the cache into separate objects.
    self.db = try Skull(url)
    self.queue = DispatchQueue(label: "ink.codes.feedkit.cache", attributes: [])
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
  
  func feedIDForURL(_ url: String) throws -> Int {
    if let cachedFeedID = cachedFeedID(for: url) {
      return cachedFeedID
    }
    var er: Error?
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
    guard id != nil else { throw FeedKitError.feedNotCached(urls: [url]) }

    return cache(feedID: id!, for: url)
  }

  // TODO: Write test for feedsForSQL method

  func feedsForSQL(_ sql: String) throws -> [Feed]? {
    let db = self.db
    let fmt = self.sqlFormatter

    var er: Error?
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

  /// Update feeds in the cache. Feeds that are not cached yet are inserted.
  ///
  /// - parameter feeds: The feeds to insert or update.
  public func update(feeds: [Feed]) throws {
    let fmt = self.sqlFormatter
    let db = self.db
    
    var error: Error?

    queue.sync {
      do {
        let sql = try feeds.reduce([String]()) { acc, feed in
          do {
            let feedID = try self.feedIDForURL(feed.url)
            return acc + [fmt.SQLToUpdateFeed(feed, withID: feedID)]
          } catch FeedKitError.feedNotCached {
            return acc + [fmt.SQLToInsertFeed(feed)]
          }
        }.joined(separator: "\n")
        try db.exec(sql)
      } catch let er {
        error = er
      }
    }
    
    if let er = error {
      throw er
    }
  }

  /// Retrieve feeds from the cache identified by their URLs.
  ///
  /// - parameter urls: An array of feed URL strings.
  /// - returns: An array of feeds currently in the cache.
  func feedIDsForURLs(_ urls: [String]) throws -> [String : Int]? {
    var result = [String:Int]()
    try urls.forEach { url in
      do {
        let feedID = try self.feedIDForURL(url)
        result[url] = feedID
      } catch FeedKitError.feedNotCached {
        // No need to throw this, our user can ascertain uncached feeds from result.
      }
    }
    if result.isEmpty {
      return nil
    }
    return result
  }

  public func feeds(_ urls: [String]) throws -> [Feed] {
    var feeds: [Feed]?
    var error: Error?
    queue.sync {
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

  func hasURL (_ url: String) -> Bool {
    do {
      let _ = try feedIDForURL(url)
    } catch {
      return false
    }
    return true
  }

  /// Update entries in the cache inserting new ones.
  ///
  /// - parameter entries: An array of entries to be cached.
  ///
  /// - throws: You cannot update entries of feeds that are not cached yet,
  /// if you do, this method will throw `FeedKitError.FeedNotCached`,
  /// containing the respective URLs.
  public func updateEntries(_ entries: [Entry]) throws {
    let fmt = self.sqlFormatter
    let db = self.db
    var error: Error?

    queue.sync {
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
        }.joined(separator: "\n")
        if sql != "\n" {
          try db.exec(sql)
        }
        if !unidentified.isEmpty {
          throw FeedKitError.feedNotCached(urls: unidentified)
        }
      } catch let er {
        error = er
      }
    }
    if let er = error {
      throw er
    }
  }

  fileprivate func entriesForSQL(_ sql: String) throws -> [Entry]? {
    let db = self.db
    let df = self.sqlFormatter

    var er: Error?
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

  /// Retrieve entries within the specified locators.
  ///
  /// - parameter locators: An array of time intervals between now and the past.
  /// - Returns: The matching array of entries currently cached.
  public func entries(_ locators: [EntryLocator]) throws -> [Entry] {
    var entries: [Entry]?
    var error: Error?
    let fmt = self.sqlFormatter

    queue.sync {
      do {
        let urls = locators.map { $0.url }
        guard let feedIDsByURLs = try self.feedIDsForURLs(urls) else {
          return
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

  // TODO: Conflate multiple selects into transactions (like here)

  /// Entries with matching guids.
  ///
  /// - parameter guids: An array of entry identifiers.
  /// - Returns: An array of matching the specified guids entries.
  /// - Throws: Might throw database errors.
  public func entries(_ guids: [String]) throws -> [Entry] {
    let db = self.db

    var entries = [Entry]()
    var error: Error?

    queue.sync {
      do {
        try db.exec("begin transaction;")
        for guid in guids {
          let sql = SQLToSelectEntryByGUID(guid)
          if let found = try self.entriesForSQL(sql) {
            entries = entries + found
          }
        }
        try db.exec("commit;")
      } catch let er {
        return error = er
      }
    }
    if let er = error {
      throw er
    }
    return entries
  }

  /// Remove feeds and, respectively, their associated entries.
  ///
  /// - parameter urls: The URL strings of the feeds to remove.
  public func remove(_ urls: [String]) throws {
    let db = self.db
    var error: Error?
    queue.sync {
      do {
        guard let dicts = try self.feedIDsForURLs(urls) else { return }
        let feedIDs = dicts.map { $0.1 }
        guard let sql = SQLToRemoveFeedsWithFeedIDs(feedIDs) else {
          throw FeedKitError.sqlFormatting
        }
        try db.exec(sql)
        urls.forEach { self.removeFeedID(for: $0) }
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

/// Scan dictionary for a term and its lexicographical predecessors.
///
/// The specified dictionary, containing timestamps by terms, is scanned
/// backwards for a term or its predecessing substrings. If a matching term is
/// found, it is returned in a tuple with its timestamp.
///
/// - parameter term: The term to look for.
/// - parameter dict: A dictionary of timestamps by terms.
/// - Returns: A tuple containing the matching term and a timestamp, or, if no
/// matches were found, `nil` is returned.
func subcached(_ term: String, dict: [String:Date]) -> (String, Date)? {
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

extension Cache: SearchCaching {

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
  /// - Throws: May throw database errors: various `SkullError` types.
  public func updateFeeds(_ feeds: [Feed], forTerm term: String) throws {
    if feeds.isEmpty {
      noSearch[term] = Date()
    } else {
      try update(feeds: feeds)
      noSearch[term] = nil
      if let (predecessor, _) = subcached(term, dict: noSuggestions) {
        noSuggestions[predecessor] = nil
      }
    }

    let db = self.db
    var error: Error?

    // To stay synchronized with the remote state, before inserting feed 
    // identifiers, we firstly delete all searches for this term.

    queue.sync {
      do {
        let delete = SQLToDeleteSearchForTerm(term)
        let insert = try feeds.reduce([String]()) { acc, feed in
          let feedID = try feed.uid ?? self.feedIDForURL(feed.url)
          return acc + [SQLToInsertFeedID(feedID, forTerm: term)]
        }.joined(separator: "\n")
        let sql = [
          "BEGIN;",
          delete,
          insert,
          "COMMIT;"
        ].joined(separator: "\n")
        try db.exec(sql)
      } catch let er {
        error = er
      }
    }
    if let er = error {
      throw er
    }
  }

  /// Return feeds matching the specified term, the number of feeds can be 
  /// limited.
  ///
  /// - parameter term: The search term.
  /// - parameter limit: The maximal number of feeds to return.
  ///
  /// - returns: An array of feeds that can be empty or nil.
  ///
  public func feedsForTerm(_ term: String, limit: Int) throws -> [Feed]? {
    var feeds: [Feed]?
    var error: Error?
    let noSearch = self.noSearch

    queue.sync { [unowned self] in
      if let ts = noSearch[term] {
        if stale(ts, ttl: CacheTTL.long.seconds) {
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
    
    guard let f = feeds else { return feeds }
    
    return f
    
    // TODO: Optimize SQL query for this application
    
//    let s = Set(f) // uniquify
//    let u = Array(s)
//    return u.sorted {
//      guard let a = $0.updated else { return false }
//      guard let b = $1.updated else { return true }
//      return a.compare(b as Date) == ComparisonResult.orderedDescending
//    }
  }
  
  public func feedsMatchingTerm(_ term: String, limit: Int) throws -> [Feed]? {
    var feeds: [Feed]?
    var error: Error?

    queue.sync {
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

  /// Run a full text search on all cached entries for the specified term.
  ///
  /// - parameter term: The search term to use.
  /// - parameter limit: The maximum number of entries to return.
  /// - Returns: Entries with matching author, summary, subtitle, or title.
  /// - Throws: Might throw SQL errors via Skull.
  public func entriesMatchingTerm(_ term: String, limit: Int) throws -> [Entry]? {
    var entries: [Entry]?
    var error: Error?

    queue.sync {
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

  public func updateSuggestions(_ suggestions: [Suggestion], forTerm term: String) throws {
    let db = self.db

    guard !suggestions.isEmpty else {
      noSuggestions[term] = Date()
      var er: Error?
      queue.sync {
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

    var er: Error?
    queue.sync(execute: {
      do {
        let sql = [
          "BEGIN;",
          suggestions.map {
            SQLToInsertSuggestionForTerm($0.term)
          }.joined(separator: "\n"),
          "COMMIT;"
        ].joined(separator: "\n")
        try db.exec(sql)
      } catch let error {
        er = error
      }
    })
    if let error = er {
      throw error
    }
  }

  func suggestionsForSQL(_ sql: String) throws -> [Suggestion]? {
    let db = self.db
    let df = self.sqlFormatter
    var optErr: Error?
    var sugs = [Suggestion]()
    queue.sync(execute: {
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

  /// Retrieve cached suggestions matching a term from the database.
  ///
  /// - parameter term: The term to query the database for suggestions with.
  /// - parameter limit: The maximum number of suggestions to return.
  /// - Returns: An array of matching suggestions. If the term isn't cached yet
  /// `nil` is returned. Having no suggestions is cached too: it is expressed by
  /// returning an empty array.
  public func suggestionsForTerm(_ term: String, limit: Int) throws -> [Suggestion]? {
    if let (cachedTerm, ts) = subcached(term, dict: noSuggestions) {
      if stale(ts, ttl: CacheTTL.long.seconds) {
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
