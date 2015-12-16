//
//  sql.swift
//  FeedKit
//
//  Created by Michael Nisi on 27/10/15.
//  Copyright © 2015 Michael Nisi. All rights reserved.
//

import Foundation
import Skull

func SQLToSelectFeedsByFeedIDs(feedIDs: [Int]) -> String? {
  guard !feedIDs.isEmpty else {
    return nil
  }
  let sql = "SELECT * FROM feed_view WHERE" + feedIDs.map {
    " uid = \($0)"
  }.joinWithSeparator(" OR") + ";"
  return sql
}

func SQLToRemoveFeedsWithFeedIDs(feedIDs: [Int]) -> String? {
  guard !feedIDs.isEmpty else {
    return nil
  }
  let sql = "DELETE FROM feed WHERE rowid IN(" + feedIDs.map {
    "\($0)"
    }.joinWithSeparator(", ") + ");"
  return sql
}

func SQLToSelectFeedIDFromURLView(url: String) -> String {
  return "SELECT feedid FROM url_view WHERE url = '\(url)';"
}

func SQLToInsertFeedID(feedID: Int, forTerm term: String) -> String {
  return "INSERT OR REPLACE INTO search(feedID, term) VALUES(\(feedID), '\(term)');"
}

func SQLToSelectFeedsByTerm(term: String, limit: Int) -> String {
  return [
    "SELECT * FROM search_view WHERE uid IN (",
    "SELECT feedid FROM search_fts ",
    "WHERE term MATCH '\(term)') ",
    "ORDER BY ts DESC ",
    "LIMIT \(limit);"
  ].joinWithSeparator("")
}

func SQLToSelectFeedsMatchingTerm(term: String, limit: Int) -> String {
  return [
    "SELECT * FROM feed_view WHERE uid IN (",
    "SELECT rowid FROM feed_fts ",
    "WHERE feed_fts MATCH '\(term)*') ",
    "ORDER BY ts DESC ",
    "LIMIT \(limit);"
  ].joinWithSeparator("")
}

func SQLToSelectEntriesMatchingTerm(term: String, limit: Int) -> String {
  return [
    "SELECT * FROM entry_view WHERE uid IN (",
    "SELECT rowid FROM entry_fts ",
    "WHERE entry_fts MATCH '\(term)*') ",
    "ORDER BY ts DESC ",
    "LIMIT \(limit);"
    ].joinWithSeparator("")
}

final class SQLFormatter {

  lazy var df: NSDateFormatter = {
    let df = NSDateFormatter()
    df.timeZone = NSTimeZone(forSecondsFromGMT: 0)
    df.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return df
  }()

  func now() -> String {
    return df.stringFromDate(NSDate())
  }

  func dateFromString(str: String?) -> NSDate? {
    guard str != nil else { return nil }
    return df.dateFromString(str!)
  }

  func SQLToInsertFeed(feed: Feed) -> String {
    let author = stringFromAnyObject(feed.author)
    let guid = stringFromAnyObject(feed.guid)
    let img = stringFromAnyObject(feed.images?.img)
    let img100 = stringFromAnyObject(feed.images?.img100)
    let img30 = stringFromAnyObject(feed.images?.img30)
    let img60 = stringFromAnyObject(feed.images?.img60)
    let img600 = stringFromAnyObject(feed.images?.img600)
    let link = stringFromAnyObject(feed.link)
    let summary = stringFromAnyObject(feed.summary)
    let title = stringFromAnyObject(feed.title)
    let updated = stringFromAnyObject(feed.updated)
    let url = stringFromAnyObject(feed.url)

    return [
      "INSERT INTO feed(",
      "author, guid, ",
      "img, img100, img30, img60, img600, ",
      "link, summary, title, updated, url) VALUES(",
      "\(author), \(guid), ",
      "\(img), \(img100), \(img30), \(img60), \(img600), ",
      "\(link), \(summary), \(title), \(updated), \(url)",
      ");"
    ].joinWithSeparator("")
  }
  
  func SQLToUpdateFeed(feed: Feed, withID rowid: Int) -> String {
    let author = stringFromAnyObject(feed.author)
    let guid = stringFromAnyObject(feed.guid)
    let img = stringFromAnyObject(feed.images?.img)
    let img100 = stringFromAnyObject(feed.images?.img100)
    let img30 = stringFromAnyObject(feed.images?.img30)
    let img60 = stringFromAnyObject(feed.images?.img60)
    let img600 = stringFromAnyObject(feed.images?.img600)
    let link = stringFromAnyObject(feed.link)
    let summary = stringFromAnyObject(feed.summary)
    let title = stringFromAnyObject(feed.title)
    let updated = stringFromAnyObject(feed.updated)
    let url = stringFromAnyObject(feed.url)
    
    return [
      "UPDATE feed ",
      "SET author = \(author), guid = \(guid), ",
      "img = \(img), img100 = \(img100), img30 = \(img30), ",
      "img60 = \(img60), img600 = \(img600), ", "link = \(link), ",
      "summary = \(summary), title = \(title), updated = \(updated), ",
      "url = \(url) ",
      "WHERE rowid = \(rowid);"
    ].joinWithSeparator("")
  }

