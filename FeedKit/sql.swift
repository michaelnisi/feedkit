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

  func SQLToUpdate(feed: Feed, with feedID: FeedID) -> String {
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

    // If the feed doesn’t come from iTunes, it has no GUID and doesn’t
    // contain URLs of the prescaled images. We don’t want to explicitly
    // set these to 'NULL'.
    let kept = ["itunes_guid", "img100", "img30", "img60", "img600"]

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
    let sql = "SELECT DISTINCT * FROM feed WHERE feed_id IN (" +
      "SELECT rowid FROM feed_fts " +
      "WHERE feed_fts MATCH \(s)) " +
      "ORDER BY ts DESC " +
      "LIMIT \(limit);"
    return sql
  }

  static func SQLToSelectEntries(matching term: String, limit: Int) -> String {
    let s = SQLFormatter.SQLString(from: "\(term)*")
    let sql = "SELECT DISTINCT * FROM entry_view WHERE entry_id IN (" +
      "SELECT rowid FROM entry_fts " +
      "WHERE entry_fts MATCH \(s)) " +
      "ORDER BY updated DESC " +
      "LIMIT \(limit);"
    return sql
  }

  static func SQLToDeleteSearch(for term: String) -> String {
    let s = SQLFormatter.SQLString(from: term)
    return "DELETE FROM search WHERE term = \(s);"
  }

}

// MARK: - Queueing

extension SQLFormatter {

  static let SQLToSelectAllQueued =
    "SELECT * FROM queued_entry_view ORDER BY ts DESC;"

  static let SQLToSelectAllPrevious =
    "SELECT * FROM prev_entry_view ORDER BY ts DESC LIMIT 25;"

  static func SQLToUnqueue(guids: [String]) -> String? {
    guard !guids.isEmpty else {
      return nil
    }
    return "DELETE FROM queued_entry WHERE entry_guid IN(" + guids.map {
      "'\($0)'"
    }.joined(separator: ", ") + ");"
  }

  func SQLToQueue(entry: EntryLocator) throws -> String {
    guard let guid = entry.guid else {
      throw FeedKitError.invalidEntryLocator(reason: "missing guid")
    }

    let url = SQLString(from: entry.url)
    let since = SQLString(from: entry.since)
    let guidStr = SQLFormatter.SQLString(from: guid)

    return """
    INSERT OR REPLACE INTO entry(
      entry_guid, feed_url, since
    ) VALUES(
      \(guidStr), \(url), \(since)
    );
    INSERT OR REPLACE INTO queued_entry(entry_guid) VALUES(\(guidStr));
    """
  }

  func queuedLocator(from row: SkullRow) -> Queued {
    let url = row["feed_url"] as! String
    let since = date(from: row["since"] as? String)!
    let guid = row["entry_guid"] as? String
    let locator = EntryLocator(url: url, since: since, guid: guid)

    let ts = date(from: row["ts"] as? String)!

    return Queued.entry(locator, ts)
  }
}

// MARK: - Subscribing

extension SQLFormatter {

  /// Returns a tuple of SQL strings from `subscription` properties.
  func strings(from subscription: Subscription)
    -> (String, String, String, String, String) {
    let iTunesID = SQLString(from: subscription.iTunes?.iTunesID)
    let img100 = SQLString(from: subscription.iTunes?.img100)
    let img30 = SQLString(from: subscription.iTunes?.img30)
    let img60 = SQLString(from: subscription.iTunes?.img60)
    let img600 = SQLString(from: subscription.iTunes?.img600)
    return (iTunesID, img100, img30, img60, img600)
  }

  /// The SQL to fetch all feed subscriptions.
  static let SQLToSelectSubscriptions =
    "SELECT * from subscribed_feed_view;"

  /// SQL to select URLs of unrelated feeds that can safely be deleted.
  static let SQLToSelectZombieFeedURLs = "SELECT * from zombie_feed_url_view;"

  /// Returns SQL to replace `subscription`.
  func SQLToReplace(subscription: Subscription) -> String {
    let url = SQLFormatter.SQLString(from: subscription.url)

    let (iTunesID, img100, img30, img60, img600) = strings(from: subscription)

    let sql = """
    INSERT OR REPLACE INTO feed(
      feed_url, itunes_guid, img100, img30, img60, img600
    ) VALUES(
      \(url), \(iTunesID), \(img100), \(img30), \(img60), \(img600)
    );
    INSERT OR REPLACE INTO subscribed_feed(feed_url) VALUES(\(url));
    """
    return sql
  }

