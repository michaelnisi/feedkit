//
//  SearchRepositoryTests.swift
//  FeedKit
//
//  Created by Michael Nisi on 17/12/15.
//  Copyright © 2015 Michael Nisi. All rights reserved.
//

import XCTest
import FanboyKit

@testable import FeedKit

private func freshFanboy(string: String = "http://localhost:8383") -> Fanboy {
  let baseURL = NSURL(string: string)!
  let queue = dispatch_queue_create("com.michaelnisi.fanboy.json", DISPATCH_QUEUE_CONCURRENT)
  let conf = NSURLSessionConfiguration.defaultSessionConfiguration()
  conf.HTTPShouldUsePipelining = true
  conf.requestCachePolicy = .ReloadIgnoringLocalCacheData
  let session = NSURLSession(configuration: conf)
  return Fanboy(URL: baseURL, queue: queue, session: session)
}

class SearchRepositoryTests: XCTestCase {
  var repo: SearchRepository!
  var cache: Cache!
  var svc: Fanboy!
  
  override func setUp() {
    super.setUp()
    cache = freshCache(self.classForCoder)
    svc = freshFanboy()
    let queue = NSOperationQueue()
    repo = SearchRepository(cache: cache, queue: queue, svc: svc)
  }
  
  override func tearDown() {
    try! destroyCache(cache)
    super.tearDown()
  }
  
  // Mark: Search
  
  func testSearch() {
    let exp = self.expectationWithDescription("search")
    func go(done: Bool = false) {
      repo.search("apple") { error, feeds in
        XCTAssertNil(error)
        XCTAssert(feeds!.count > 0)
        if done {
          for feed in feeds! {
            XCTAssertNotNil(feed.ts, "should be cached")
          }
          exp.fulfill()
        } else {
          for feed in feeds! {
            XCTAssertNil(feed.ts)
          }
          dispatch_sync(dispatch_get_main_queue()) {
            go(true)
          }
        }
      }
    }
    go()
    self.waitForExpectationsWithTimeout(10) { er in
      XCTAssertNil(er)
    }
  }
  
  func testSearchWithNoResult() {
    let exp = self.expectationWithDescription("search")
    func go(terms: [String]) {
      guard !terms.isEmpty else {
        return exp.fulfill()
      }
      var t = terms
      let term = t.removeFirst()
      repo.search(term) { error, feeds in
        XCTAssertNil(error)
        XCTAssertEqual(feeds!.count, 0)
        dispatch_sync(dispatch_get_main_queue()) {
          go(t)
        }
      }
    }
    // Mere speculation that these return no results from iTunes.
    go(["0", "0a", "0", "0a"])
    self.waitForExpectationsWithTimeout(10) { er in
      XCTAssertNil(er)
    }
  }
  
  func testSearchConcurrently() {
    let exp = self.expectationWithDescription("feeds")
    let repo = self.repo
    let terms = ["apple", "gruber", "newyorker", "nyt", "literature"]
    var count = terms.count
    let label = "com.michaelnisi.tmp"
    let queue = dispatch_queue_create(label, DISPATCH_QUEUE_CONCURRENT)
    for term in terms {
      dispatch_async(queue) {
        repo.search(term) { er, feeds in
          XCTAssertNil(er)
          XCTAssertNotNil(feeds)
          dispatch_async(dispatch_get_main_queue()) {
            count -= 1
            if count == 0 {
              exp.fulfill()
            }
          }
        }
      }
    }
    self.waitForExpectationsWithTimeout(10) { er in
      XCTAssertNil(er)
    }
  }
  
  func testSearchCancel() {
    let exp = self.expectationWithDescription("search")
    let op = repo.search("apple") { er, feeds in
      XCTAssertEqual(er as? FeedKitError , FeedKitError.CancelledByUser)
      XCTAssert(feeds!.isEmpty)
      exp.fulfill()
    }
    op.cancel()
    self.waitForExpectationsWithTimeout(10) { er in
      XCTAssertNil(er)
    }
  }
}
