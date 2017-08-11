//
//  sql.swift - translate to and from SQLite
//  FeedKit
//
//  Created by Michael Nisi on 27/10/15.
//  Copyright © 2015 Michael Nisi. All rights reserved.
//

import Foundation
import Skull

// MARK: - Stateful Formatting

/// `SQLFormatter` produces SQL statements from FeedKit structures and creates 
/// and transforms SQLite rows into FeedKit value objects. Mostly via stateless
/// functions, the only reason for this being a class is to share a date
/// formatter.
final class SQLFormatter {
  
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
  /// - Returns: A date or `nil`.
  func date(from string: String?) -> Date? {
    guard let str = string else {
      return nil
    }
    return df.date(from: str)
  }

  func SQLToInsertFeed(_ feed: Feed) -> String {
    let author = stringFromAny(feed.author)
    let guid = stringFromAny(feed.iTunes?.guid)
    let img = stringFromAny(feed.image)
    let img100 = stringFromAny(feed.iTunes?.img100)
    let img30 = stringFromAny(feed.iTunes?.img30)
    let img60 = stringFromAny(feed.iTunes?.img60)
    let img600 = stringFromAny(feed.iTunes?.img600)
    let link = stringFromAny(feed.link)
    let summary = stringFromAny(feed.summary)
    let title = stringFromAny(feed.title)
    let updated = stringFromAny(feed.updated)
    let url = stringFromAny(feed.url)

    let sql =
    "INSERT INTO feed(" +
    "author, guid, " +
    "img, img100, img30, img60, img600, " +
    "link, summary, title, updated, url) VALUES(" +
    "\(author), \(guid), " +
    "\(img), \(img100), \(img30), \(img60), \(img600), " +
    "\(link), \(summary), \(title), \(updated), \(url)" +
    ");"

    return sql
  }

  private func column(name: String, value: String, keep: Bool = false) -> String? {
    guard keep else {
      return "\(name) = \(value)"
    }
    return value != "NULL" ? "\(name) = \(value)" : nil
  }

  func SQLToUpdateFeed(_ feed: Feed, withID rowid: Int) -> String {
    let author = stringFromAny(feed.author)
    let guid = stringFromAny(feed.iTunes?.guid)
    let img = stringFromAny(feed.image)
    let img100 = stringFromAny(feed.iTunes?.img100)
    let img30 = stringFromAny(feed.iTunes?.img30)
    let img60 = stringFromAny(feed.iTunes?.img60)
    let img600 = stringFromAny(feed.iTunes?.img600)
    let link = stringFromAny(feed.link)
    let summary = stringFromAny(feed.summary)
    let title = stringFromAny(feed.title)
    let updated = stringFromAny(feed.updated)
    let url = stringFromAny(feed.url)

    let props = [
      ("author", author), ("guid", guid), ("img", img), ("img100", img100),
      ("img30", img30), ("img60", img60), ("img600", img600), ("link", link),
      ("summary", summary), ("title", title), ("updated", updated), ("url", url)
    ]

    // TODO: Find more effective way to do this
    //
    // There must be a better way using flatMap.

    // If the feed doesn’t come from iTunes, it doesn’t contain the URLs of the
    // prescaled and we don’t want to nullify them.
    let kept = ["guid", "img100", "img30", "img60", "img600"]

    let vars = props.reduce([String]()) { acc, prop in
      let (name, value) = prop
      let keep = kept.contains(name)
      guard let col = column(name: name, value: value, keep: keep) else {
        return acc
      }
      return acc + [col]

    }.joined(separator: ", ")

    let sql = "UPDATE feed SET \(vars) WHERE rowid = \(rowid);"

    return sql
  }

  func SQLToInsertEntry(_ entry: Entry, forFeedID feedID: Int) -> String {
    let author = stringFromAny(entry.author)
    let duration = stringFromAny(entry.duration)
    let feedid = stringFromAny(feedID)
    let guid = SQLFormatter.SQLString(from: entry.guid) // TODO: Review
    let img = stringFromAny(entry.image)
    let length = stringFromAny(entry.enclosure?.length)
    let link = stringFromAny(entry.link)
    let subtitle = stringFromAny(entry.subtitle)
    let summary = stringFromAny(entry.summary)
    let title = stringFromAny(entry.title)

    let type = stringFromAny(entry.enclosure?.type.rawValue)
    let updated = stringFromAny(entry.updated)
    let url = stringFromAny(entry.enclosure?.url)

    let sql =
    "INSERT OR REPLACE INTO entry(" +
    "author, duration, feedid, guid, img, length, " +
    "link, subtitle, summary, title, type, updated, url) VALUES(" +
    "\(author), \(duration), \(feedid), \(guid), \(img), \(length), " +
    "\(link), \(subtitle), \(summary), \(title), \(type), \(updated), \(url)" +
    ");"
    return sql
  }

