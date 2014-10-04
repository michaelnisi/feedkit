//
//  EntryRepositoryTests.swift
//  FeedKit
//
//  Created by Michael Nisi on 29.09.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import UIKit
import XCTest

class EntryRepositoryTests: XCTestCase {
  var queue: dispatch_queue_t?
  var svc: MangerHTTPService?
  var repo: EntryRepository?

  override func setUp() {
    super.setUp()
    queue = dispatch_queue_create("FeedKit.feeds", DISPATCH_QUEUE_SERIAL)
    svc = MangerHTTPService(host: "localhost", port:8384)
    repo = EntryRepository(queue: queue!, svc: svc!)
  }

  override func tearDown() {
    svc = nil
    repo = nil
    dispatch_release(self.queue)
    super.tearDown()
  }

  func testEntries () {
    let exp = self.expectationWithDescription("get entries")
    let urls = [
        "http://feeds.muleradio.net/thetalkshow"
      , "http://5by5.tv/rss"
    ]
    let queries = urls.map { url -> FeedQuery in FeedQuery(string: url) }
    repo!.entries(queries) { (er, result) in
      XCTAssertNil(er)
      if let entries = result {
        XCTAssertTrue(entries.count > 0)
      } else {
        XCTAssertTrue(false, "should have received entries")
      }
      exp.fulfill()
    }
    self.waitForExpectationsWithTimeout(10, handler: { (er) in
      XCTAssertNil(er)
    })
  }
}
