//
//  MangerTests.swift
//  FeedKit
//
//  Created by Michael Nisi on 22.07.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import XCTest
import FeedKit

class MangerHTTPTests: XCTestCase {
  var svc: MangerHTTPService?

  override func setUp () {
    super.setUp()
    svc = MangerHTTPService(host: "localhost", port:8384)
    XCTAssertEqual(svc!.baseURL.absoluteString!, "http://localhost:8384")
  }

  override func tearDown() {
    svc = nil
    super.tearDown()
  }

  func testFeedFromValid () {
    let dict = ["title":"a", "feed":"b"]
    let (er, feed) = feedFrom(dict)
    XCTAssertNil(er)
    if let found = feed {
      let wanted = Feed(
        author: nil
      , image: nil
      , language: nil
      , link: nil
      , summary: nil
      , title: "a"
      , updated: 0.0
      , url: NSURL(string:"http://some.io/rss")!
      )
      XCTAssertEqual(found, wanted)
    } else {
      XCTAssert(false, "should have feed")
    }
  }

  func testFeedFromInvalid () {
    let dict = ["title":"invalid"]
    let wanted = NSError(
      domain: domain
    , code: 1
    , userInfo: ["message":"missing fields (title or feed) in {\n    title = invalid;\n}"]
    )
    shouldError(feedFrom, dict, wanted)
  }

  func testEnclosureFromInvalid () {
    let dict = ["href":"href"]
    let wanted = NSError(
      domain: domain
    , code: 1
    , userInfo: ["message":"missing fields (url, length, or type) in {\n    href = href;\n}"]
    )
    shouldError(enclosureFrom, dict, wanted)
  }

  func testEnclosureFromValid () {
    let dict = [
      "url":"http://cdn.io/some.mp3"
      , "length":"100"
      , "type":"audio/mpeg"
    ]
    let (er, enclosure) = enclosureFrom(dict)
    XCTAssertNil(er)
    if let found = enclosure {
      let wanted = Enclosure(
        href: NSURL(string:"http://cdn.io/some.mp3")!
        , length: 100
        , type: "audio/mpeg"
      )
      XCTAssertEqual(found, wanted)
    } else {
      XCTAssert(false, "should have enclosure")
    }
  }

  func testEntryFromInvalid () {
    let dict = ["title":"a"]
    let wanted = NSError(
      domain: domain
    , code: 1
    , userInfo: ["message":"missing fields (title or enclosure) in {\n    title = a;\n}"]
    )
    shouldError(entryFrom, dict, wanted)
  }

  func testUpdated () {
    XCTAssertTrue(updated(NSDictionary()) == 0.00)
    XCTAssertTrue(updated(["updated":1000]) == 1.00)
  }

  func testQuery () {
    let queries = [
      FeedQuery(string: "")
    , FeedQuery(url: NSURL(string: "")!, date: NSDate(timeIntervalSince1970: 1))
    , FeedQuery(url: NSURL(string: "")!, date: NSDate(timeIntervalSince1970: 1.5))
    ]
    for (i, time) in enumerate([
      -1 // no feeds before 00:00:00, 1 January 1970
    , 1000
    , 1500]) {
      XCTAssertEqual(queries[i].time, time)
    }
  }

  func testPayload () {
    let queries = [
      FeedQuery(string: "abc")
    , FeedQuery(
        url: NSURL(string: "def")!
      , date: NSDate(timeIntervalSince1970: 1) // seconds in Cocoa
      )
    ]
    let (payloadError, data) = payload(queries)
    XCTAssertNil(payloadError)
    let (parseError, items: AnyObject?) = parseJSON(data!)
    XCTAssertNil(parseError)
    let found = items as [NSDictionary]
    let wanted = [
      ["url": "abc"]
    , ["url": "def", "since": 1000] // milliseconds in JavaScript
    ]
    XCTAssertEqual(found, wanted)
  }

  func testReq () {
    var r = req(NSURL(string: "a")!, [FeedQuery(string: "b")])
  }

  func testFeedsWithoutQueries () {
    let exp = self.expectationWithDescription("no queries")
    svc!.feeds([]) { (er, feeds) in
      XCTAssertNotNil(er)
      exp.fulfill()
    }
    self.waitForExpectationsWithTimeout(10, handler: {
      (er) in
      XCTAssertNil(er)
    })
  }

  func testEntriesWithoutQueries () {
    let exp = self.expectationWithDescription("no queries")
    svc!.feeds([]) { (er, entries) in
      XCTAssertNotNil(er)
      exp.fulfill()
    }
    self.waitForExpectationsWithTimeout(10, handler: {
      (er) in
      XCTAssertNil(er)
    })
  }
}
