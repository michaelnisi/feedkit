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
  let label = "com.michaelnisi.fanboy.json"
  let queue = dispatch_queue_create(label, DISPATCH_QUEUE_CONCURRENT)
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
      repo.search("john   gruber", perFindGroupBlock: { error, finds in
        XCTAssertNil(error)
        XCTAssert(finds.count > 0)
        if !done {
          for find in finds {
            XCTAssertNil(find.ts)
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
    self.waitForExpectationsWithTimeout(61) { er in
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
      repo.search(term, perFindGroupBlock: { error, finds in
        XCTAssertNil(error)
        XCTAssertEqual(finds.count, 0)
      }) { error in
        XCTAssertNil(error)
        dispatch_async(dispatch_get_main_queue()) {
          go(t)
        }
      }
    }
    // Mere speculation that these return no results from iTunes.
    go(["0", "0a", "0", "0a"])
    self.waitForExpectationsWithTimeout(61) { er in
      XCTAssertNil(er)
    }
  }
  
  func testSearchConcurrently() {
    let exp = self.expectationWithDescription("search")
    let repo = self.repo
    let terms = ["apple", "gruber", "newyorker", "nyt", "literature"]
    var count = terms.count
    let label = "com.michaelnisi.tmp"
    let queue = dispatch_queue_create(label, DISPATCH_QUEUE_CONCURRENT)
    for term in terms {
      dispatch_async(queue) {
        repo.search(term, perFindGroupBlock: { er, finds in
          XCTAssertNil(er)
          XCTAssertNotNil(finds)
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
    self.waitForExpectationsWithTimeout(61) { er in
      XCTAssertNil(er)
    }
  }
  
  func testSearchCancel() {
    let exp = self.expectationWithDescription("search")
    let op = repo.search("apple", perFindGroupBlock: { er, finds in
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
        XCTAssertEqual(found, wanted, "should apply callback sequentially")
        exp.fulfill()
      }
    }
    
    try! populate()
    
    let terms = ["apple", "automobile", "art"]
    for (i, term) in terms.enumerate() {
      repo.search(term, perFindGroupBlock: { error, finds in
        XCTAssertNil(error)
        XCTAssert(finds.count > 0)
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
  
  func testFirstSuggestion() {
    let exp = self.expectationWithDescription("suggest")
    let term = "apple"
    var found: String?
    repo.suggest(term, perFindGroupBlock: { error, finds in
      XCTAssertNil(error)
      XCTAssert(!finds.isEmpty, "should never be empty")
      guard found == nil else { return }
      switch finds.first! {
      case .SuggestedTerm(let sug):
        found = sug.term
      default:
        XCTFail("should suggest term")
      }
    }) { error in
      XCTAssertNil(error)
      XCTAssertEqual(found, term)
      exp.fulfill()
    }
    self.waitForExpectationsWithTimeout(10) { er in XCTAssertNil(er) }
  }
  
  func testCancelledSuggest() {
    for _ in 0...100 {
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
}
