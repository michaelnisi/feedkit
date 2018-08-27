//
//  LibrarySQLFormatter.swift
//  FeedKit
//
//  Created by Michael Nisi on 06.02.18.
//  Copyright © 2018 Michael Nisi. All rights reserved.
//

import Foundation
import Skull
import os.log

final class LibrarySQLFormatter: SQLFormatter {}

// MARK: - iTunes

extension LibrarySQLFormatter {
  
  /// Returns SQL that updates the `iTunesItem` of the associated cached feed.
  func SQLToUpdate(iTunes: ITunesItem) -> String {
    let url = SQLString(from: iTunes.url)
    let itunes_guid = SQLString(from: iTunes.iTunesID)
    let img100 = SQLString(from: iTunes.img100)
    let img30 = SQLString(from: iTunes.img30)
    let img60 = SQLString(from: iTunes.img60)
    let img600 = SQLString(from: iTunes.img600)
    
    return """
    UPDATE feed SET \
    itunes_guid = \(itunes_guid), \
    img100 = \(img100), \
    img30 = \(img30), \
    img60 = \(img60), \
    img600 = \(img600) \
    WHERE url = \(url);
    """
  }
  
}

// MARK: - Entries

extension LibrarySQLFormatter {
  
  static func SQLToRemoveEntries(matching feedIDs: [FeedID]) -> String? {
    guard !feedIDs.isEmpty else { return nil }
    let sql = "DELETE FROM entry WHERE feed_id IN(" + feedIDs.map {
      "\($0.rowid)"
    }.joined(separator: ", ") + ");"
    return sql
  }
  
  static func SQLToSelectEntriesByEntryIDs(_ entryIDs: [Int]) -> String? {
    guard !entryIDs.isEmpty else {
      return nil
    }
    let sql = "SELECT * FROM entry_view WHERE" + entryIDs.map {
      " entry_id = \($0)"
    }.joined(separator: " OR") + ";"
    return sql
  }
  
  static func SQLToSelectEntryByGUID(_ guid: String) -> String {
    return "SELECT * FROM entry_view WHERE entry_guid = '\(guid)';"
  }
  
  static func SQLToSelectEntries(by guids: [String]) -> String? {
    guard !guids.isEmpty else { return nil }
    return "SELECT * FROM entry_view WHERE" + guids.map {
      " entry_guid = '\($0)'"
    }.joined(separator: " OR") + ";"
  }
  
  func SQLToInsert(entry: Entry, for feedID: FeedID) -> String {
    let author = SQLString(from: entry.author)
    let duration = SQLString(from: entry.duration)
    let guid = SQLFormatter.SQLString(from: entry.guid)
    let img = SQLString(from: entry.image)
    let length = SQLString(from: entry.enclosure?.length)
    let link = SQLString(from: entry.link)
    let subtitle = SQLString(from: entry.subtitle)
    let summary = SQLString(from: entry.summary)
    let title = SQLString(from: entry.title)
    
    let type = SQLString(from: entry.enclosure?.type.rawValue)
    let updated = SQLString(from: entry.updated)
    let url = SQLString(from: entry.enclosure?.url)
    
    return """
    INSERT OR REPLACE INTO entry(
      author, duration, feed_id, entry_guid, img, length,
      link, subtitle, summary, title, type, updated, url
    ) VALUES(
      \(author), \(duration), \(feedID.rowid), \(guid), \(img), \(length),
      \(link), \(subtitle), \(summary), \(title), \(type), \(updated), \(url)
    );
    """
  }
  
  func SQLToSelectEntries(within intervals: [(FeedID, Date)]) -> String? {
    guard !intervals.isEmpty else {
      return nil
    }
    
    return "SELECT * FROM entry_view WHERE" + intervals.map {
      let feedID = $0.0.rowid
      let updated = df.string(from: $0.1)
      return " feed_id = \(feedID) AND updated > '\(updated)'"
    }.joined(separator: " OR") + " ORDER BY feed_id, updated;"
  }
  
  func enclosureFromRow(_ row: SkullRow) throws -> Enclosure {
    guard let url = row["url"] as? String else {
      throw FeedKitError.invalidEnclosure(reason: "missing url")
    }
    let length = row["length"] as? Int
    guard let rawType = row["type"] as? Int else {
      throw FeedKitError.invalidEnclosure(reason: "missing type")
    }
    guard let type = EnclosureType(rawValue: rawType) else {
      throw FeedKitError.invalidEnclosure(reason: "unknown type: \(rawType)")
    }
    return Enclosure(url: url, length: length, type: type)
  }
  
