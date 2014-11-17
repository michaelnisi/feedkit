//
//  CacheTests.swift
//  FeedKit
//
//  Created by Michael Nisi on 02.11.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import UIKit
import XCTest
import FeedKit
import Skull

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
      cache = Cache(db: db, queue: cacheQueue)
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
    XCTAssertNotNil(cache?.addSuggestions([]), "should error if empty")
    let terms = ["apple", "google", "samsung"]
    let input = terms.map({ term in
      Suggestion(cat: .Store, term: term, ts: nil)
    })
    let er = cache?.addSuggestions(input)
    XCTAssertNil(er)
    XCTAssertNil(cache?.addSuggestions(input), "should replace")
    let (error, suggestions) = cache!.suggestionsForTerm("a")
    if let output = suggestions {
      XCTAssertEqual(output.count, 1)
      let found: Suggestion = output.first!
      let wanted: Suggestion = input.first!
      println(found)
      XCTAssertEqual(found, wanted)
    } else {
      XCTFail("should find suggestions")
    }
  }
}
