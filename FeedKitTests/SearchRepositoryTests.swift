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
  
  // MARK: Search
  
  func testSearch() {
    let exp = self.expectationWithDescription("search")
    func go(done: Bool = false) {
      repo.search("apple", feedsBlock: { error, feeds in
        XCTAssertNil(error)
        XCTAssert(feeds.count > 0)
        if !done {
          for feed in feeds {
            XCTAssertNil(feed.ts)
          }
        }
      }) { error in
        XCTAssertNil(error)
        if done {
          dispatch_async(dispatch_get_main_queue()) {
            exp.fulfill()
          }
        } else {
          dispatch_async(dispatch_get_main_queue()) {
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
        return dispatch_async(dispatch_get_main_queue()) {
          exp.fulfill()
        }
      }
      var t = terms
      let term = t.removeFirst()
      repo.search(term, feedsBlock: { error, feeds in
        XCTAssertNil(error)
        XCTAssertEqual(feeds.count, 0)
      }) { error in
        XCTAssertNil(error)
        dispatch_async(dispatch_get_main_queue()) {
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
        repo.search(term, feedsBlock: { er, feeds in
          XCTAssertNil(er)
          XCTAssertNotNil(feeds)
        }) { error in
          XCTAssertNil(error)
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
    let op = repo.search("apple", feedsBlock: { er, feeds in
      XCTFail("should not get dispatched")
    }) { error in
      XCTAssertEqual(error as? FeedKitError , FeedKitError.CancelledByUser)
      dispatch_async(dispatch_get_main_queue()) {
        exp.fulfill()
      }
    }
    op.cancel()
    self.waitForExpectationsWithTimeout(10) { er in
      XCTAssertNil(er)
    }
  }
  
  // MARK: Suggest
  
  func feedsFromFile(name: String = "feeds") throws -> [Feed] {
    let bundle = NSBundle(forClass: self.classForCoder)
    let feedsURL = bundle.URLForResource(name, withExtension: "json")
    return try feedsFromFileAtURL(feedsURL!)
  }
  
  func entriesFromFile() throws -> [Entry] {
    let bundle = NSBundle(forClass: self.classForCoder)
    let entriesURL = bundle.URLForResource("entries", withExtension: "json")
    return try entriesFromFileAtURL(entriesURL!)
  }
  
  func populate() throws -> ([Feed], [Entry]) {
    let feeds = try! feedsFromFile()
    try! cache.updateFeeds(feeds)
    
    let entries = try! entriesFromFile()
    try! cache.updateEntries(entries)
    
    return (feeds, entries)
  }
  
  func testSuggest() {
    let exp = self.expectationWithDescription("suggest")
    var op: SessionTaskOperation?
    func go() {
      var found:UInt = 4
      func shift () { found = found << 1 }
      repo.suggest("a", perFindGroupBlock: { er, finds in
        XCTAssertNil(er)
        XCTAssertFalse(finds.isEmpty)
        for find in finds {
          switch find {
          case .SuggestedTerm:
            if found ==  4 { shift() }
          case .RecentSearch:
            if found ==  8 { shift() }
          case .SuggestedFeed:
            if found == 16 { shift() }
          case .SuggestedEntry:
            if found == 32 { shift() }
          }
        }
      }) { er in
        XCTAssertNil(er)
        let wanted = UInt(64)
        XCTAssertEqual(found, wanted, "should apply all callbacks in expected order")
        exp.fulfill()
      }
    }
    
    try! populate()
    
    let terms = ["apple", "automobile", "art"]
    for (i, term) in terms.enumerate() {
      repo.search(term, feedsBlock: { error, feeds in
        XCTAssertNil(error)
        XCTAssert(feeds.count > 0)
        guard i == terms.count - 1 else { return }
      }) { error in
        dispatch_async(dispatch_get_main_queue()) {
          go()
        }
      }
    }
    self.waitForExpectationsWithTimeout(10) { er in
      XCTAssertNil(er)
    }
  }
  
  func testCancelledSuggest() {
    let exp = self.expectationWithDescription("suggest")
    let op = repo.suggest("a", perFindGroupBlock: { _, _ in
      XCTFail("should not get dispatched")
    }) { er in
      do {
        throw er!
      } catch FeedKitError.CancelledByUser {
        exp.fulfill()
      } catch {
        XCTFail("should not pass unexpected error")
      }
    }
    op.cancel()
    self.waitForExpectationsWithTimeout(10) { er in
      XCTAssertNil(er)
    }
  }
}