  /// Create an entry from a database row.
  ///
  /// - Parameter row: The database row to retrieve values from.
  ///
  /// - Returns: The resulting entry.
  ///
  /// - Throws: If this throws our database got corrupted, thus, in this case,
  /// users of this function are well advised to crash. The only reason for not
  /// crashing directly from here is debugging during development.
  func entryFromRow(_ row: SkullRow) throws -> Entry {
    let author = row["author"] as? String ?? row["feed_author"] as? String
    let duration = row["duration"] as? Int
    let enclosure = try enclosureFromRow(row)
    let feed = row["feed"] as! FeedURL
    let feedImage = row["feed_image"] as? String
    let feedTitle = row["feed_title"] as! String
    let guid = row["entry_guid"] as! String
    let iTunes = LibrarySQLFormatter.iTunesItem(from: row, url: feed)
    let image = row["img"] as? String
    let link = row["link"] as? String
    let subtitle = row["subtitle"] as? String
    let summary = row["summary"] as? String
    let title = row["title"] as! String
    let ts = date(from: row["ts"] as? String)
    
    guard let updated = date(from: row["updated"] as? String) else {
      throw FeedKitError.invalidEntry(reason: "missing updated")
    }
    
    return Entry(
      author: author,
      duration: duration,
      enclosure: enclosure,
      feed: feed,
      feedImage: feedImage,
      feedTitle: feedTitle,
      guid: guid,
      iTunes: iTunes,
      image: image,
      link: link,
      originalURL: nil,
      subtitle: subtitle,
      summary: summary,
      title: title,
      ts: ts,
      updated: updated
    )
  }
  
}

// MARK: - Feeds

extension LibrarySQLFormatter {
  
  static func toRemoveFeed(with guid: Int) -> String {
    return "DELETE FROM feed WHERE itunes_guid = \(guid);"
  }
  
  static func SQLToSelectFeeds(by feedIDs: [FeedID]) -> String? {
    guard !feedIDs.isEmpty else {
      return nil
    }
    let rowids = feedIDs.map { $0.rowid }
    let sql = "SELECT * FROM feed WHERE" + rowids.map {
      " feed_id = \($0)"
    }.joined(separator: " OR") + ";"
    return sql
  }
  
  static func SQLToRemoveFeeds(with feedIDs: [FeedID]) -> String? {
    guard !feedIDs.isEmpty else { return nil }
    let sql = "DELETE FROM feed WHERE rowid IN(" + feedIDs.map {
      "\($0.rowid)"
    }.joined(separator: ", ") + ");"
    return sql
  }
  
  static func SQLToSelectFeedIDFromURLView(_ url: String) -> String {
    let s = SQLFormatter.SQLString(from: url)
    return "SELECT * FROM url_view WHERE url = \(s);"
  }
  
  static func SQLToInsert(feedID: FeedID, for term: String) -> String {
    let s = SQLFormatter.SQLString(from: term)
    return "INSERT OR REPLACE INTO search(feed_id, term) VALUES(\(feedID.rowid), \(s));"
  }
  
  /// Feeds can enter from their original host or from iTunes.
  enum FeedOrigin {
    case iTunes, hosted
    
    /// Table columns that should not be set to `NULL` if associated input
    /// property is `nil`.
    var columns: [String] {
      switch self {
      case .hosted:
        return ["img100", "img30", "img60", "img600", "itunes_guid", "updated"]
      case .iTunes:
        return ["summary", "link"]
      }
    }
  }
  
  func SQLToUpdate(feed: Feed, with feedID: FeedID, from type: FeedOrigin) -> String {
    return SQLToUpdate(feed: feed, with: feedID, kept: type.columns)
  }
  
  private func column(name: String, value: String, keep: Bool = false) -> String? {
    guard keep else {
      return "\(name) = \(value)"
    }
    return value != "NULL" ? "\(name) = \(value)" : nil
  }
  
  private func SQLToUpdate(
    feed: Feed, with feedID: FeedID, kept: [String]) -> String {
    let author = SQLString(from: feed.author)
    let guid = SQLString(from: feed.iTunes?.iTunesID)
    let img = SQLString(from: feed.image)
    let img100 = SQLString(from: feed.iTunes?.img100)
    let img30 = SQLString(from: feed.iTunes?.img30)
    let img60 = SQLString(from: feed.iTunes?.img60)
    let img600 = SQLString(from: feed.iTunes?.img600)
    let link = SQLString(from: feed.link)
    let summary = SQLString(from: feed.summary)
    let title = SQLString(from: feed.title)
    
    if feed.updated == nil || feed.updated == Date(timeIntervalSince1970: 0) {
      os_log("missing proper updated date in feed: %{public}@", feed.description)
    }
    
    let updated = SQLString(from: feed.updated)
    let url = SQLString(from: feed.url)
    
    let props = [
      ("author", author),
      ("itunes_guid", guid),
      ("img", img),
      ("img100", img100),
      ("img30", img30),
      ("img60", img60),
      ("img600", img600),
      ("link", link),
      ("summary", summary),
      ("title", title),
      ("updated", updated),
      ("url", url)
    ]
    
    let vars = props.reduce([String]()) { acc, prop in
      let (name, value) = prop
      let keep = kept.contains(name)
      guard let col = column(name: name, value: value, keep: keep) else {
        return acc
      }
      return acc + [col]
      }.joined(separator: ", ")
    
    let sql = "UPDATE feed SET \(vars) WHERE feed_id = \(feedID.rowid);"
    
    return sql
  }
  
