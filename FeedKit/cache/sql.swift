//
//  sql.swift - translate to and from SQLite
//  FeedKit
//
//  Created by Michael Nisi on 27/10/15.
//  Copyright © 2015 Michael Nisi. All rights reserved.
//

import Foundation
import Skull
import os.log

// MARK: - Stateful Formatting

/// `SQLFormatter` produces SQL statements from FeedKit structures and creates
/// and transforms SQLite rows into FeedKit value objects. Mostly via stateless
/// functions, the only reason for this being a class is to share a date
/// formatter.
///
/// This formatter doesn‘t return explicit transactions, this is left to the
/// call site, which knows more about the context, the formatted SQL is going
/// to be used in.
///
/// Remember to respect [SQLite limits](https://www.sqlite.org/limits.html) when
/// using this class. Some of its functions might exceed the maximum depth of an
/// SQLite expression tree Here's the deal, basically every time an array of
/// identifiers is longer than 1000, we have to slice it down, for example, with
/// `Cache.slice(elements:, with:)`.
final class SQLFormatter {
  
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

  public static var shared = SQLFormatter()

  lazy private var df: DateFormatter = {
    let df = DateFormatter()
    df.timeZone = TimeZone(secondsFromGMT: 0)
    df.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return df
  }()

  /// Returns now as an SQLite datetime timestamp string.
  func now() -> String {
    return df.string(from: Date())
  }

  /// Returns a date from an SQLite datetime timestamp string.
  ///
  /// - Parameter string: A `'yyyy-MM-dd HH:mm:ss'` formatted timestamp.
  ///
  /// - Returns: A date or `nil`.
  func date(from string: String?) -> Date? {
    guard let str = string else {
      return nil
    }
    return df.date(from: str)
  }

