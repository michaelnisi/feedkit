//
//  SearchRepositoryTests.swift
//  FeedKit
//
//  Created by Michael Nisi on 03.11.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import UIKit
import XCTest
import FeedKit
import Skull

class SearchRepositoryTests: XCTestCase {
  var repo: SearchRepository?

  func svc () -> FanboyService {
    let baseURL = NSURL(string: "http://localhost:8383")!
    let conf = NSURLSessionConfiguration.defaultSessionConfiguration()
    return FanboyService(baseURL: baseURL, conf: conf)
  }

  override func setUp () {
    super.setUp()
    let queue = NSOperationQueue()
    queue.name = "\(domain).search"

    let label = "\(domain).cache"
    let cacheQueue = dispatch_queue_create(label, DISPATCH_QUEUE_SERIAL)
    let db = Skull()
    let cache = Cache(db: db, queue: cacheQueue)!

    repo = SearchRepository(
      cache: cache
    , queue: queue
    , svc: svc()
    )
  }

  override func tearDown () {
    repo = nil
    super.tearDown()
  }

  func testSuggest () {
    let exp = self.expectationWithDescription("suggest")
    repo?.suggest("china", cb: { (error, found) -> Void in
      XCTAssertNil(error)
      let wanted = [Suggestion(cat: .Store, term: "china", ts: nil)]
      XCTAssertEqual(found!, wanted)
    }, end: { error -> Void in
      XCTAssertNil(error)
      exp.fulfill()
    })
    self.waitForExpectationsWithTimeout(10) { er in
      XCTAssertNil(er)
    }
  }

  func testSuggestCached () {
    let exp = self.expectationWithDescription("suggest")
    repo?.suggest("china", cb: { (error, found) -> Void in
      XCTAssertNil(error)
      let wanted = [Suggestion(cat: .Store, term: "china", ts: nil)]
      XCTAssertEqual(found!, wanted)
      }, end: { error -> Void in
        XCTAssertNil(error)
        exp.fulfill()
    })
    self.waitForExpectationsWithTimeout(10) { er in
      XCTAssertNil(er)
    }
  }
}
