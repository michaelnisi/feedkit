//
//  CacheTests.swift
//  FeedKit
//
//  Created by Michael Nisi on 02.11.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import FeedKit
import Skull
import XCTest

class CacheTests: XCTestCase {
  var cache: Cache?

  func dbURL () -> NSURL? {
    var er: NSError?
    let fm = NSFileManager.defaultManager()
    let dir = fm.URLForDirectory(
      .CachesDirectory
    , inDomain: .UserDomainMask
    , appropriateForURL: nil
    , create: true
    , error: &er
    )
    if er == nil {
      return NSURL(string: "feedkit.db", relativeToURL: dir)
    }
    return nil
  }

  func rm (url: NSURL) -> NSError? {
    let fm = NSFileManager.defaultManager()
    var er: NSError?
    fm.removeItemAtURL(url, error: &er)
    return er
  }

  override func setUp() {
    super.setUp()
    if let url = dbURL() {
      let fm = NSFileManager.defaultManager()
      if fm.fileExistsAtPath(url.path!) {
        if let er = rm(url) {
          XCTFail("could not remove file")
        }
      }
      let label = "\(domain).cache"
      let cacheQueue = dispatch_queue_create(label, DISPATCH_QUEUE_SERIAL)
      let db = Skull()
      let ttl: NSTimeInterval = 3600
      cache = Cache(db: db, queue: cacheQueue, rm: true, ttl: ttl)
      XCTAssert(fm.fileExistsAtPath(url.path!))
    } else {
      XCTFail("directory not found")
    }
  }

  override func tearDown() {
    if let url = dbURL() {
      if let er = rm(url) {
        XCTFail("could not remove file")
      }
      let fm = NSFileManager.defaultManager()
      XCTAssertFalse(fm.fileExistsAtPath(url.path!))
    } else {
      XCTFail("directory not found")
    }

    cache = nil
    super.tearDown()
  }

  func testSuggestions () {
    let terms = ["apple", "apple watch", "apple pie"]
    let input = terms.map({ term in
      Suggestion(term: term, ts: nil)
    })
    XCTAssertNil(cache?.setSuggestions(input, forTerm:"apple"))
    let (error, suggestions) = cache!.suggestionsForTerm("apple pie")
    if let output = suggestions {
      XCTAssertEqual(output.count, 1)
      let found: Suggestion = output.last!
      XCTAssertNotNil(found.ts!)
      let wanted: Suggestion = input.last!
      XCTAssertEqual(found, wanted)
    } else {
      XCTFail("should find suggestions")
    }
  }

  func testRemoveSuggestions () {
    let terms = ["apple", "apple watch", "apple pie"]
    let input = terms.map({ term in
      Suggestion(term: term, ts: nil)
    })
    XCTAssertNil(cache?.setSuggestions(input, forTerm:"apple"))
    XCTAssertNil(cache?.setSuggestions([], forTerm:"pie"))
    let (error, suggestions) = cache!.suggestionsForTerm("apple")
    XCTAssertNil(error)
    if let found = suggestions {
      XCTAssertEqual(found.count, 2)
      for (i, sug) in enumerate(found) {
        XCTAssertEqual(sug, input[i])
      }
    } else {
      XCTFail("should find suggestions")
    }
  }

  func hit (term: String, _ wanted: String, _ cache: [String:NSDate]) {
    if let (found, ts) = subcached(term, cache) {
      XCTAssertEqual(found, wanted)
      if countElements(term) > 1 {
        let pre = term.endIndex.predecessor()
        hit(term.substringToIndex(pre), wanted, cache)
      }
    } else {
      XCTFail("\(term) should be cached")
    }
  }

  func testSubcached () {
    var cache = [String:NSDate]()
    cache["a"] = NSDate()
    hit("abc", "a", cache)
    cache["a"] = nil

    cache["abc"] = NSDate()
    XCTAssertNotNil(subcached("abcd", cache)!.0)
    XCTAssertNil(subcached("ab", cache)?.0)
  }
}
