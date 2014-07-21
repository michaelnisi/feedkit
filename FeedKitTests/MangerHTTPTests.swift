//
//  MangerHTTPTests.swift
//  FeedKit
//
//  Created by Michael Nisi on 22.07.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import XCTest
import FeedKit

class MangerHTTPTests: XCTestCase {
  
  func testInit () {
    let svc = MangerHTTPService(host: "localhost", port:8080)
    XCTAssertEqual(svc.baseURL.absoluteString!, "http://localhost:8080")
  }
  
  func testQuery () {
    let queries = [
      Query("", date: NSDate(timeIntervalSince1970: 1))
      , Query("", date: NSDate(timeIntervalSince1970: 1.5))
    ]
    for (i, time) in enumerate([1000.0, 1500.0]) {
      XCTAssertEqual(queries[i].time, time)
    }
    XCTAssertEqual(
      String(Int(Query("", date: NSDate(timeIntervalSince1970: 1)).time))
      , "1000")
  }
  
  func testPayload () {
    let queries = [
      Query("a")
    ]
    let body = payload(queries)
    if let json: Array = parse(body) as? NSArray {
      XCTAssertEqual(json.count, 1)
      XCTAssertEqual(json[0]["url"] as NSString, "a")
    } else {
      XCTAssertTrue(false)
    }
  }
  
  func testReq () {
    var r = req(NSURL(string: "a"), [Query("b")])
    XCTAssertEqual(r.HTTPMethod as NSString, "POST")
  }
  
  func testFeeds () {
    let svc = MangerHTTPService(host: "localhost", port:8384)
    XCTAssertEqual(svc.baseURL.absoluteString!, "http://localhost:8384")
    let exp = self.expectationWithDescription("fetch feeds")
    let urls = [
      "http://feeds.muleradio.net/thetalkshow"
    , "http://www.friday.com/bbum/feed/"
    , "http://dtrace.org/blogs/feed/"
    , "http://5by5.tv/rss"
    , "http://feeds.feedburner.com/thesartorialist"
    , "http://hypercritical.co/feeds/main"
    ]
    svc.feeds(urls) { (er, feeds) in
      XCTAssertNil(er)
      if feeds != nil {
        XCTAssertEqual(feeds!.map {
          (feed) ->  NSDictionary in
          XCTAssertNotNil(feed["title"])
          return feed
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
}