  func SQLToInsertEntry(entry: Entry, forFeedID feedID: Int) -> String {
    let author = stringFromAnyObject(entry.author)
    let duration = stringFromAnyObject(entry.duration)
    let feedid = stringFromAnyObject(feedID)
    let id = stringFromAnyObject(entry.id)
    let img = stringFromAnyObject(entry.img)
    let length = stringFromAnyObject(entry.enclosure?.length)
    let link = stringFromAnyObject(entry.link)
    let subtitle = stringFromAnyObject(entry.subtitle)
    let summary = stringFromAnyObject(entry.summary)
    let title = stringFromAnyObject(entry.title)
    let type = stringFromAnyObject(entry.enclosure?.type.rawValue)
    let updated = stringFromAnyObject(entry.updated)
    let url = stringFromAnyObject(entry.enclosure?.url)

    return [
      "INSERT OR REPLACE INTO entry(",
      "author, duration, feedid, id, img, length, link, ",
      "subtitle, summary, title, type, updated, url) VALUES(",
      "\(author), \(duration), \(feedid), \(id), \(img), \(length), \(link), ",
      "\(subtitle), \(summary), \(title), \(type), \(updated), \(url)",
      ");"
    ].joinWithSeparator("")
  }

  func stringFromAnyObject(obj: AnyObject?) -> String {
    switch obj {
    case nil:
      return "NULL"
    case is Int, is Double:
      return "\(obj!)"
    case let value as String:
      let s = value.stringByReplacingOccurrencesOfString(
        "'",
        withString: "''",
        options: NSStringCompareOptions.LiteralSearch,
        range: nil
      )
      return "'\(s)'"
    case let value as NSDate:
      return "'\(df.stringFromDate(value))'"
    case let value as NSURL:
      return value.absoluteString
    default:
      return "NULL"
    }
  }
  
  func SQLToSelectEntriesByIntervals(intervals: [(Int, NSDate)]) -> String? {
    guard !intervals.isEmpty else {
      return nil
    }
    return "SELECT * FROM entry_view WHERE" + intervals.map {
      let feedID = $0.0
      let ts = df.stringFromDate($0.1)
      return " feedid = \(feedID) AND ts > '\(ts)'"
    }.joinWithSeparator(" OR") + " ORDER BY feedid, ts;"
  }

  func feedImagesFromRow(row: SkullRow) -> FeedImages {
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

  func feedFromRow(row: SkullRow) throws -> Feed {
    let author = row["author"] as? String
    let guid = row["guid"] as? Int
    let link = row["link"] as? String
    let img = feedImagesFromRow(row)
    let summary = row["summary"] as? String
    guard let title = row["title"] as? String else {
      throw FeedKitError.Missing(name: "title")
    }
    let ts = dateFromString(row["ts"] as? String)
    let uid = row["uid"] as? Int
    let updated = dateFromString(row["updated"] as? String)
    guard let url = row["url"] as? String else {
      throw FeedKitError.Missing(name: "url")
    }

    return Feed(
      author: author,
      guid: guid,
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

  func enclosureFromRow(row: SkullRow) throws -> Enclosure {
    guard let url = row["url"] as? String else {
      throw FeedKitError.Missing(name: "url")
    }
    let length = row["length"] as? Int
    guard let rawType = row["type"] as? Int else {
      throw FeedKitError.Missing(name: "type")
    }
    guard let type = EnclosureType(rawValue: rawType) else {
      throw FeedKitError.UnknownEnclosureType(type: "raw value: \(rawType)")
    }
    return Enclosure(url: url, length: length, type: type)
  }

  func entryFromRow(row: SkullRow) throws -> Entry {
    let author = row["author"] as? String
    
    var enclosure: Enclosure?
    do {
      enclosure = try enclosureFromRow(row)
    } catch {
      // TODO: Handle entries without enclosure
    }
    
    let duration = row["duration"] as? String
    guard let feed = row["feed"] as? String else {
      throw FeedKitError.Missing(name: "feed")
    }
    guard let id = row["id"] as? String else {
      throw FeedKitError.Missing(name: "id")
    }
    let img = row["img"] as? String
    let link = row["link"] as? String
    let subtitle = row["subtitle"] as? String
    let summary = row["summary"] as? String
    guard let title = row["title"] as? String else {
      throw FeedKitError.Missing(name: "title")
    }
    let ts = dateFromString(row["ts"] as? String)
    let updated = dateFromString(row["updated"] as? String)

    return Entry(
      author: author,
      enclosure: enclosure,
      duration: duration,
      feed: feed,
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

  func suggestionFromRow(row: SkullRow) throws -> Suggestion {
    guard let term = row["term"] as? String else {
      throw FeedKitError.Missing(name: "term")
    }
    guard let ts = row["ts"] as? String else {
      throw FeedKitError.Missing(name: "ts")
    }
    return Suggestion(term: term, ts: dateFromString(ts))
  }
}
