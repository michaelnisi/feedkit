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

public final class FeedCache: LocalCache {
  
  /// The last time entries of an URL have been reported needed.
  private var lastTimeNeededByURL = DateCache(ttl: CacheTTL.short.seconds)
  
  private lazy var sqlFormatter = LibrarySQLFormatter()
  
  // Access these caches is not synchronized, be aware that this only works,
  // if our users run exactly ONE search operation at a time.

  // TODO: Replace noSuggestions Dictionary with NSCache
  fileprivate var noSuggestions = [String : Date]()

  // TODO: Replace noSearch Dictionary with NSCache
  fileprivate var noSearch = [String : Date]()

  fileprivate var feedIDsCache = NSCache<NSString, ValueObject<FeedID>>()

  fileprivate func cachedFeedID(for url: String) -> FeedID? {
    return feedIDsCache.object(forKey: url as NSString)?.value
  }

  fileprivate func cache(feedID: FeedID, for url: String) -> FeedID {
    let obj = ValueObject<FeedID>(feedID)
    feedIDsCache.setObject(obj, forKey: url as NSString)
    return feedID
  }

  fileprivate func removeFeedID(for url: String) {
    feedIDsCache.removeObject(forKey: url as NSString)
  }

  /// Returns the local feed identifier, its rowid in the database feed table,
  /// for the given URL. Retrieved identifiers are being cached in memory, for
  /// faster access, although this should probably be measured for prove.
  func feedID(for url: String) throws -> FeedID {
    if let cachedFeedID = cachedFeedID(for: url) {
      return cachedFeedID
    }

    var er: Error?
    var id: FeedID?
    let sql = LibrarySQLFormatter.SQLToSelectFeedIDFromURLView(url)
    
    try db.query(sql) { error, row in
      guard error == nil, let r = row else {
        er = error ?? FeedKitError.unexpectedDatabaseRow
        return 1
      }
      do {
        id = try LibrarySQLFormatter.feedID(from: r)
      } catch {
        er = error
        return 1
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
    _ db: Skull, with sql: String, using formatter: LibrarySQLFormatter
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
    _ db: Skull, with sql: String, using formatter: LibrarySQLFormatter
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
    _ db: Skull, with sql: String, using formatter: LibrarySQLFormatter
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
  
  // TODO: Review fullfill function

  /// Queries the local `cache` for entries and returns a tuple of cached
  /// entries and unfulfilled entry `locators`, if any.
  ///
  /// Remember that **entries cannot be stale**—call site makes the calls.
  ///
  /// Despite `ttl`, older entries are returned, however their locators are
  /// included as unfulfilled. For groups the timestamp of the latest entry
  /// is relevant.
  ///
  /// - Parameters:
  ///   - locators: The selection of entries to fetch.
  ///   - ttl: The maximum age for entries.
  ///
  /// - Returns: A tuple of cached entries and URLs not satisfied by the cache.
  ///
  /// - Throws: Might throw database errors.
  public func fulfill(_ locators: [EntryLocator], ttl: TimeInterval
  ) throws -> ([Entry], [EntryLocator]) {
    os_log("""
    fulfilling: {
      locators: %{public}@,
      ttl: %f
    }
    """, log: Cache.log, type: .debug, locators, ttl)
    
    let optimized = EntryLocator.reduce(locators)
    
    let guids = optimized.compactMap { $0.guid }
    let resolved = try entries(guids)

    // If all locators were specific, we can check if we are done.
    if guids.count == optimized.count, guids.count == resolved.count {
      return (resolved, [])
    }

    let resolvedGUIDs = resolved.map { $0.guid }
    
    let unresolved = optimized.filter {
      guard let guid = $0.guid else {
        return true
      }
      return !resolvedGUIDs.contains(guid)
    }

    let items = try entries(within: unresolved) + resolved
    let unresolvedURLs = unresolved.map { $0.url }

    let (cached, stale, needed) = FeedCache.subtract(
      items, from: unresolvedURLs, with: ttl
    )

    os_log("""
    subtracted: {
      cached: %{public}@,
      stale: %{public}@,
      needed: %{public}@
    }
    """, log: Cache.log, type: .debug, cached, stale, needed ?? "none")

    assert(stale.isEmpty, "entries cannot be stale")

    let neededLocators: [EntryLocator] = optimized.filter {
      let urls = needed ?? []
      let y = urls.contains($0.url)
      guard let guid = $0.guid else {
        return y
      }
      return !resolvedGUIDs.contains(guid) || y
    }

    // Assumingly, if needed locators are all specific and matching the request,
    // we got nothing. This is the only case dismissing collected data here,
    // otherwise the caller would need scan the result for the GUIDS requested.
    // Shortly put, for concrete requests, we can tell we have failed.
    
    guard (neededLocators.filter { $0.guid != nil }) != optimized else {
      return ([], neededLocators)
    }
    
    // Provisionally only for single locators, we are restricting the resulting
    // needed locators to the latest we got from the cache, minimizing request
    // frequency and response size. Without this, we’d rely on URLCache, which
    // works, but using GET requests, resulting in fetching entire feeds.
    
    if neededLocators.count == 1,
      !cached.isEmpty,
      let url = neededLocators.first?.url,
      let latest = (cached.filter {
        $0.url == url }.sorted { $0.updated > $1.updated }.first),
      let ts = latest.ts {
      
      if FeedCache.stale(ts, ttl: ttl), lastTimeNeededByURL.update(url) {
        return (cached, [EntryLocator(entry: latest)])
      } else {
        return (cached, [])
      }
    }

    return (cached, neededLocators)
  }
  
  public func integrate(iTunesItems: [ITunesItem]) throws {
    try queue.sync {
      let sql = iTunesItems.reduce([String]()) { acc, iTunes in
        return acc + [sqlFormatter.SQLToUpdate(iTunes: iTunes)]
      }.joined(separator: "\n")

      try db.exec(sql)
    }
  }

  /// Updates feeds using a dynamic SQL formatting function.
  public func update(
    feeds: [Feed],
    using sqlToUpdateFeeds: @escaping (Feed, FeedID) -> String
  ) throws {
    return try queue.sync {
      let sql = try feeds.reduce([String]()) { acc, feed in
        do {
          let id = try feedID(for: feed.url)
          return acc + [sqlToUpdateFeeds(feed, id)]
        } catch FeedKitError.feedNotCached {
          guard let guid = feed.iTunes?.iTunesID else {
            return acc + [sqlFormatter.SQLToInsert(feed: feed)]
          }
          return acc + [
            LibrarySQLFormatter.toRemoveFeed(with: guid),
            sqlFormatter.SQLToInsert(feed: feed)
          ]
        }
      }.joined(separator: "\n")

      do {
        try db.exec(sql)
      } catch {
        switch error {
        case SkullError.sqliteError(let code, let message):
          guard code == 19 else {
            break
          }
          os_log("inconsistent database: %@", log: Cache.log, type: .error, message)
          // TODO: Handle Skull: 19: UNIQUE constraint failed: feed.itunes_guid
          break
        default:
          break
        }
        throw error
      }
    }
  }

  public func update(feeds: [Feed]) throws {
    try update(feeds: feeds) { feed, feedID in
      return self.sqlFormatter.SQLToUpdate(feed: feed, with: feedID, from: .hosted)
    }
  }

  /// Retrieve feeds from the cache identified by their URLs.
  ///
  /// - Parameter urls: An array of feed URL strings. Passing empty `urls` is
  /// considered a programming error and will crash.
  ///
  /// - Returns: An array of feeds currently in the cache.
  func feedIDs(matching urls: [String]) throws -> [String : FeedID]? {
    assert(!urls.isEmpty)

    var result = [String : FeedID]()
    try urls.forEach { url in
      do {
        let feedID = try self.feedID(for: url)
        result[url] = feedID
      } catch FeedKitError.feedNotCached {
        os_log("feed not cached: %{public}@", log: Cache.log,  type: .debug, url)
      }
    }

    guard !result.isEmpty else  {
      return nil
    }

    return result
  }

  public func feeds(_ urls: [String]) throws -> [Feed] {
    return try queue.sync {
      guard let dicts = try self.feedIDs(matching: urls) else {
        return []
      }
      let feedIDs = dicts.map { $0.1 }
      guard let sql = LibrarySQLFormatter.SQLToSelectFeeds(by: feedIDs) else {
        return []
      }
      let feeds = try FeedCache.queryFeeds(db, with: sql, using: sqlFormatter)
      return feeds ?? []
    }
  }

  func hasURL(_ url: String) -> Bool {
    do { let _ = try feedID(for: url) } catch { return false }
    return true
  }

  public func update(entries: [Entry]) throws {
    guard !entries.isEmpty else {
      return
    }

    try queue.sync {
      var unidentified = [String]()

      let sql = entries.reduce([String]()) { acc, entry in
        var feedID: FeedID?
        do {
          feedID = try self.feedID(for: entry.feed)
        } catch {
          let url = entry.feed
          if !unidentified.contains(url) {
            unidentified.append(url)
          }
          return acc
        }
        return acc + [sqlFormatter.SQLToInsert(entry: entry, for: feedID!)]
      }.joined(separator: "\n")

      if sql != "\n" {
        try self.db.exec(sql)
      }

      if !unidentified.isEmpty {
        throw FeedKitError.feedNotCached(urls: unidentified)
      }
    }
  }

  public func entries(within locators: [EntryLocator]) throws -> [Entry] {
    guard !locators.isEmpty else {
      return []
    }

    return try queue.sync {
      let urls = locators.map { $0.url }

      guard let feedIDsByURLs = try feedIDs(matching: urls) else {
        return []
      }

      let intervals = locators.reduce([(FeedID, Date)]()) { acc, interval in
        let url = interval.url
        let since = interval.since
        if let feedID = feedIDsByURLs[url] {
          return acc + [(feedID, since)]
        } else {
          return acc
        }
      }

      guard let sql = sqlFormatter.SQLToSelectEntries(within: intervals) else {
        return []
      }

      let entries = try FeedCache.queryEntries(
        db, with: sql, using: sqlFormatter)

      return entries ?? []
    }
  }

  // TODO: Cache entryIDs too (by guids)

  public func entries(_ guids: [String]) throws -> [Entry] {
    return try queue.sync {
      let chunks = FeedCache.slice(elements: guids, with: 512)

      return try chunks.reduce([Entry]()) { acc, guids in
        guard let sql = LibrarySQLFormatter.SQLToSelectEntries(by: guids) else {
          return acc
        }
        guard let entries = try FeedCache.queryEntries(
          self.db, with: sql, using: sqlFormatter) else {
            return acc
        }
        return acc + entries
      }
    }
  }

  public func remove(_ urls: [String]) throws {
    try queue.sync {
      guard let dicts = try self.feedIDs(matching: urls) else { return }
      let feedIDs = dicts.map { $0.1 }
      guard let sql = LibrarySQLFormatter.SQLToRemoveFeeds(with: feedIDs) else {
        throw FeedKitError.sqlFormatting
      }
      try db.exec(sql)
      urls.forEach { self.removeFeedID(for: $0) }
    }
  }
  
  public func removeEntries(matching urls: [FeedURL]) throws {
    try queue.sync {
      guard let dicts = try self.feedIDs(matching: urls) else { return }
      let feedIDs = dicts.map { $0.1 }
      guard let sql = LibrarySQLFormatter
        .SQLToRemoveEntries(matching: feedIDs) else {
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
        let pre = term.index(before: term.endIndex)
        let substring = String(term[..<pre])
        return subcached(substring, dict: dict)
      }
      return nil
    }
  }

  /// Update feeds associating them with the specified search term, which is
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
      try update(feeds: feeds) { feed, feedID in
        return self.sqlFormatter.SQLToUpdate(feed: feed, with: feedID, from: .iTunes)
      }
      noSearch[term] = nil
      if let (predecessor, _) = FeedCache.subcached(term, dict: noSuggestions) {
        noSuggestions[predecessor] = nil
      }
    }

    // To stay synchronized with the remote state, before inserting feed
    // identifiers, we delete searches for this term wholesale.

    try queue.sync {
      do {
        let delete = LibrarySQLFormatter.SQLToDeleteSearch(for: term)
        let insert = try feeds.reduce([String]()) { acc, feed in
          let feedID: FeedID
          do {
            feedID = try feed.uid ?? self.feedID(for: feed.url)
          } catch {
            switch error {
            case FeedKitError.feedNotCached(let urls):
              if #available(iOS 10.0, *) {
                os_log("feed not cached: %{public}@", log: Cache.log,  type: .error, urls)
              }
              return acc
            default: throw error
            }
          }
          return acc + [LibrarySQLFormatter.SQLToInsert(feedID: feedID, for: term)]
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
        if FeedCache.stale(ts, ttl: CacheTTL.long.seconds) {
          self.noSearch[term] = nil
          return nil
        } else {
          return []
        }
      }

      let sql = LibrarySQLFormatter.SQLToSelectFeeds(for: term, limit: limit)

      return try FeedCache.queryFeeds(self.db, with: sql, using: self.sqlFormatter)
    }
  }

  /// Returns feeds matching `term` using full-text-search.
  public func feeds(matching term: String, limit: Int) throws -> [Feed]? {
    return try queue.sync {
      let sql = LibrarySQLFormatter.SQLToSelectFeeds(matching: term, limit: limit)
      return try FeedCache.queryFeeds(db, with: sql, using: sqlFormatter)
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
    return try queue.sync { [unowned db, unowned sqlFormatter] in
      let sql = LibrarySQLFormatter.SQLToSelectEntries(matching: term, limit: limit)
      return try FeedCache.queryEntries(db, with: sql, using: sqlFormatter)
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
        let sql = LibrarySQLFormatter.SQLToDeleteSuggestionsMatchingTerm(term)
        try self.db.exec(sql)
        return
      }

      if let (cachedTerm, _) = FeedCache.subcached(term, dict: noSuggestions) {
        noSuggestions[cachedTerm] = nil
      }

      let sql = [
        "BEGIN;",
        suggestions.map {
          LibrarySQLFormatter.SQLToInsertSuggestionForTerm($0.term)
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
          os_log("subcached expired: %{public}@",
                 log: Search.log, type: .debug, term)
          noSuggestions[cachedTerm] = nil
          return nil
        } else {
          os_log("nothing cached: %{public}@", log: Search.log, type: .debug, term)
          return []
        }
      }
      let sql = LibrarySQLFormatter.SQLToSelectSuggestionsForTerm(term, limit: limit)
      return try FeedCache.querySuggestions(db, with: sql, using: sqlFormatter)
    }
  }
}
