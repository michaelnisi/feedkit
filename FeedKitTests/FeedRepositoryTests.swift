//
//  FeedRepositoryTests.swift
//  FeedKit
//
//  Created by Michael Nisi on 24.09.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import XCTest
import FeedKit

class FeedRepositoryTests: XCTestCase {
  var queue :dispatch_queue_t?
  
  override func setUp() {
    super.setUp()
    queue = dispatch_queue_create("FeedKit.feeds", DISPATCH_QUEUE_SERIAL)
  }
  
  override func tearDown() {
    dispatch_release(self.queue)
    super.tearDown()
  }
  
  func testFeeds () {
    let svc = MangerHTTPService(host: "localhost", port:8384)
    let repo = FeedRepository(queue: self.queue!, svc: svc)
    let exp = self.expectationWithDescription("get feeds")
    let urls = [
        "http://feeds.muleradio.net/thetalkshow"
      , "http://www.friday.com/bbum/feed/"
      , "http://dtrace.org/blogs/feed/"
      , "http://5by5.tv/rss"
      , "http://feeds.feedburner.com/thesartorialist"
      , "http://hypercritical.co/feeds/main"
    ]
    repo.feeds(urls) { (er, feeds) in
      XCTAssertNil(er)
      if feeds != nil {
        XCTAssertEqual(feeds!.map { (feed) -> Feed in
          XCTAssertNotNil(feed.title)
          XCTAssertNotNil(feed.url)
          return feed
          }.count, 6)
      } else {
        XCTAssertTrue(false, "no feeds")
      }
      exp.fulfill()
    }
    self.waitForExpectationsWithTimeout(10, handler: { (er) in
      XCTAssertNil(er)
    })
  }
}