  /// Returns SQL to delete subscriptions for `urls`.
  static func SQLToDelete(subscribed urls: [FeedURL]) -> String {
    return "DELETE FROM subscribed_feed WHERE feed_url IN(" +
      urls.map { "'\($0)'"}.joined(separator: ", ") +
    ");"
  }

  func subscription(from row: SkullRow) -> Subscription {
    let url = row["feed_url"] as! String
    let iTunes = SQLFormatter.iTunesItem(from: row)
    let ts = date(from: row["ts"] as? String)
    return Subscription(url: url, iTunes: iTunes, ts: ts)
  }

}

// MARK: - Syncing

extension SQLFormatter {
  
  static var SQLToDeleteQueued = "DELETE FROM queued_entry;"
  
  static var SQLToRemoveLibrary = """
  DELETE FROM feed;
  DELETE FROM subscribed_feed;
  DELETE FROM record WHERE record_name IN (SELECT record_name FROM zombie_record_name_view);
  """
  
  static var SQLToRemoveQueue = """
  DELETE FROM entry;
  DELETE FROM queued_entry;
  DELETE FROM prev_entry;
  DELETE FROM record WHERE record_name IN (SELECT record_name FROM zombie_record_name_view);
  """

  static var SQLToDeleteZombies = """
  DELETE FROM record WHERE record_name IN (SELECT record_name FROM zombie_record_name_view);
  DELETE FROM feed WHERE feed_url IN(SELECT feed_url FROM zombie_feed_url_view);
  DELETE FROM entry WHERE entry_guid IN(SELECT entry_guid FROM zombie_entry_guid_view);
  """

  // Examplary iCloud record name: C494AD71-AB58-4A00-BFDE-2551A32BC3E4

  static func SQLToDeleteRecords(with names: [String]) -> String {
    return "DELETE FROM record WHERE record_name IN(" + names.map {
      "'\($0)'"
    }.joined(separator: ", ") + ");"
  }

  func SQLToReplace(synced: Synced) throws -> String {
    switch synced {
    case .subscription(let subscription, let record):
      let url = SQLString(from: subscription.url)

      let (iTunesID, img100, img30, img60, img600) = strings(from: subscription)
      let ts = SQLString(from: subscription.ts)

      let recordName = SQLString(from: record.recordName)
      let zoneName = SQLString(from: record.zoneName)
      let tag = SQLString(from: record.changeTag)

      let sql = """
      INSERT OR REPLACE INTO record(
        record_name, zone_name, change_tag
      ) VALUES(
        \(recordName), \(zoneName), \(tag)
      );

      INSERT OR REPLACE INTO feed(
        feed_url, itunes_guid, img100, img30, img60, img600
      ) VALUES(
        \(url), \(iTunesID), \(img100), \(img30), \(img60), \(img600)
      );

      INSERT OR REPLACE INTO subscribed_feed(
        feed_url, record_name, ts
      ) VALUES(
        \(url), \(recordName), \(ts)
      );
      """
      return sql
    case .entry(let locator, let queuedAt, let record):
      guard let locGuid = locator.guid else {
        throw FeedKitError.invalidEntryLocator(reason: "missing guid")
      }
      let guid = SQLString(from: locGuid)
      let url = SQLString(from: locator.url)
      let since = SQLString(from: locator.since)

      let ts = SQLString(from: queuedAt)

      let zoneName = SQLString(from: record.zoneName)
      let recordName = SQLString(from: record.recordName)
      let tag = SQLString(from: record.changeTag)

      return [
        "INSERT OR REPLACE INTO record(record_name, zone_name, change_tag) " +
        "VALUES(\(recordName), \(zoneName), \(tag));",

        "INSERT OR REPLACE INTO entry(entry_guid, feed_url, since) " +
        "VALUES(\(guid), \(url), \(since));",

        "INSERT OR REPLACE INTO queued_entry(entry_guid, ts, record_name) " +
        "VALUES(\(guid), \(ts), \(recordName));"
      ].joined(separator: "\n");
    }
  }

  static let SQLToSelectLocallyQueuedEntries =
    "SELECT * FROM locally_queued_entry_view;"

  static let SQLToSelectAbandonedRecords = "SELECT * FROM zombie_record_view;"

  static let SQLToSelectLocallySubscribedFeeds =
    "SELECT * FROM locally_subscribed_feed_view;"

}
