//
//  sql.swift - translate to and from SQLite
//  FeedKit
//
//  Created by Michael Nisi on 27/10/15.
//  Copyright © 2015 Michael Nisi. All rights reserved.
//

import Foundation
import Skull

// TODO: Complete last eight percent of test coverage

// TODO: Review map functions regarding limits
//
// Maximum Depth Of An Expression Tree https://www.sqlite.org/limits.html
// Here's the deal, basically every time an array of identifiers is longer than
// 1000, these will break.

// MARK: Browsing

private func selectRowsByUIDs(_ table: String, ids: [Int]) -> String? {
  guard !ids.isEmpty else { return nil }
  let sql = "SELECT * FROM \(table) WHERE" + ids.map {
    " uid = \($0)"
  }.joined(separator: " OR") + ";"
  return sql
}

func SQLToSelectEntriesByEntryIDs(_ entryIDs: [Int]) -> String? {
  return selectRowsByUIDs("entry_view", ids: entryIDs)
}

func SQLToSelectFeedsByFeedIDs(_ feedIDs: [Int]) -> String? {
  return selectRowsByUIDs("feed_view", ids: feedIDs)
}

func SQLToSelectEntryByGUID(_ guid: String) -> String {
  return "SELECT * FROM entry_view WHERE guid = '\(guid)';"
}

// TODO: Test if entries are removed when their feeds are removed

func SQLToRemoveFeedsWithFeedIDs(_ feedIDs: [Int]) -> String? {
  guard !feedIDs.isEmpty else { return nil }
  let sql = "DELETE FROM feed WHERE rowid IN(" + feedIDs.map {
    "\($0)"
  }.joined(separator: ", ") + ");"
  return sql
}

func SQLStringFromString(_ string: String) -> String {
  let s = string.replacingOccurrences(
    of: "'",
    with: "''",
    options: NSString.CompareOptions.literal,
    range: nil
  )
  return "'\(s)'"
}

func SQLToSelectFeedIDFromURLView(_ url: String) -> String {
  let s = SQLStringFromString(url)
  return "SELECT feedid FROM url_view WHERE url = \(s);"
}

func SQLToInsertFeedID(_ feedID: Int, forTerm term: String) -> String {
  return "INSERT OR REPLACE INTO search(feedID, term) VALUES(\(feedID), '\(term)');"
}

// MARK: Searching

func SQLToSelectFeedsByTerm(_ term: String, limit: Int) -> String {
  let sql =
  "SELECT * FROM search_view WHERE uid IN (" +
  "SELECT feedid FROM search_fts " +
  "WHERE term MATCH '\(term)*') " +
  "ORDER BY ts DESC " +
  "LIMIT \(limit);"
  return sql
}

func SQLToSelectFeedsMatchingTerm(_ term: String, limit: Int) -> String {
  let sql =
  "SELECT * FROM feed_view WHERE uid IN (" +
  "SELECT rowid FROM feed_fts " +
  "WHERE feed_fts MATCH '\(term)*') " +
  "ORDER BY ts DESC " +
  "LIMIT \(limit);"
  return sql
}

func SQLToSelectEntriesMatchingTerm(_ term: String, limit: Int) -> String {
  let sql =
  "SELECT * FROM entry_view WHERE uid IN (" +
  "SELECT rowid FROM entry_fts " +
  "WHERE entry_fts MATCH '\(term)*') " +
  "ORDER BY updated DESC " +
  "LIMIT \(limit);"
  return sql
}

func SQLToDeleteSearchForTerm(_ term: String) -> String {
  return "DELETE FROM search WHERE term='\(term)';"
}

// MARK: Suggestions

func SQLToInsertSuggestionForTerm(_ term: String) -> String {
  return "INSERT OR REPLACE INTO sug(term) VALUES('\(term)');"
}

