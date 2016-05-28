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
    let label = "com.michaelnisi.manger.json"
    let queue = dispatch_queue_create(label, DISPATCH_QUEUE_CONCURRENT)
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
  
  lazy var locators: [EntryLocator] = {
    return self.urls.map { EntryLocator(url: $0) }
  }()
  
  // MARK: General
  
  func testLatest() {
    struct Thing: Cachable {
      let url: String
      let ts: NSDate?
      func equals(rhs: Thing) -> Bool {
        return url == rhs.url
      }
    }
    let a = Thing(url: "abc", ts: NSDate(timeIntervalSince1970: 0))
    let b = Thing(url: "def", ts: NSDate(timeIntervalSince1970: 3600))
    let c = Thing(url: "ghi", ts: NSDate(timeIntervalSince1970: 7200))
    let found = [
      latest([a, b, c]),
      latest([c, b, a]),
      latest([a, c, b]),
      latest([b, c, a])
    ]
    let wanted = [
      c,
      c,
      c,
      c
    ]
    for (i, b) in wanted.enumerate() {
      let a = found[i]
      XCTAssert(a.equals(b))
    }
  }
  
  func testSubtractStringsFromStrings() {
    let f = subtractStrings
    let abc = ["a", "b", "c"]
    let found = [
      f(abc, fromStrings: abc),
      f(abc, fromStrings: abc + ["d"]),
      f(abc, fromStrings: abc + ["d", "e", "f"]),
      f(["a", "a"], fromStrings: abc),
      f(["c", "c", "a", "a"], fromStrings: abc)
    ]
    let wanted = [
      [],
      ["d"],
      ["d", "e", "f"],
      ["b", "c"],
      ["b"]
    ]
    for (i, b) in wanted.enumerate() {
      let a = found[i]
      XCTAssert(a == b || a == ["e", "f", "d"])
    }
  }
  
  // MARK: Feeds
  
  func testFeeds() {
    let exp = self.expectationWithDescription("feeds")
    let urls = self.urls
    let cache = self.cache
    let wanted = urls
    var found = [String]()
    repo.feeds(urls, feedsBlock: { er, feeds in
      XCTAssertNil(er)
      XCTAssert(!feeds.isEmpty)
      found += feeds.map { $0.url }
    }) { er in
      XCTAssertNil(er)
      exp.fulfill()
    }
    self.waitForExpectationsWithTimeout(10) { er in
      XCTAssertNil(er)
      XCTAssertEqual(found, wanted)
      urls.forEach() { url in
        XCTAssertTrue(cache.hasURL(url))
      }
    }
  }
  
  func testFeedsRecursively() {
    let exp = self.expectationWithDescription("feeds")
    var count = 0
    var urls = self.urls
    func go() {
      guard !urls.isEmpty else {
        return exp.fulfill()
      }
      let url = urls.popLast()!
      repo.feeds([url], feedsBlock: { er, feeds in
        XCTAssertNil(er)
        count += feeds.count
      }) { er in
        XCTAssertNil(er)
        go()
      }
    }
    go()
    self.waitForExpectationsWithTimeout(10) { er in
      XCTAssertNil(er)
      XCTAssertEqual(count, 10)
    }
  }
  
  func testFeedsConcurrently() {
    let exp = self.expectationWithDescription("feeds")
    let repo = self.repo
    let label = "com.michaelnisi.tmp"
    let q = dispatch_queue_create(label, DISPATCH_QUEUE_CONCURRENT)
    
    var n = urls.count
    var count = 0
    
    urls.forEach { url in
      dispatch_async(q) {
        repo.feeds([url], feedsBlock: { er, feeds in
          XCTAssertNil(er)
          count += feeds.count
        }) { er in
          XCTAssertNil(er)
          dispatch_async(dispatch_get_main_queue()) {
            n -= 1
            if (n == 0) {
              exp.fulfill()
            }
          }
        }
      }
    }
    self.waitForExpectationsWithTimeout(10) { er in
      XCTAssertNil(er)
      XCTAssertEqual(count, 10)
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

    let repo = FeedRepository(cache: zeroCache, svc: unavailable, queue: queue)
    var found = [String]()
    func go() {
      repo.feeds(urls, feedsBlock: { er, feeds in
        XCTAssertNil(er)
        found += feeds.map { $0.url }
      }) { er in
        XCTAssertNotNil(er)
        do {
          throw er!
        } catch FeedKitError.ServiceUnavailable(let er) {
          XCTAssertEqual(er._code, -1004)
        } catch {
          XCTFail("should be expected error")
        }
        XCTAssertEqual(found, wanted)
        exp.fulfill()
      }
    }

    do {
      let repo = FeedRepository(cache: zeroCache, svc: svc, queue: queue)
      var found = [String]()
      repo.feeds(urls, feedsBlock: { er, feeds in
        XCTAssertNil(er)
        found += feeds.map { $0.url }
      }) { er in
        XCTAssertNil(er)
        XCTAssertEqual(found, wanted)
        go()
      }
      self.waitForExpectationsWithTimeout(10) { er in
        XCTAssertNil(er)
      }
    }
  }
  
  func testFeedsOneExtra() {
    let exp = self.expectationWithDescription("feeds")
    let wanted = urls
    var count = 0
    func go() {
      let extra = try! feedWithName("thetalkshow")
      repo.feeds(urls + [extra.url], feedsBlock: { er, feeds in
        count += feeds.count
      }) { er in
        exp.fulfill()
      }
    }
    repo.feeds(urls, feedsBlock: { er, feeds in
      XCTAssertNil(er)
      let found = feeds.map { $0.url }
      XCTAssertEqual(found, wanted)
      count += feeds.count
    }) { er in
      go()
    }
    self.waitForExpectationsWithTimeout(10) { er in
      XCTAssertNil(er)
      XCTAssertEqual(count, 21)
    }
  }
  

  func testFeedsAllCached() {
    let exp = self.expectationWithDescription("feeds")
    let wanted = urls
    var count = 0
    func go() {
      repo.feeds(urls, feedsBlock: { er, feeds in
        XCTAssertNil(er)
        count += feeds.count
      }) { er in
        XCTAssertNil(er)
        exp.fulfill()
      }
    }
    repo.feeds(urls, feedsBlock: { er, feeds in
      XCTAssertNil(er)
      count += feeds.count
      let found = feeds.map { $0.url }
      XCTAssertEqual(found, wanted)
    }) { er in
      XCTAssertNil(er)
      go()
    }
    self.waitForExpectationsWithTimeout(10) { er in
      XCTAssertNil(er)
      XCTAssertEqual(count, 20)
    }
  }
  
  func testFeedsCancel() {
    let exp = self.expectationWithDescription("feeds")
    let op = repo.feeds(urls, feedsBlock: { er, feeds in
      XCTAssertNil(er)
      XCTAssert(feeds.isEmpty)
    }) { er in
      XCTAssertEqual(er as? FeedKitError , FeedKitError.CancelledByUser)
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
    var found = [Entry]()
    repo.entries(locators, entriesBlock: { error, entries in
      XCTAssertNil(error)
      XCTAssertFalse(entries.isEmpty)
      found += entries
    }) { er in
      XCTAssertNil(er)
      exp.fulfill()
    }
    self.waitForExpectationsWithTimeout(10) { er in
      XCTAssertNil(er)
      XCTAssertFalse(found.isEmpty)
    }
  }
  
  func testEntriesWithGuid() {
    let exp = self.expectationWithDescription("entries")
    let repo = self.repo
    var entry: Entry?
    repo.entries(locators, entriesBlock: { error, entries in
      XCTAssertNil(error)
      entry = entries.last // any should do
    }) { er in
      XCTAssertNil(er)
      let url = entry!.feed
      let guid = entry!.guid
      XCTAssertEqual(guid, entryGUID(url, id: entry!.id, updated: entry!.updated))
      let since = NSDate(timeInterval: -1, sinceDate: entry!.updated)
      print(url)
      let locators = [
        EntryLocator(url: url, since: since, guid: guid)
      ]
      var found = [Entry]()
      repo.entries(locators, entriesBlock: { error, entries in
        XCTAssertNil(error)
        XCTAssertFalse(entries.isEmpty)
        found += entries
      }) { er in
        XCTAssertNil(er)
        XCTAssertFalse(found.isEmpty)
        let guids = found.map { $0.guid }
        XCTAssertEqual(guids.count, 1)
        XCTAssertEqual(guids.first!, guid)
        exp.fulfill()
      }
    }
    self.waitForExpectationsWithTimeout(10) { er in
      XCTAssertNil(er)
    }
  }
  
  func testEntriesCancel() {
    let exp = self.expectationWithDescription("entries")
    let op = repo.entries(locators, entriesBlock: { er, entries in
      XCTFail("should not be applied")
    }) { er in
      XCTAssertEqual(er as? FeedKitError , FeedKitError.CancelledByUser)
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
    let label = "com.michaelnisi.tmp"
    let q = dispatch_queue_create(label, DISPATCH_QUEUE_CONCURRENT)
    

    let min = locators.count
    var count = 0
    var n = locators.count
    
    locators.forEach { query in
      dispatch_async(q) {
        repo.entries([query], entriesBlock: { er, entries in
          XCTAssertNil(er)
          XCTAssertFalse(entries.isEmpty)
          count += entries.count
        }) { er in
          n -= 1
          if n == 0 {
            XCTAssert(count > min)
            exp.fulfill()
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
    var found = [Entry]()
    
    func go() {
      repo.entries(locators, entriesBlock: { er, entries in
        XCTAssertNil(er)
        XCTAssertFalse(entries.isEmpty)
        found += entries
      }) { er in
        XCTAssertNil(er)
        XCTAssertFalse(found.isEmpty)
        for entry in found {
          XCTAssertNotNil(entry.ts, "should be cached")
        }
        let urls = found.map { $0.feed }
        wanted.forEach { url in
          XCTAssertTrue(urls.contains(url))
        }
        exp.fulfill()
      }
    }
    
    do {
      var found = [Entry]()
      repo.entries(locators, entriesBlock: { er, entries in
        XCTAssertNil(er)
        XCTAssertFalse(entries.isEmpty)
        found += entries
      }) { er in
        XCTAssertNil(er)
        XCTAssertFalse(found.isEmpty)
        for entry in found {
          XCTAssertNil(entry.ts, "should not be cached")
        }
        go()
      }
    }
    
    self.waitForExpectationsWithTimeout(30) { er in
      XCTAssertNil(er)
    }
  }
  
  func testEntriesInterval() {
    let exp = self.expectationWithDescription("entries")
    
    let url = urls.first! // This American Life
    var done = false
    
    do {
      // Any interval reasonable for the “This American Life” feed.
      let threeWeeks = NSTimeInterval(-3600 * 24 * 21)
      let since = NSDate(timeIntervalSinceNow: threeWeeks)
      let interval = EntryLocator(url: url, since: since)
      repo.entries([interval], entriesBlock: { er, entries in
        XCTAssertNil(er)
        XCTAssertFalse(entries.isEmpty)
      }) { er in
        XCTAssertNil(er)
        if done { exp.fulfill() }
        done = true
      }
    }
    
    do {
      let interval = EntryLocator(url: url, since: NSDate())
      repo.entries([interval], entriesBlock:  { er, entries in
        XCTAssertNil(er)
        XCTAssert(entries.isEmpty)
      }) { er in
        XCTAssertNil(er)
        if done { exp.fulfill() }
        done = true
      }
    }
    
    self.waitForExpectationsWithTimeout(10) { er in
      XCTAssertNil(er)
    }
  }
}
