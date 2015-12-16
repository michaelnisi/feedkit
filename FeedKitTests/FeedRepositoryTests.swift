//
//  FeedRepositoryTests.swift
//  FeedKit
//
//  Created by Michael Nisi on 11/10/15.
//  Copyright © 2015 Michael Nisi. All rights reserved.
//

import XCTest
import MangerKit

@testable import FeedKit

class FeedRepositoryTests: XCTestCase {
  
  var repo: FeedRepository!
  var cache: Cache!
  var svc: Manger!
  
  func freshManger(string: String = "http://localhost:8384") -> Manger {
    let baseURL = NSURL(string: string)!
    let queue = dispatch_queue_create("com.michaelnisi.manger.json", DISPATCH_QUEUE_CONCURRENT)
    let conf = NSURLSessionConfiguration.defaultSessionConfiguration()
    conf.HTTPShouldUsePipelining = true
    let session = NSURLSession(configuration: conf)
    return Manger(URL: baseURL, queue: queue, session: session)
  }
  
  override func setUp() {
    super.setUp()
    cache = freshCache(self.classForCoder)
    svc = freshManger()
    let queue = NSOperationQueue()
    repo = FeedRepository(cache: cache, svc: svc, queue: queue)
  }
  
  override func tearDown() {
    try! destroyCache(cache)
    super.tearDown()
  }
  
  lazy var urls: [String] = {
    let bundle = NSBundle(forClass: self.classForCoder)
    let url = bundle.URLForResource("feed_query", withExtension: "json")
    let json = try! JSONFromFileAtURL(url!)
    let urls = json.map { $0["url"] as! String }
    return urls
  }()
  
  lazy var intervals: [EntryInterval] = {
    return self.urls.map { EntryInterval(url: $0) }
  }()
  
  // MARK: General
  
  func testSubtractStringsFromStrings() {
    let f = subtractStrings
    let abc = ["a", "b", "c"]
    let found = [
      f(abc, fromStrings: abc),
      f(abc, fromStrings: abc + ["d"]),
      f(abc, fromStrings: abc + ["d", "e", "f"])
    ]
    let wanted = [
      [],
      ["d"],
      ["e", "f", "d"]
    ]
    for (i, b) in wanted.enumerate() {
      let a = found[i]
      XCTAssertEqual(a, b)
    }
  }
  
  // MARK: Feeds
  
  func testFeeds() {
    let exp = self.expectationWithDescription("feeds")
    let urls = self.urls
    let cache = self.cache
    let wanted = urls
    repo.feeds(urls) { er, feeds in
      XCTAssertNil(er)
      let found = feeds.map { $0.url }
      XCTAssertEqual(found, wanted)
      urls.forEach() { url in
        XCTAssertTrue(cache.hasURL(url))
      }
      exp.fulfill()
    }
    self.waitForExpectationsWithTimeout(10) { er in
      XCTAssertNil(er)
    }
  }
  
  func testFeedsRecursively() {
    let exp = self.expectationWithDescription("feeds")
    func go(var urls: [String]) {
      guard !urls.isEmpty else {
        return exp.fulfill()
      }
      let url = urls.popLast()
      repo.feeds([url!]) { er, feeds in
        XCTAssertNil(er)
        XCTAssertNotNil(feeds)
        go(urls)
      }
    }
    go(self.urls)
    self.waitForExpectationsWithTimeout(10) { er in
      XCTAssertNil(er)
    }
  }
  
