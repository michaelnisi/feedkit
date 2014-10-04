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

  func testUpdated () {
    XCTAssertTrue(updated(NSDictionary()) == 0.00)
    XCTAssertTrue(updated(["updated":1000]) == 1.00)
  }

  func testQuery () {
    let queries = [
      FeedQuery(string: "")
    , FeedQuery(url: NSURL(string: ""), date: NSDate(timeIntervalSince1970: 1))
    , FeedQuery(url: NSURL(string: ""), date: NSDate(timeIntervalSince1970: 1.5))
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
      FeedQuery(string: "a")
    ]
    let (payloadError, data) = payload(queries)
    XCTAssertNil(payloadError)
    let (parseError, dicts: AnyObject?) = parseJSON(data!)
    XCTAssertNil(parseError)
    XCTAssertEqual(dicts!.count, 1)
    XCTAssertEqual(dicts![0]["url"] as NSString, "a")
  }

  func testReq () {
    var r = req(NSURL(string: "a"), [FeedQuery(string: "b")])
    XCTAssertEqual(r.HTTPMethod as NSString, "POST")
  }

  func testFeeds () {
    let exp = self.expectationWithDescription("fetch feeds")
    let urls = [
      "http://feeds.muleradio.net/thetalkshow"
    , "http://www.friday.com/bbum/feed/"
    , "http://dtrace.org/blogs/feed/"
    , "http://5by5.tv/rss"
    , "http://feeds.feedburner.com/thesartorialist"
    , "http://hypercritical.co/feeds/main"
    ]
    let queries = urls.map { url -> FeedQuery in FeedQuery(string: url) }
    svc!.feeds(queries) { (er, res) in
      XCTAssertNil(er)
      if let dicts = res!.items as? [NSDictionary]{
        XCTAssertEqual(dicts.map {
          (dict) ->  NSDictionary in
          XCTAssertNotNil(dict["title"])
          return dict
          }.count, 6)
      } else {
        XCTAssertTrue(false, "no feeds")
      }
      exp.fulfill()
    }
    self.waitForExpectationsWithTimeout(10, handler: {
      (er) in
      XCTAssertNil(er)
    })
  }
  
  func testWithoutQueries () {
    for f in [svc!.feeds, svc!.entries] {
      let exp = self.expectationWithDescription("\(f)")
      f([]) { (er, res) in
        XCTAssertNotNil(er)
        XCTAssertNil(res)
        exp.fulfill()
      }
      self.waitForExpectationsWithTimeout(10, handler: {
        (er) in
        XCTAssertNil(er)
      })
    }
  }
}