  // TODO: Rename to string(from:)

  func stringFromAny(_ obj: Any?) -> String {
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
  
  // TODO: Add parameters for paging: DESC LIMIT 25

  func SQLToSelectEntriesByIntervals(_ intervals: [(Int, Date)]) -> String? {
    guard !intervals.isEmpty else {
      return nil
    }
    
    return "SELECT * FROM entry_view WHERE" + intervals.map {
      let feedID = $0.0
      let updated = df.string(from: $0.1)
      return " feedid = \(feedID) AND updated > '\(updated)'"
    }.joined(separator: " OR") + " ORDER BY feedid, updated;"
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
    let uid = row["uid"] as? Int
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
    let guid = row["guid"] as! String
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

// TODO: Review map functions regarding limits
//
// Maximum Depth Of An Expression Tree https://www.sqlite.org/limits.html
// Here's the deal, basically every time an array of identifiers is longer than
// 1000, these will break.

private func selectRowsByUIDs(_ table: String, ids: [Int]) -> String? {
  guard !ids.isEmpty else { return nil }
  let sql = "SELECT * FROM \(table) WHERE" + ids.map {
    " uid = \($0)"
    }.joined(separator: " OR") + ";"
  return sql
}

extension SQLFormatter {
  
  static func toRemoveFeed(with guid: Int) -> String {
    return "DELETE FROM feed WHERE guid = \(guid);"
  }
  
  static func SQLToSelectEntriesByEntryIDs(_ entryIDs: [Int]) -> String? {
    return selectRowsByUIDs("entry_view", ids: entryIDs)
  }
  
  static func SQLToSelectFeedsByFeedIDs(_ feedIDs: [Int]) -> String? {
    return selectRowsByUIDs("feed_view", ids: feedIDs)
  }
  
  static func SQLToSelectEntryByGUID(_ guid: String) -> String {
    return "SELECT * FROM entry_view WHERE guid = '\(guid)';"
  }

  static func SQLToSelectEntries(by guids: [String]) -> String? {
    guard !guids.isEmpty else { return nil }
    return "SELECT * FROM entry_view WHERE" + guids.map {
      " guid = '\($0)'"
    }.joined(separator: " OR") + ";"
  }
  
  // TODO: Test if entries are removed when their feeds are removed
  
  static func SQLToRemoveFeedsWithFeedIDs(_ feedIDs: [Int]) -> String? {
    guard !feedIDs.isEmpty else { return nil }
    let sql = "DELETE FROM feed WHERE rowid IN(" + feedIDs.map {
      "\($0)"
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
  
  // TODO: Ensure all strings pass through SQLStringFromString
  
  static func SQLToSelectFeedIDFromURLView(_ url: String) -> String {
    let s = SQLFormatter.SQLString(from: url)
    return "SELECT feedid FROM url_view WHERE url = \(s);"
  }
  
  static func SQLToInsertFeedID(_ feedID: Int, forTerm term: String) -> String {
    let s = SQLFormatter.SQLString(from: term)
    return "INSERT OR REPLACE INTO search(feedID, term) VALUES(\(feedID), \(s));"
  }
}

// MARK: - Searching

// TODO: Validate search term to avoid: "malformed MATCH expression: [\"*]"

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
  
  static func iTunesItem(from row: SkullRow) -> ITunesItem? {
    guard
      let guid = row["guid"] as? Int ?? row["feed_guid"] as? Int,
      let img100 = row["img100"] as? String,
      let img30 = row["img30"] as? String,
      let img60 = row["img60"] as? String,
      let img600 = row["img600"] as? String else {
      return nil
    }
    
    return ITunesItem(
      guid: guid,
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
    guard let ts = row["ts"] as? String else {
      throw FeedKitError.invalidSuggestion(reason: "missing ts")
    }
    return Suggestion(term: term, ts: date(from: ts))
  }
  
  // TODO: Review SELECT DISTINCT in search queries
  // TODO: Escape search term
  
  static func SQLToSelectFeedsByTerm(_ term: String, limit: Int) -> String {
    let s = SQLFormatter.SQLString(from: term)
    let sql = "SELECT DISTINCT * FROM search_view WHERE searchid IN (" +
      "SELECT rowid FROM search_fts " +
      "WHERE term = \(s)) " +
      "LIMIT \(limit);"
    return sql
  }
  
  static func SQLToSelectFeedsMatchingTerm(_ term: String, limit: Int) -> String {
    let s = SQLFormatter.SQLString(from: "\(term)*")
    let sql = "SELECT DISTINCT * FROM feed_view WHERE uid IN (" +
      "SELECT rowid FROM feed_fts " +
      "WHERE feed_fts MATCH \(s)) " +
      "ORDER BY ts DESC " +
      "LIMIT \(limit);"
    return sql
  }
  
  static func SQLToSelectEntries(matching term: String, limit: Int) -> String {
    let s = SQLFormatter.SQLString(from: "\(term)*")
    let sql = "SELECT DISTINCT * FROM entry_view WHERE uid IN (" +
      "SELECT rowid FROM entry_fts " +
      "WHERE entry_fts MATCH \(s)) " +
      "ORDER BY updated DESC " +
      "LIMIT \(limit);"
    return sql
  }
  
  static func SQLToDeleteSearch(for term: String) -> String {
    let s = SQLFormatter.SQLString(from: term)
    return "DELETE FROM search WHERE term=\(s);"
  }
  
}

// MARK: - Syncing

extension SQLFormatter {
  
  static func SQLToDeleteRecords(with names: [String]) -> String? {
    guard !names.isEmpty else {
      return nil
    }
    return "DELETE FROM record WHERE record_name IN(" + names.map {
      "'\($0)'"
    }.joined(separator: ", ") + ");"
  }
  
  func SQLToQueueSynced(locator synced: Synced) -> String {
    switch synced {
    case .entry(let locator, let queuedAt, let name, let tag):
      let guid = stringFromAny(locator.guid)
      let url = stringFromAny(locator.url)
      let since = stringFromAny(locator.since)
      
      let ts = stringFromAny(queuedAt)
      let name = stringFromAny(name)
      let tag = stringFromAny(tag)
      
      return [
        "INSERT OR REPLACE INTO record(record_name, change_tag) VALUES(\(name), \(tag));",
        "INSERT OR REPLACE INTO queued_entry(guid, url, since, ts, record_name) VALUES(" +
        "\(guid), \(url), \(since), \(ts), \(name));"
      ].joined(separator: "\n");
    }
  }
  // C494AD71-AB58-4A00-BFDE-2551A32BC3E4
  static let SQLToSelectLocallyQueuedEntries = "SELECT * FROM locally_queued_entry;"
  
}

// MARK: - Queueing

extension SQLFormatter {

  static let SQLToSelectAllQueued = "SELECT * FROM queued_entry_view ORDER BY ts DESC;"
  
  static func SQLToUnqueue(guids: [String]) -> String? {
    guard !guids.isEmpty else {
      return nil
    }
    return "DELETE FROM queued_entry WHERE guid IN(" + guids.map {
      "'\($0)'"
    }.joined(separator: ", ") + ");"
  }
  
  func SQLToQueueEntry(locator entry: QueueEntryLocator) -> String {
    let guid = stringFromAny(entry.guid)
    let url = stringFromAny(entry.url)
    let since = stringFromAny(entry.since)
    
    return "INSERT OR REPLACE INTO queued_entry(guid, url, since) " +
      "VALUES(\(guid), \(url), \(since));"
  }
  
  func queuedLocator(from row: SkullRow) -> Queued {
    let url = row["url"] as! String
    let since = date(from: row["since"] as? String)!
    let guid = row["guid"] as? String
    let locator = EntryLocator(url: url, since: since, guid: guid)
    
    let ts = date(from: row["ts"] as? String)!
    
    return Queued.locator(locator, ts)
  }
}

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
