//
//  FeedRepositoryTests.swift
//  FeedKit
//
//  Created by Michael Nisi on 11/10/15.
//  Copyright © 2015 Michael Nisi. All rights reserved.
//

import XCTest
import MangerKit
import Ola
import Patron

@testable import FeedKit

final class FeedRepositoryTests: XCTestCase {
  
  var repo: Browsing!
  var cache: Cache!
  var svc: MangerService!
  
  override func setUp() {
    super.setUp()
    
    cache = freshCache(self.classForCoder)
    
    svc = freshManger(string: "http://localhost:8384")
    
    let queue = OperationQueue()
    queue.underlyingQueue = DispatchQueue(label: "ink.codes.feedkit.FeedRepositoryTests")

    let probe = Ola(host: "http://localhost:8384", queue: queue.underlyingQueue!)!
    
    repo = FeedRepository(cache: cache, svc: svc, queue: queue, probe: probe)
  }
  
  override func tearDown() {
    try! destroyCache(cache)
    super.tearDown()
  }
  
  lazy var urls: [String] = {
    let bundle = Bundle(for: self.classForCoder)
    let url = bundle.url(forResource: "feed_query", withExtension: "json")
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
      let ts: Date?
      func equals(_ rhs: Thing) -> Bool {
        return url == rhs.url
      }
    }
    let a = Thing(url: "abc", ts: Date(timeIntervalSince1970: 0))
    let b = Thing(url: "def", ts: Date(timeIntervalSince1970: 3600))
    let c = Thing(url: "ghi", ts: Date(timeIntervalSince1970: 7200))
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
    for (i, b) in wanted.enumerated() {
      let a = found[i]
      XCTAssert(a.equals(b))
    }
  }
  
  func testSubtractStringsFromStrings() {
    let abc = ["a", "b", "c"]
    let found = [
      subtract(strings: abc, from: abc),
      subtract(strings: abc, from: abc + ["d"]),
      subtract(strings: abc, from: abc + ["d", "e", "f"]),
      subtract(strings: ["a", "a"], from: abc),
      subtract(strings: ["c", "c", "a", "a"], from: abc)
    ]
    let wanted = [
      [],
      ["d"],
      ["d", "e", "f"],
      ["b", "c"],
      ["b"]
    ]
    for (i, b) in wanted.enumerated() {
      let a = found[i]
      XCTAssert(a == b || a == ["e", "f", "d"])
    }
  }
  
  // MARK: Feeds
  
  func testFeeds() {
    let exp = self.expectation(description: "feeds")
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
    
    self.waitForExpectations(timeout: 10) { er in
      XCTAssertNil(er)
      XCTAssertEqual(found, wanted)
      urls.forEach() { url in
        XCTAssertTrue((cache?.hasURL(url))!)
      }
    }
  }
  
  func testFeedsRecursively() {
    let exp = self.expectation(description: "feeds")
    var count = 0
    var urls = self.urls
    func go() {
      guard !urls.isEmpty else {
        return exp.fulfill()
      }
      let url = urls.popLast()!
      let _ = repo.feeds([url], feedsBlock: { er, feeds in
        XCTAssertNil(er)
        count += feeds.count
      }) { er in
        XCTAssertNil(er)
        go()
      }
    }
    go()
    self.waitForExpectations(timeout: 10) { er in
      XCTAssertNil(er)
      XCTAssertEqual(count, 9)
    }
  }
  
  func testFeedsConcurrently() {
    let exp = self.expectation(description: "feeds")
    let repo = self.repo!
    
    let q = DispatchQueue.global(qos: .userInitiated)
    
    var n = urls.count
    var count = 0
    
    urls.forEach { url in
      q.async {
        let _ = repo.feeds([url], feedsBlock: { er, feeds in
          XCTAssertNil(er)
          count += feeds.count
        }) { er in
          XCTAssertNil(er)
          DispatchQueue.main.async() {
            n -= 1
            if (n == 0) {
              exp.fulfill()
            }
          }
        }
      }
    }
    
    self.waitForExpectations(timeout: 10) { er in
      XCTAssertNil(er)
      XCTAssertEqual(count, 9)
    }
  }
  
  func testFeedsFromCache() {
    let (cached, stale, notCached) = try!
      feeds(in: cache, with: urls, within: CacheTTL.long.seconds)
    
    XCTAssert(cached.isEmpty)
    XCTAssert(stale.isEmpty)
    XCTAssertEqual(notCached!, urls)
  }
  
  // TODO: Review this test
  
  func testCachedFeeds() {
    let exp = self.expectation(description: "feeds")
    
    let falseHost = "http://localhost:8385"
    let unavailable = freshManger(string: falseHost)
    
    let zeroCache = freshCache(classForCoder)
    let queue = OperationQueue()
    let probe = Ola(host: "localhost", queue: DispatchQueue.main)!
    
    let a: Browsing = FeedRepository(
      cache: zeroCache, svc: unavailable, queue: queue, probe: probe)
    
    var found = [String]()
    let wanted = urls
    
    func go() {
      var ended = false
      a.feeds(urls, feedsBlock: { er, feeds in
        XCTAssertNil(er)
        found += feeds.map { $0.url }
      }) { er in
        XCTAssertFalse(ended, "should end only once")
        ended = true
        XCTAssertEqual(found, wanted)
        exp.fulfill()
      }
    }

    do { // Cache Loading
      let probe = Ola(host: "localhost", queue: DispatchQueue.main)!
      let b: Browsing = FeedRepository(
        cache: zeroCache, svc: svc, queue: queue, probe: probe)
      
      var found = [String]()
      var ended = false
      b.feeds(urls, feedsBlock: { er, feeds in
        XCTAssertNil(er)
        found += feeds.map { $0.url }
      }) { er in
        XCTAssertFalse(ended, "should end only once")
        ended = true
        XCTAssertNil(er)
        XCTAssertEqual(found, wanted)
        go()
      }
      self.waitForExpectations(timeout: 10) { er in
        XCTAssertNil(er)
      }
    }
  }
  
  func testFeedsOneExtra() {
    let exp = self.expectation(description: "feeds")
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
      // TODO: Test redirection
      // http://feeds.soundcloud.com/users/soundcloud:users:180603351/sounds.rss
      // This RSS feed has been redirected, and SoundCloud cannot guarantee the 
      // safety of external links. If you would like to continue, you can 
      // navigate to 'https://rss.art19.com/women-of-the-hour'. RSS Readers and 
      // Podcasting apps will be redirected automatically.
      XCTAssertEqual(found, wanted)
      count += feeds.count
    }) { er in
      go()
    }
    self.waitForExpectations(timeout: 10) { er in
      XCTAssertNil(er)
      XCTAssertEqual(count, wanted.count * 2 + 1)
    }
  }
  

  func testFeedsAllCached() {
    let exp = self.expectation(description: "feeds")
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
    
    self.waitForExpectations(timeout: 10) { er in
      XCTAssertNil(er)
      XCTAssertEqual(count, wanted.count * 2)
    }
  }
  
  func testFeedsCancel() {
    let exp = self.expectation(description: "feeds")
    let op = repo.feeds(urls, feedsBlock: { er, feeds in
      XCTAssertNil(er)
      XCTAssert(feeds.isEmpty)
    }) { er in
      XCTAssertEqual(er as? FeedKitError, FeedKitError.cancelledByUser)
      exp.fulfill()
    }
    op.cancel()
    self.waitForExpectations(timeout: 10) { er in
      XCTAssertNil(er)
    }
  }
  
  // MARK: Entries

  func testEntries() {
    let exp = self.expectation(description: "entries")
    var found = [Entry]()
    repo.entries(locators, entriesBlock: { error, entries in
      XCTAssertNil(error)
      XCTAssertFalse(entries.isEmpty)
      found += entries
    }) { er in
      XCTAssertNil(er, "should succeed without error: \(String(describing: er))")
      exp.fulfill()
    }
    self.waitForExpectations(timeout: 10) { er in
      XCTAssertNil(er)
      XCTAssertFalse(found.isEmpty)
    }
  }
  
  func testEntriesWithGUID() {
    let exp = self.expectation(description: "entries")
    let repo = self.repo!
    
    // A very brittle test, the publisher might remove the entry with this
    // GUID at any time. If it fails, replace guid with an existing one.
    
    let url = "http://feeds.wnyc.org/newyorkerradiohour"
    let id = "eee61768a48783c62756edd481a0364129c65be0"
    let guid = entryGUID(for: id, at: url)
    let locators = [EntryLocator(url: url, guid: guid)]
    
    var acc = [Entry]()
    
    let _ = repo.entries(locators, entriesBlock: { er, entries in
      XCTAssertNil(er)
      acc.append(contentsOf: entries)
    }) { er in
      XCTAssertNil(er)
      guard let found = acc.first else {
        return XCTFail("should find entry")
      }
      XCTAssertEqual(found.guid, guid)
      exp.fulfill()
    }
    self.waitForExpectations(timeout: 10) { er in
      XCTAssertNil(er)
    }
  }
  
  func testEntriesWithFalseGUID() {
    let exp = self.expectation(description: "entries")
    let repo = self.repo!
    
    let url = "http://feeds.wnyc.org/newyorkerradiohour"
    let guid = "hello"
    let locators = [EntryLocator(url: url, guid: guid)]
    
    let _ = repo.entries(locators, entriesBlock: { error, entries in
      switch error as! FeedKitError {
      case .missingEntries(let urls):
        XCTAssertEqual(urls, [url])
      default:
        XCTFail("should be expected error")
      }
      XCTAssert(entries.isEmpty)
    }) { error in
      XCTAssertNil(error)
      exp.fulfill()
    }
    self.waitForExpectations(timeout: 10) { er in
      XCTAssertNil(er)
    }
  }
  
  func testEntriesCancel() {
    let exp = self.expectation(description: "entries")
    let op = repo.entries(locators, entriesBlock: { er, entries in
      XCTFail("should not be applied")
    }) { er in
      XCTAssertEqual(er as? FeedKitError , FeedKitError.cancelledByUser)
      exp.fulfill()
    }
    op.cancel()
    self.waitForExpectations(timeout: 10) { er in
      XCTAssertNil(er)
    }
  }
  
  func testEntriesConcurrently() {
    let exp = self.expectation(description: "entries")
    let repo = self.repo!
    
    let q = DispatchQueue.global(qos: .userInitiated)

    let min = locators.count
    var count = 0
    var n = locators.count
    
    locators.forEach { query in
      q.async {
        let _ = repo.entries([query], entriesBlock: { er, entries in
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
    
    self.waitForExpectations(timeout: 10) { er in
      XCTAssertNil(er)
    }
  }
  
  func testEntriesAllCached() {
    let exp = self.expectation(description: "entries")
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
        go()
      }
    }
    
    self.waitForExpectations(timeout: 30) { er in
      XCTAssertNil(er)
    }
  }
  
  func testEntriesInterval() {
    let exp = self.expectation(description: "entries")
    
    let url = urls.first! // This American Life
    var done = false
    
    do {
      // Any interval reasonable for the “This American Life” feed.
      let threeWeeks = TimeInterval(-3600 * 24 * 21)
      let since = Date(timeIntervalSinceNow: threeWeeks)
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
      let interval = EntryLocator(url: url, since: Date())
      repo.entries([interval], entriesBlock:  { er, entries in
        XCTAssertNil(er)
        XCTAssert(entries.isEmpty)
      }) { er in
        XCTAssertNil(er)
        if done { exp.fulfill() }
        done = true
      }
    }
    
    self.waitForExpectations(timeout: 10) { er in
      XCTAssertNil(er)
    }
  }
}