  /// Produces an SQL formatted strings.
  func SQLString(from obj: Any?) -> String {
    switch obj {
    case nil:
      return "NULL"
    case is Int, is Double:
      return "\(obj!)"
    case let value as String:
      return SQLFormatter.SQLString(from: value)
    case let value as Date:
      return "'\(df.string(from: value))'"
    case let value as URL:
      return SQLFormatter.SQLString(from: value.absoluteString)
    default:
      return "NULL"
    }
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
      os_log("** warning: overriding date: %{public}@", type: .debug,
             String(reflecting: feed))
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
  
  func SQLToUpdate(feed: Feed, with feedID: FeedID, from type: FeedOrigin) -> String {
    return SQLToUpdate(feed: feed, with: feedID, kept: type.columns)
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

  func feedID(from row: SkullRow) throws -> FeedID {
    guard
      let rowid = row["feed_id"] as? Int64,
      let url = row["url"] as? String else {
      throw FeedKitError.unidentifiedFeed
    }
    return FeedID(rowid: rowid, url: url)
  }

  func feedFromRow(_ row: SkullRow) throws -> Feed {
    let author = row["author"] as? String
    let iTunes = SQLFormatter.iTunesItem(from: row)
    let image = row["img"] as? String
    let link = row["link"] as? String
    let summary = row["summary"] as? String

    guard let title = row["title"] as? String else {
      throw FeedKitError.invalidFeed(reason: "missing title")
    }

    let ts = date(from: row["ts"] as? String)
    let uid = try feedID(from: row)
    let updated = date(from: row["updated"] as? String)

    guard let url = row["url"] as? String else {
      throw FeedKitError.invalidFeed(reason: "missing url")
    }

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
    let feed = row["feed"] as! String
    let feedImage = row["feed_image"] as? String
    let feedTitle = row["feed_title"] as! String
    let guid = row["entry_guid"] as! String
    let iTunes = SQLFormatter.iTunesItem(from: row)
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

// MARK: - General Use

extension SQLFormatter {

  static func toRemoveFeed(with guid: Int) -> String {
    return "DELETE FROM feed WHERE itunes_guid = \(guid);"
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

  static func SQLToSelectEntryByGUID(_ guid: String) -> String {
    return "SELECT * FROM entry_view WHERE entry_guid = '\(guid)';"
  }

  static func SQLToSelectEntries(by guids: [String]) -> String? {
    guard !guids.isEmpty else { return nil }
    return "SELECT * FROM entry_view WHERE" + guids.map {
      " entry_guid = '\($0)'"
    }.joined(separator: " OR") + ";"
  }

  static func SQLToRemoveFeeds(with feedIDs: [FeedID]) -> String? {
    guard !feedIDs.isEmpty else { return nil }
    let sql = "DELETE FROM feed WHERE rowid IN(" + feedIDs.map {
      "\($0.rowid)"
    }.joined(separator: ", ") + ");"
    return sql
  }

  /// The SQL standard specifies that single-quotes, and double quotes for that
  /// matter in strings are escaped by putting two single quotes in a row.
  static func SQLString(from string: String) -> String {
    let s = string.replacingOccurrences(
      of: "'",
      with: "''",
      options: String.CompareOptions.literal,
      range: nil
    )

    return "'\(s)'"
  }

  static func SQLToSelectFeedIDFromURLView(_ url: String) -> String {
    let s = SQLFormatter.SQLString(from: url)
    return "SELECT * FROM url_view WHERE url = \(s);"
  }

  static func SQLToInsert(feedID: FeedID, for term: String) -> String {
    let s = SQLFormatter.SQLString(from: term)
    return "INSERT OR REPLACE INTO search(feed_id, term) VALUES(\(feedID.rowid), \(s));"
  }
}

// MARK: - Searching

extension SQLFormatter {

  static func SQLToInsertSuggestionForTerm(_ term: String) -> String {
    let s = SQLFormatter.SQLString(from: term)
    return "INSERT OR REPLACE INTO sug(term) VALUES(\(s));"
  }

  static func SQLToSelectSuggestionsForTerm(_ term: String, limit: Int) -> String {
    let s = SQLFormatter.SQLString(from: "\(term)*")
    let sql = "SELECT * FROM sug WHERE rowid IN (" +
      "SELECT rowid FROM sug_fts " +
      "WHERE term MATCH \(s)) " +
      "ORDER BY ts DESC " +
      "LIMIT \(limit);"
    return sql
  }

  static func SQLToDeleteSuggestionsMatchingTerm(_ term: String) -> String {
    let s = SQLFormatter.SQLString(from: "\(term)*")
    let sql = "DELETE FROM sug " +
      "WHERE rowid IN (" +
      "SELECT rowid FROM sug_fts WHERE term MATCH \(s));"
    return sql
  }

  /// Returns optional iTunes item from feed or entry row.
  static func iTunesItem(from row: SkullRow) -> ITunesItem? {
    guard
      let iTunesID = row["itunes_guid"] as? Int,
      let img100 = row["img100"] as? String,
      let img30 = row["img30"] as? String,
      let img60 = row["img60"] as? String,
      let img600 = row["img600"] as? String else {
      return nil
    }

    return ITunesItem(
      iTunesID: iTunesID,
      img100: img100,
      img30: img30,
      img60: img60,
      img600: img600
    )
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
    let sql = "SELECT DISTINCT * FROM search_view WHERE searchid IN (" +
      "SELECT rowid FROM search_fts " +
      "WHERE term = \(s)) " +
      "LIMIT \(limit);"
    return sql
  }

  static func SQLToSelectFeeds(matching term: String, limit: Int) -> String {
    let s = SQLFormatter.SQLString(from: "\(term)*")
    return """
    SELECT DISTINCT * FROM feed WHERE feed_id IN (
      SELECT rowid FROM feed_fts
      WHERE feed_fts MATCH \(s)
    ) ORDER BY ts DESC LIMIT \(limit);
    """
  }

  static func SQLToSelectEntries(matching term: String, limit: Int) -> String {
    // Limiting search to title for shorter latency.
    let s = SQLFormatter.SQLString(from: "\(term)*")
    return """
    SELECT DISTINCT * FROM entry_view WHERE entry_id IN (
      SELECT rowid FROM entry_fts
      WHERE title MATCH \(s)
    ) ORDER BY updated DESC LIMIT \(limit);
    """
  }

  static func SQLToDeleteSearch(for term: String) -> String {
    let s = SQLFormatter.SQLString(from: term)
    return "DELETE FROM search WHERE term = \(s);"
  }

}


