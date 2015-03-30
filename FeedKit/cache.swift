//
//  cache.swift
//  FeedKit
//
//  Created by Michael Nisi on 03.11.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import Foundation
import Skull

func urlInRow (row: SkullRow, forKey key: String) -> NSURL? {
  if let str = row[key] as? String {
    return NSURL(string: str)
  }
  return nil
}

func subcached (term: String, dict: [String:NSDate]) -> (String, NSDate)? {
  if let ts = dict[term] {
    return (term, ts)
  } else {
    if countElements(term) > 0 {
      let pre = term.endIndex.predecessor()
      return subcached(term.substringToIndex(pre), dict)
    }
    return nil
  }
}

func imagesInRow (row: SkullRow) -> ITunesImages? {
  if let img100 = urlInRow(row, forKey: "img100") {
    if let img30 = urlInRow(row, forKey: "img30") {
      if let img600 = urlInRow(row, forKey: "img600") {
        if let img60 = urlInRow(row, forKey: "img60") {
          return ITunesImages(
            img100: img100
          , img30: img30
          , img600: img600
          , img60: img60
          )
        }
      }
    }
  }
  return nil
}

func resultFromRow (row: SkullRow, df: SQLDates) -> SearchResult? {
  if let author = row["author"] as? String {
    if let feed = urlInRow(row, forKey: "feed") {
      if let guid = row["guid"] as? Int {
        if let title = row["title"] as? String {
          if let ts = row["ts"] as? String {
            return SearchResult(
              author: author
            , feed: feed
            , guid: guid
            , images: nil
            , title: title
            , ts: df.dateFromString(ts)
            )
          }
        }
      }
    }
  }
  return nil
}

func suggestionFromRow (row: SkullRow, df: SQLDates)
-> Suggestion? {
  if let term = row["term"] as? String {
    if let ts = row["ts"] as? String {
      return Suggestion(
        term: term
      , ts: df.dateFromString(ts)
      )
    }
  }
  return nil
}

func stale (ts: NSDate, ttl: NSTimeInterval) -> Bool {
  return ts.timeIntervalSinceNow + ttl < 0
}

class SQLDates {
  let ttl: NSTimeInterval
  init (ttl: NSTimeInterval) {
    self.ttl = ttl
  }

  lazy var df: NSDateFormatter = {
    let df = NSDateFormatter()
    df.timeZone = NSTimeZone(forSecondsFromGMT: 0)
    df.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return df
  }()

  func now () -> String {
    return df.stringFromDate(NSDate())
  }

  func then () -> String {
    return df.stringFromDate(NSDate(timeIntervalSinceNow: -ttl))
  }

  func dateFromString (str: String) -> NSDate? {
    return df.dateFromString(str)
  }
}

public class Cache {
  struct Constants {
    static let FILENAME = "feedkit.db"
  }
  let dates: SQLDates
  let db: Skull
  let queue: dispatch_queue_t
  let rm: Bool
  let schema: String
  public let ttl: NSTimeInterval
  public var url: NSURL?
  var noSuggestions = [String:NSDate]()
  var noResults = [String:NSDate]()

  public init? (
    db: Skull
  , queue: dispatch_queue_t
  , rm: Bool
  , schema: String
  , ttl: NSTimeInterval) {
    self.db = db
    self.queue = queue
    self.rm = rm
    self.schema = schema
    self.ttl = ttl
    self.dates = SQLDates(ttl: ttl)
    if let er = open(rm) {
      NSLog("\(__FUNCTION__): \(er)")
      return nil
    }
  }

  deinit {
    db.close()
  }

  func open (rm: Bool) -> NSError? {
    let db = self.db
    let schema = self.schema
    var error: NSError? = nil
    var url: NSURL!
    dispatch_sync(queue, {
      let fm = NSFileManager.defaultManager()
      let dir = fm.URLForDirectory(
        .CachesDirectory
      , inDomain: .UserDomainMask
      , appropriateForURL: nil
      , create: true
      , error: &error
      )
      if error != nil {
        return
      }
      url = NSURL(string: Constants.FILENAME, relativeToURL: dir)
      let exists = fm.fileExistsAtPath(url.path!)
      if exists && rm { // remove file
        var er: NSError? = nil
        fm.removeItemAtURL(url!, error: &er)
      }
      if let er = db.open(url: url) { // creates file and opens connection
        return error = er
      }
      if exists && !rm {
        return
      }
      var er: NSError?
      if let sql = String(
        contentsOfFile: schema
      , encoding: NSUTF8StringEncoding
      , error: &er) {
        if er != nil {
          return error = er
        }
        if let er = db.exec(sql) {
          return error = er
        }
      } else {
        return error = NSError(
          domain: domain
        , code: 1
        , userInfo: ["message": "couldn't create string from \(schema)"]
        )
      }
    })
    self.url = url
    return error
  }

  func close () -> NSError? {
    self.url = nil
    return db.close()
  }

  public func flush () -> NSError? {
    return db.flush()
  }
}

// MARK: SearchCache

private func time (date: NSDate?) -> NSTimeInterval {
  if let ts = date?.timeIntervalSince1970 {
    return ts
  }
  return NSDate().timeIntervalSince1970
}

private func text (str: String) -> String {
  return str.stringByReplacingOccurrencesOfString(
    "'", withString: "''", options: NSStringCompareOptions.LiteralSearch,
    range: nil)
}

