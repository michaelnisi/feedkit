//
//  cache.swift
//  FeedKit
//
//  Created by Michael Nisi on 03.11.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import Foundation
import Skull

public class Cache {
  let queue: dispatch_queue_t
  let db: Skull

  public convenience init? () {
    let label = "\(domain).cache"
    let queue = dispatch_queue_create(label, DISPATCH_QUEUE_SERIAL)
    let db = Skull()
    self.init(queue: queue, db: db)
  }

  public init? (queue: dispatch_queue_t, db: Skull) {
    self.queue = queue
    self.db = db
    if let er = migrate() {
      return nil
    }
  }

  func migrate () -> NSError? {
    let db = self.db
    var error: NSError?
    dispatch_sync(queue, {
      let url = NSURL(fileURLWithPath: "feedkit.db")
      let fm = NSFileManager.defaultManager()
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
    return error
  }
}

extension Cache: SearchCache {
  public func addSuggestions(suggestions: [Suggestion]) -> NSError? {
    if suggestions.count < 1 {
      return NSError(
        domain: domain
      , code: 0
      , userInfo: ["message": "no suggestions"]
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

  public func suggestionsForTerm(term: String) -> (NSError?, [Suggestion]?) {
    let db = self.db
    var er: NSError?
    var sugs = [Suggestion]()
    dispatch_sync(queue, {
      let sql = "".join([
        "SELECT * FROM sug_fts "
      , "WHERE term MATCH '\(term)*' "
      , "ORDER BY ts DESC "
      , "LIMIT 5;"
      ])
      er = db.query(sql) { er, row -> Int in
        if let term = row?["term"] as? String {
          if let rawCat = row?["cat"] as? Int {
            if let cat = SearchCategory(rawValue: rawCat) {
              let sug = Suggestion(cat: cat, term: term)
              sugs.append(sug)
            }
          }
        }
        return 0
      }
    })
    return (er, sugs.count > 0 ? sugs : nil)
  }
}