  func SQLToInsert(feed: Feed) -> String {
    let author = SQLString(from: feed.author)
    let guid = SQLString(from: feed.iTunes?.iTunesID)
    let img = SQLString(from: feed.image)
    let img100 = SQLString(from: feed.iTunes?.img100)
    let img30 = SQLString(from: feed.iTunes?.img30)
    let img60 = SQLString(from: feed.iTunes?.img60)
    let img600 = SQLString(from: feed.iTunes?.img600)
    let link = SQLString(from: feed.link)
    let summary = SQLString(from: feed.summary)
    let title = SQLString(from: feed.title)
    let updated = SQLString(from: feed.updated)
    let url = SQLString(from: feed.url)
    
    return """
    INSERT INTO feed(
      author, itunes_guid, img, img100, img30, img60, img600,
      link, summary, title, updated, url
    ) VALUES(
      \(author), \(guid), \(img), \(img100), \(img30), \(img60), \(img600),
      \(link), \(summary), \(title), \(updated), \(url)
    );
    """
  }
  
  static func feedID(from row: SkullRow) throws -> FeedID {
    guard
      let rowid = row["feed_id"] as? Int64,
      let url = row["url"] as? String else {
      throw FeedKitError.unidentifiedFeed
    }
    return FeedID(rowid: rowid, url: url)
  }
  
  func feedFromRow(_ row: SkullRow) throws -> Feed {
    let author = row["author"] as? String
    let image = row["img"] as? String
    let link = row["link"] as? String
    let summary = row["summary"] as? String
    
    guard let title = row["title"] as? String else {
      throw FeedKitError.invalidFeed(reason: "missing title")
    }
    
    let ts = date(from: row["ts"] as? String)
    let uid = try LibrarySQLFormatter.feedID(from: row)
    let updated = date(from: row["updated"] as? String)
    
    guard let url = row["url"] as? String else {
      throw FeedKitError.invalidFeed(reason: "missing url")
    }
    
    let iTunes = SQLFormatter.iTunesItem(from: row, url: url)
    
    return Feed(
      author: author,
      iTunes: iTunes,
      image: image,
      link: link,
      originalURL: nil,
      summary: summary,
      title: title,
      ts: ts,
      uid: uid,
      updated: updated,
      url: url
    )
  }
  
}

// MARK: - Searching

extension LibrarySQLFormatter {
  
  static func makeTokenQueryExpression(string: String) -> String {
    let t = SQLFormatter.FTSString(from: string)
    return SQLFormatter.SQLString(from: "\(t)*")
  }
  
  static func SQLToInsertSuggestionForTerm(_ term: String) -> String {
    let s = SQLFormatter.SQLString(from: term)
    return "INSERT OR REPLACE INTO sug(term) VALUES(\(s));"
  }
  
  static func SQLToSelectSuggestionsForTerm(_ term: String, limit: Int) -> String {
    let exp = makeTokenQueryExpression(string: term)
    return """
    SELECT * FROM sug WHERE rowid IN (
      SELECT rowid FROM sug_fts
      WHERE term MATCH \(exp)
    ) ORDER BY ts DESC LIMIT \(limit);
    """
  }
  
  static func SQLToDeleteSuggestionsMatchingTerm(_ term: String) -> String {
    let exp = makeTokenQueryExpression(string: term)
    return """
    DELETE FROM sug WHERE rowid IN (
      SELECT rowid FROM sug_fts
      WHERE term MATCH \(exp)
    );
    """
  }
  
  func suggestionFromRow(_ row: SkullRow) throws -> Suggestion {
    guard let term = row["term"] as? String else {
      throw FeedKitError.invalidSuggestion(reason: "missing term")
    }
    guard let rowTs = row["ts"] as? String, let ts = date(from: rowTs) else {
      throw FeedKitError.invalidSuggestion(reason: "missing ts")
    }
    return Suggestion(term: term, ts: ts)
  }
  
  static func SQLToSelectFeeds(for term: String, limit: Int) -> String {
    let s = SQLFormatter.SQLString(from: term)
    return """
    SELECT DISTINCT * FROM search_view WHERE searchid IN (
      SELECT rowid FROM search_fts
      WHERE term = \(s)
    ) LIMIT \(limit);
    """
  }
  
  static func SQLToSelectFeeds(matching term: String, limit: Int) -> String {
    let exp = makeTokenQueryExpression(string: term)
    return """
    SELECT DISTINCT * FROM feed WHERE feed_id IN (
      SELECT rowid FROM feed_fts
      WHERE feed_fts MATCH \(exp)
    ) ORDER BY ts DESC LIMIT \(limit);
    """
  }
  
  static func SQLToSelectEntries(matching term: String, limit: Int) -> String {
    let exp = makeTokenQueryExpression(string: term)
    return """
    SELECT DISTINCT * FROM entry_view WHERE entry_id IN (
      SELECT rowid FROM entry_fts
      WHERE summary MATCH \(exp) LIMIT 1000
    ) ORDER BY updated DESC LIMIT \(limit);
    """
  }
  
  static func SQLToDeleteSearch(for term: String) -> String {
    let s = SQLFormatter.SQLString(from: term)
    return "DELETE FROM search WHERE term = \(s);"
  }
  
}