  func testFeedsConcurrently() {
    let exp = self.expectationWithDescription("feeds")
    let repo = self.repo
    var count = urls.count
    let queue = dispatch_queue_create("com.michaelnisi.tmp", DISPATCH_QUEUE_CONCURRENT)
    urls.forEach { url in
      dispatch_async(queue) {
        repo.feeds([url]) { er, feeds in
          XCTAssertNil(er)
          XCTAssertNotNil(feeds)
          dispatch_sync(dispatch_get_main_queue()) {
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
  
  func testFeedsFromCache() {
    let (cached, stale, notCached) = try! feedsFromCache(cache, withURLs: urls)
    XCTAssert(cached.isEmpty)
    XCTAssert(stale.isEmpty)
    XCTAssertEqual(notCached!, urls)
  }
  
  func testFeedsFallback() {
    let exp = self.expectationWithDescription("feeds")
    let wanted = urls
    let unavailable = freshManger("http://localhost:8385")
    let ttl = CacheTTL(short: 0, medium: 0, long: 0)
    let zeroCache = freshCache(classForCoder, ttl: ttl)
    let queue = NSOperationQueue()
    let a = FeedRepository(cache: zeroCache, svc: unavailable, queue: queue)
    func go() {
      a.feeds(urls) { er, feeds in
        XCTAssertNotNil(er)
        do {
          throw er!
        } catch FeedKitError.ServiceUnavailable(let er, let urls) {
          XCTAssertEqual(er._code, -1004)
          XCTAssertEqual(subtractStrings(urls, fromStrings: self.urls).count, 0)
        } catch {
          XCTFail("should be expected error")
        }
        let found = feeds.map { $0.url }
        XCTAssertEqual(found, wanted)
        exp.fulfill()
      }
    }
    let b = FeedRepository(cache: zeroCache, svc: svc, queue: queue)
    b.feeds(urls) { er, feeds in
      XCTAssertNil(er)
      let found = feeds.map { $0.url }
      XCTAssertEqual(found, wanted)
      go()
    }
    self.waitForExpectationsWithTimeout(10) { er in
      XCTAssertNil(er)
    }
  }
  
  func testFeedsOneExtra() {
    let exp = self.expectationWithDescription("feeds")
    let wanted = urls
    func go() {
      let extra = try! feedWithName("thetalkshow")
      repo.feeds(urls + [extra.url]) { er, feeds in
        XCTAssertEqual(feeds.count, 11)
        exp.fulfill()
      }
    }
    repo.feeds(urls) { er, feeds in
      XCTAssertNil(er)
      let found = feeds.map { $0.url }
      XCTAssertEqual(found, wanted)
      go()
    }
    self.waitForExpectationsWithTimeout(10) { er in
      XCTAssertNil(er)
    }
  }
  
  func testFeedsAllCached() {
    let exp = self.expectationWithDescription("feeds")
    let wanted = urls
    func go() {
      repo.feeds(urls) { er, feeds in
        XCTAssertEqual(feeds.count, 10)
        exp.fulfill()
      }
    }
    repo.feeds(urls) { er, feeds in
      XCTAssertNil(er)
      let found = feeds.map { $0.url }
      XCTAssertEqual(found, wanted)
      go()
    }
    self.waitForExpectationsWithTimeout(10) { er in
      XCTAssertNil(er)
    }
  }
  
  func testFeedsCancel() {
    let exp = self.expectationWithDescription("feeds")
    let op = repo.feeds(urls) { er, feeds in
      XCTAssertEqual(er as? FeedKitError , FeedKitError.CancelledByUser)
      XCTAssert(feeds.isEmpty)
      exp.fulfill()
    }
    op.cancel()
    self.waitForExpectationsWithTimeout(10) { er in
      XCTAssertNil(er)
    }
  }
  
  // MARK: Entries

  func testEntries() {
    let exp = self.expectationWithDescription("entries")
    repo.entries(intervals) { error, entries in
      XCTAssertNil(error)
      XCTAssert(entries.count > 0)
      exp.fulfill()
    }
    self.waitForExpectationsWithTimeout(10) { er in
      XCTAssertNil(er)
    }
  }
  
  func testEntriesCancel() {
    let exp = self.expectationWithDescription("entries")
    let op = repo.entries(intervals) { er, entries in
      XCTAssertEqual(er as? FeedKitError , FeedKitError.CancelledByUser)
      XCTAssert(entries.isEmpty)
      exp.fulfill()
    }
    op.cancel()
    self.waitForExpectationsWithTimeout(10) { er in
      XCTAssertNil(er)
    }
  }
  
  func testEntriesConcurrently() {
    let exp = self.expectationWithDescription("entries")
    let repo = self.repo
    var count = intervals.count
    let queue = dispatch_queue_create("com.michaelnisi.tmp", DISPATCH_QUEUE_CONCURRENT)
    intervals.forEach { query in
      dispatch_async(queue) {
        repo.entries([query]) { er, entries in
          XCTAssertNil(er)
          XCTAssertNotNil(entries)
          dispatch_sync(dispatch_get_main_queue()) {
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
  
  func testEntriesAllCached() {
    let exp = self.expectationWithDescription("entries")
    let wanted = urls
    func go() {
      repo.entries(intervals) { er, entries in
        XCTAssertNil(er)
        XCTAssert(entries.count > 0)
        for entry in entries {
          XCTAssertNotNil(entry.ts)
        }
        let found = entries.map { $0.feed }
        wanted.forEach { url in
          XCTAssertTrue(found.contains(url))
        }
        exp.fulfill()
      }
    }
    repo.entries(intervals) { er, entries in
      XCTAssertNil(er)
      XCTAssert(entries.count > 0)
      for entry in entries {
        XCTAssertNil(entry.ts)
      }
      go()
    }
    self.waitForExpectationsWithTimeout(30) { er in
      XCTAssertNil(er)
    }
  }
  
  func testEntriesInterval() {
    let url = urls.first!
    let since = NSDate(timeIntervalSinceNow: -3600 * 24 * 14)
    let interval = EntryInterval(url: url, since: since)
    let exp = self.expectationWithDescription("entries")
    var done = false
    repo.entries([interval]) { er, entries in
      XCTAssertNil(er)
      XCTAssertFalse(entries.isEmpty)
      if done {
        exp.fulfill()
      }
      done = true
    }
    repo.entries([EntryInterval(url: url, since: NSDate())]) { er, entries in
      XCTAssertNil(er)
      XCTAssert(entries.isEmpty)
      if done {
        exp.fulfill()
      }
      done = true
    }
    self.waitForExpectationsWithTimeout(10) { er in
      XCTAssertNil(er)
    }
  }
  
  // TODO: Add more entries tests
}
