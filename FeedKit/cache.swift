//
//  cache.swift
//  FeedKit
//
//  Created by Michael Nisi on 03.11.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import Foundation
import Skull

private func suggestionFromRow (
  row: SkullRow
, dateFormatter df: NSDateFormatter)
  -> Suggestion? {
  if let term = row["term"] as? String {
    if let rawCat = row["cat"] as? Int {
      if let cat = SearchCategory(rawValue: rawCat) {
        if let ts = row["ts"] as? String {
          return Suggestion(
            cat: cat
          , term: term
          , ts: df.dateFromString(ts)
          )
        }
      }
    }
  }
  return nil
}

public class Cache {
  let db: Skull
  let queue: dispatch_queue_t
  public var url: NSURL?

  lazy var dateFormatter: NSDateFormatter = {
    let df = NSDateFormatter()
    df.timeZone = NSTimeZone(forSecondsFromGMT: 0)
    df.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return df
  }()

  public init? (db: Skull, queue: dispatch_queue_t) {
    self.db = db
    self.queue = queue
    if let er = open() {
      println(er)
      return nil
    }
  }

  deinit {
    db.close()
  }

  func open () -> NSError? {
    let db = self.db
    var error: NSError? = nil
    var url: NSURL?
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
      url = NSURL(string: "feedkit.db", relativeToURL: dir)
      let exists = fm.fileExistsAtPath(url!.path!)
      if let er = db.open(url: url) { // Open in all cases.
        return error = er
      }
      if exists {
        return
      }
      let bundle = NSBundle(forClass: self.dynamicType)
      if let path = bundle.pathForResource("schema", ofType: "sql") {
        var er: NSError?
        if let sql = String(
          contentsOfFile: path
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
          , userInfo: ["message": "couldn't create string from \(path)"]
          )
        }
      } else {
        return error = NSError(
          domain: domain
        , code: 1
        , userInfo: ["message": "couldn't locate schema.sql"]
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

extension Cache: SearchCache {
  public func addSuggestions (suggestions: [Suggestion]) -> NSError? {
    if suggestions.count < 1 {
      return NSError(
        domain: domain
      , code: 0
      , userInfo:["message": "no suggestions"]
      )
    }
    let db = self.db
    var errors = [NSError]()
    dispatch_sync(queue, {
      db.exec("BEGIN IMMEDIATE;")
      for suggestion: Suggestion in suggestions {
        let term = suggestion.term
        let cat = suggestion.cat.rawValue
        let sql = "".join([
          "INSERT OR REPLACE INTO sug(rowid, term, cat) "
        , "VALUES((SELECT rowid FROM sug WHERE term = '\(term)'), "
        , "'\(term)', \(cat));"
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
      , userInfo: ["message": stringFrom(errors)]
      )
    }
    return nil
  }

  public func suggestionsForTerm (term: String) -> (NSError?, [Suggestion]?) {
    let db = self.db
    var er: NSError?
    var sugs = [Suggestion]()
    let df = self.dateFormatter
    dispatch_sync(queue, {
      let sql = "".join([
        "SELECT * FROM sug_fts "
      , "WHERE term MATCH '\(term)*' "
      , "ORDER BY ts DESC "
      , "LIMIT 5;"
      ])
      er = db.query(sql) { er, row -> Int in
        if let r = row {
          if let sug = suggestionFromRow(r, dateFormatter: df) {
            sugs.append(sug)
          }
        }
        return 0
      }
    })
    return (er, sugs.count > 0 ? sugs : nil)
  }
}