func SQLToSelectSuggestionsForTerm(_ term: String, limit: Int) -> String {
  let sql =
  "SELECT * FROM sug WHERE rowid IN (" +
  "SELECT rowid FROM sug_fts " +
  "WHERE term MATCH '\(term)*') " +
  "ORDER BY ts DESC " +
  "LIMIT \(limit);"
  return sql
}

func SQLToDeleteSuggestionsMatchingTerm(_ term: String) -> String {
  let sql =
  "DELETE FROM sug " +
  "WHERE rowid IN (" +
  "SELECT rowid FROM sug_fts WHERE term MATCH '\(term)*');"
  return sql
}

// MARK: SQLFormatter

final class SQLFormatter {

  lazy var df: DateFormatter = {
    let df = DateFormatter()
    df.timeZone = TimeZone(secondsFromGMT: 0)
    df.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return df
  }()

  func now() -> String {
    return df.string(from: Date())
  }

  func dateFromString(_ str: String?) -> Date? {
    guard str != nil else { return nil }
    return df.date(from: str!)
  }

  func SQLToInsertFeed(_ feed: Feed) -> String {
    let author = stringFromAny(feed.author as AnyObject?)
    let guid = stringFromAny(feed.iTunesGuid as AnyObject?)
    let img = stringFromAny(feed.images?.img as AnyObject?)
    let img100 = stringFromAny(feed.images?.img100 as AnyObject?)
    let img30 = stringFromAny(feed.images?.img30 as AnyObject?)
    let img60 = stringFromAny(feed.images?.img60 as AnyObject?)
    let img600 = stringFromAny(feed.images?.img600 as AnyObject?)
    let link = stringFromAny(feed.link as AnyObject?)
    let summary = stringFromAny(feed.summary as AnyObject?)
    let title = stringFromAny(feed.title as AnyObject?)
    let updated = stringFromAny(feed.updated as AnyObject?)
    let url = stringFromAny(feed.url as AnyObject?)

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

  func SQLToUpdateFeed(_ feed: Feed, withID rowid: Int) -> String {
    let author = stringFromAny(feed.author as AnyObject?)
    let guid = stringFromAny(feed.iTunesGuid as AnyObject?)
    let img = stringFromAny(feed.images?.img as AnyObject?)
    let img100 = stringFromAny(feed.images?.img100 as AnyObject?)
    let img30 = stringFromAny(feed.images?.img30 as AnyObject?)
    let img60 = stringFromAny(feed.images?.img60 as AnyObject?)
    let img600 = stringFromAny(feed.images?.img600 as AnyObject?)
    let link = stringFromAny(feed.link as AnyObject?)
    let summary = stringFromAny(feed.summary as AnyObject?)
    let title = stringFromAny(feed.title as AnyObject?)
    let updated = stringFromAny(feed.updated as AnyObject?)
    let url = stringFromAny(feed.url as AnyObject?)

    let sql =
    "UPDATE feed " +
    "SET author = \(author), guid = \(guid), " +
    "img = \(img), img100 = \(img100), img30 = \(img30), " +
    "img60 = \(img60), img600 = \(img600), link = \(link), " +
    "summary = \(summary), title = \(title), updated = \(updated), " +
    "url = \(url) " +
    "WHERE rowid = \(rowid);"
    return sql
  }

  func SQLToInsertEntry(_ entry: Entry, forFeedID feedID: Int) -> String {
    let author = stringFromAny(entry.author as AnyObject?)
    let duration = stringFromAny(entry.duration as AnyObject?)
    let feedid = stringFromAny(feedID as AnyObject?)
    let guid = SQLStringFromString(entry.guid)
    let id = stringFromAny(entry.id as AnyObject?)
    let img = stringFromAny(entry.img as AnyObject?)
    let length = stringFromAny(entry.enclosure?.length as AnyObject?)
    let link = stringFromAny(entry.link as AnyObject?)
    let subtitle = stringFromAny(entry.subtitle as AnyObject?)
    let summary = stringFromAny(entry.summary as AnyObject?)
    let title = stringFromAny(entry.title as AnyObject?)

    let type = stringFromAny(entry.enclosure?.type.rawValue as AnyObject?)
    let updated = stringFromAny(entry.updated as AnyObject?)
    let url = stringFromAny(entry.enclosure?.url as AnyObject?)

    let sql =
    "INSERT OR REPLACE INTO entry(" +
    "author, duration, feedid, guid, id, img, length, " +
    "link, subtitle, summary, title, type, updated, url) VALUES(" +
    "\(author), \(duration), \(feedid), \(guid), \(id), \(img), \(length), " +
    "\(link), \(subtitle), \(summary), \(title), \(type), \(updated), \(url)" +
    ");"
    return sql
  }

  // TODO: Rename to stringFrom(Any:)
  
  func stringFromAny(_ obj: Any?) -> String {
    switch obj {
    case nil:
      return "NULL"
    case is Int, is Double:
      return "\(obj!)"
    case let value as String:
      return SQLStringFromString(value)
    case let value as Date:
      return "'\(df.string(from: value))'"
    case let value as URL:
      return SQLStringFromString(value.absoluteString)
    default:
      return "NULL"
    }
  }

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

  func feedImagesFromRow(_ row: SkullRow) -> FeedImages {
    let img = row["img"] as? String
    let img30 = row["img30"] as? String
    let img60 = row["img60"] as? String
    let img100 = row["img100"] as? String
    let img600 = row["img600"] as? String

    return FeedImages(
      img: img,
      img100: img100,
      img30: img30,
      img60: img60,
      img600: img600
    )
  }

  func feedFromRow(_ row: SkullRow) throws -> Feed {
    let author = row["author"] as? String
    let iTunesGuid = row["guid"] as? Int
    let link = row["link"] as? String
    let img = feedImagesFromRow(row)
    let summary = row["summary"] as? String
    guard let title = row["title"] as? String else {
      throw FeedKitError.invalidFeed(reason: "missing title")
    }
    let ts = dateFromString(row["ts"] as? String)
    let uid = row["uid"] as? Int
    let updated = dateFromString(row["updated"] as? String)
    guard let url = row["url"] as? String else {
      throw FeedKitError.invalidFeed(reason: "missing url")
    }

    return Feed(
      author: author,
      iTunesGuid: iTunesGuid,
      images: img,
      link: link,
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
  /// - Parameter row: The database row to use.
  /// - Returns: The resulting entry.
  /// - Throws: If this throws our database got corrupted, thus, int that case,
  /// users of this function are well advised to crash. The only reason for not
  /// crashing directly from here is debugging during development.
  func entryFromRow(_ row: SkullRow) throws -> Entry {
    let author = row["author"] as? String
    let enclosure = try enclosureFromRow(row)
    let duration = row["duration"] as? Int
    let feed = row["feed"] as! String
    let feedTitle = row["feed_title"] as! String
    let guid = row["guid"] as! String
    let id = row["id"] as! String
    let img = row["img"] as? String
    let link = row["link"] as? String
    let subtitle = row["subtitle"] as? String
    let summary = row["summary"] as? String
    let title = row["title"] as! String
    let ts = dateFromString(row["ts"] as? String)

    guard let updated = dateFromString(row["updated"] as? String) else {
      throw FeedKitError.invalidEntry(reason: "missing updated")
    }

    return Entry(
      author: author,
      enclosure: enclosure,
      duration: duration,
      feed: feed,
      feedTitle: feedTitle,
      guid: guid,
      id: id,
      img: img,
      link: link,
      subtitle: subtitle,
      summary: summary,
      title: title,
      ts: ts,
      updated: updated
    )
  }

  func suggestionFromRow(_ row: SkullRow) throws -> Suggestion {
    guard let term = row["term"] as? String else {
      throw FeedKitError.invalidSuggestion(reason: "missing term")
    }
    guard let ts = row["ts"] as? String else {
      throw FeedKitError.invalidSuggestion(reason: "missing ts")
    }
    return Suggestion(term: term, ts: dateFromString(ts))
  }
}
