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
func stale(ts: NSDate, ttl: NSTimeInterval) -> Bool {
  return ts.timeIntervalSinceNow + ttl < 0
}

public final class Cache {

  private let schema: String

  var url: NSURL?

  private let db: Skull
  private let queue: dispatch_queue_t
  private let sqlFormatter: SQLFormatter

  private var noSuggestions = [String:NSDate]()
  private var noSearch = [String:NSDate]()
  private var feedIDsCache = NSCache()

  private func remove() throws {
    var error: ErrorType?
    let url = self.url
    dispatch_sync(queue) {
      do {
        let fm = NSFileManager.defaultManager()
        try fm.removeItemAtURL(url!)
      } catch let er {
        error = er
      }
    }
    if let er = error {
      throw er
    }
  }

  private func open() throws {
    var error: ErrorType?

    let db = self.db
    let schema = self.schema
    let maybeURL = self.url

    dispatch_sync(queue) {
      do {
        if let url = maybeURL { try db.open(url) } else { try db.open() }
        let sql = try String(contentsOfFile: schema, encoding: NSUTF8StringEncoding)
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
  /// - Parameter schema: The path of the database schema file.
  /// - Parameter url: The file URL of the database to use—and create if necessary.
  /// - Parameter rm: An optional flag for development indicating you want to
  ///   replace an eventually already existing database file.
  public init(schema: String, url: NSURL?, rm: Bool? = false) throws {
    self.schema = schema
    self.url = url

    // If we'd pass these, we could disjoint the cache into separate objects.
    self.db = Skull()
    let label = "com.michaelnisi.feedkit.cache"
    self.queue = dispatch_queue_create(label, DISPATCH_QUEUE_SERIAL)
    self.sqlFormatter = SQLFormatter()

    if url != nil && rm! { try remove() }

    try open()
  }

  private func close() throws {
    try db.close()
  }

  deinit {
    try! db.close()
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

  /// Update feeds in the cache. Feeds that are not cached yet are inserted.
  ///
  /// - Parameter feeds: The feeds to insert or update.
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

  /// Retrieve feeds from the cache identified by their URLs.
  ///
  /// - Parameter urls: An array of feed URL strings.
  /// - Returns: An array of feeds currently in the cache.
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

  public func feeds(urls: [String]) throws -> [Feed] {
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

  /// Update entries in the cache inserting new ones.
  ///
  /// - Parameter entries: An array of entries to be cached.
  /// - Throws: You cannot update entries of feeds that are not cached yet,
  /// if you do, this method will throw `FeedKitError.FeedNotCached`,
  /// containing the respective URLs.
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

  private func entriesForSQL(sql: String) throws -> [Entry]? {
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

  /// Retrieve entries within the specified locators.
  ///
  /// - Parameter locators: An array of time intervals between now and the past.
  /// - Returns: The matching array of entries currently cached.
  public func entries(locators: [EntryLocator]) throws -> [Entry] {
    var entries: [Entry]?
    var error: ErrorType?
    let fmt = self.sqlFormatter

    dispatch_sync(queue) {
      do {
        let urls = locators.map { $0.url }
        guard let feedIDsByURLs = try self.feedIDsForURLs(urls) else {
          return
        }
        let specs = locators.reduce([(Int, NSDate)]()) { acc, interval in
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
  /// - Parameter guids: An array of entry identifiers.
  /// - Returns: An array of matching the specified guids entries.
  /// - Throws: Might throw database errors.
  public func entries(guids: [String]) throws -> [Entry] {
    let db = self.db

    var entries = [Entry]()
    var error: ErrorType?

    dispatch_sync(queue) {
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
    return entries ?? [Entry]()
  }

  /// Remove feeds and, respectively, their associated entries.
  ///
  /// - Parameter urls: The URL strings of the feeds to remove.
  public func remove(urls: [String]) throws {
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

/// Scan dictionary for a term and its lexicographical predecessors.
///
/// The specified dictionary, containing timestamps by terms, is scanned
/// backwards for a term or its predecessing substrings. If a matching term is
/// found, it is returned in a tuple with its timestamp.
///
/// - Parameter term: The term to look for.
/// - Parameter dict: A dictionary of timestamps by terms.
/// - Returns: A tuple containing the matching term and a timestamp, or, if no
/// matches were found, `nil` is returned.
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

  /// Update feeds and associate them with the specified search term, which is
  /// also added to the suggestions table of the database.
  ///
  /// If feeds is not empty, we got at least one suggestion for the specified
  /// term, therefore we need to update the subcached dictionary accordingly, to
  /// make sure this term is not skipped the next time a user is requesting
  /// suggestions for this term or its predecessors.
  ///
  /// - Parameter feeds: The feeds to cache.
  /// - Parameter term: The term to associate the specified feeds with.
  /// - Throws: May throw database errors: various `SkullError` types.
  public func updateFeeds(feeds: [Feed], forTerm term: String) throws {
    if feeds.isEmpty {
      // We keep the feeds.
      noSearch[term] = NSDate()
    } else {
      try updateFeeds(feeds)
      noSearch[term] = nil
      if let (predecessor, _) = subcached(term, dict: noSuggestions) {
        noSuggestions[predecessor] = nil
      }
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
    let noSearch = self.noSearch

    dispatch_sync(queue) { [unowned self] in
      if let ts = noSearch[term] {
        if stale(ts, ttl: CacheTTL.Long.seconds) {
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

  /// Run a full text search on all cached entries for the specified term.
  ///
  /// - Parameter term: The search term to use.
  /// - Parameter limit: The maximum number of entries to return.
  /// - Returns: Entries with matching author, summary, subtitle, or title.
  /// - Throws: Might throw SQL errors via Skull.
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

  /// Retrieve cached suggestions matching a term from the database.
  ///
  /// - Parameter term: The term to query the database for suggestions with.
  /// - Parameter limit: The maximum number of suggestions to return.
  /// - Returns: An array of matching suggestions. If the term isn't cached yet
  /// `nil` is returned. Having no suggestions is cached too: it is expressed by
  /// returning an empty array.
  public func suggestionsForTerm(term: String, limit: Int) throws -> [Suggestion]? {
    if let (cachedTerm, ts) = subcached(term, dict: noSuggestions) {
      if stale(ts, ttl: CacheTTL.Long.seconds) {
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