extension Cache: SearchCache {
  public func setResults(
    results: [SearchResult]
  , forTerm term: String) -> NSError? {
    let db = self.db
    if results.count == 0 {
      noResults[term] = NSDate()
      var er: NSError?
       dispatch_sync(queue, {
        let sql = "".join([
          "DELETE FROM search_result "
        , "WHERE guid = ("
        , "SELECT * FROM search "
        , "WHERE term = \(term));"
        ])
        er = db.exec(sql)
      })
      return er
    }
    if let (cachedTerm, _) = subcached(term, noResults) {
      noResults[cachedTerm] = nil
    }
    var errors = [NSError]()
    dispatch_sync(queue, {
      db.exec("BEGIN IMMEDIATE;")
      for result in results {
        let author = result.author
        let feed = result.feed
        let guid = result.guid
        let title = text(result.title)
        let sql = "".join([
          "INSERT OR REPLACE INTO search(guid, term) "
        , "VALUES(\(guid), '\(term)');"
        , "INSERT OR REPLACE INTO search_result("
        , "author, feed, guid, title) VALUES("
        , "'\(author)', '\(feed)', \(guid), '\(title)'"
        , ");"
        ])
        if let er = db.exec(sql) {
          errors.append(er)
        }
      }
      db.exec("COMMIT;")
    })
    if errors.count > 0 {
      return NSError(
        domain: domain
      , code: 0
      , userInfo: ["message": messageFromErrors(errors)])
    }
    return nil
  }

  func resultsForSQL (sql: String) -> (NSError?, [SearchResult]?) {
    let db = self.db
    let df = self.dates
    var er: NSError?
    var results = [SearchResult]()
    dispatch_sync(queue, {
      er = db.query(sql) { er, row -> Int in
        if let r = row {
          if let result = resultFromRow(r, df) {
            results.append(result)
          }
        }
        return 0
      }
    })
    return (er, results.count > 0 ? results : nil)
  }

  public func resultsForTerm (
    term: String) -> (NSError?, [SearchResult]?) {
    let ttl = self.ttl
    if let (cachedTerm, ts) = subcached(term, noResults) {
      if stale(ts, ttl) {
        noResults[cachedTerm] = nil
        return (nil, nil)
      } else {
        return (nil, [])
      }
    }
    return resultsForSQL("".join([
      "SELECT * FROM search_result WHERE guid IN("
    , "SELECT guid FROM search_fts "
    , "WHERE term MATCH '\(term)') "
    , "ORDER BY ts DESC "
    , "LIMIT 50;"
    ]))
  }

  public func resultsMatchingTerm (
    term: String) -> (NSError?, [SearchResult]?) {
    return resultsForSQL("".join([
      "SELECT * FROM search_result WHERE guid IN ("
    , "SELECT guid FROM search_result_fts "
    , "WHERE search_result_fts MATCH '\(term)*') "
    , "ORDER BY ts DESC "
    , "LIMIT 3;"
    ]))
  }

  public func setSuggestions (
    suggestions: [Suggestion]
  , forTerm term: String) -> NSError? {
    let db = self.db
    if suggestions.count == 0 {
      noSuggestions[term] = NSDate()
      var er: NSError?
      dispatch_sync(queue, {
        let sql = "".join([
          "DELETE FROM sug "
        , "WHERE rowid = ("
        , "SELECT rowid FROM sug_fts WHERE term MATCH '\(term)*');"
        ])
        er = db.exec(sql)
      })
      return er
    }
    if let (cachedTerm, _) = subcached(term, noSuggestions) {
      noSuggestions[cachedTerm] = nil
    }
    var errors = [NSError]()
    dispatch_sync(queue, {
      db.exec("BEGIN IMMEDIATE;")
      for suggestion in suggestions {
        let term = suggestion.term
        let sql = "".join([
          "INSERT OR REPLACE INTO sug(rowid, term) "
        , "VALUES((SELECT rowid FROM sug "
        , "WHERE term = '\(term)'), '\(term)');"
        ])
        if let er = db.exec(sql) {
          errors.append(er)
        }
      }
      db.exec("COMMIT;")
    })
    if errors.count > 0 {
      return NSError(
        domain: domain
      , code: 0
      , userInfo: ["message": messageFromErrors(errors)]
      )
    }
    return nil
  }

  func suggestionsForSQL (sql: String) -> (NSError?, [Suggestion]?) {
    let db = self.db
    let df = self.dates
    var er: NSError?
    var sugs = [Suggestion]()
    dispatch_sync(queue, {
      er = db.query(sql) { er, row -> Int in
        if let r = row {
          if let sug = suggestionFromRow(r, df) {
            sugs.append(sug)
          }
        }
        return 0
      }
    })
    return (er, sugs.count > 0 ? sugs : nil)
  }

  public func suggestionsForTerm (
    term: String) -> (NSError?, [Suggestion]?) {
    let ttl = self.ttl
    if let (cachedTerm, ts) = subcached(term, noSuggestions) {
      if stale(ts, ttl) {
        noSuggestions[cachedTerm] = nil
        return (nil, nil)
      } else {
        return (nil, [])
      }
    }
    return suggestionsForSQL("".join([
      "SELECT * FROM sug_fts "
    , "WHERE term MATCH '\(term)*' "
    , "ORDER BY ts DESC "
    , "LIMIT 5;"
    ]))
  }
}
