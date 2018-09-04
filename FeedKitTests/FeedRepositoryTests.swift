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
  var cache: FeedCache!
  var svc: MangerService!
  
  override func setUp() {
    super.setUp()
    
    cache = freshCache(self.classForCoder)
    
    svc = makeManger(string: "http://localhost:8384")
    
    let queue = OperationQueue()
    queue.underlyingQueue = DispatchQueue(label: "ink.codes.feedkit.FeedRepositoryTests")

    repo = FeedRepository(cache: cache, svc: svc, queue: queue)
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
  
}

// MARK: - Feeds

extension FeedRepositoryTests {
  
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
        XCTAssertTrue((cache?.hasURL(url))!, "should have \(url)")
      }
    }
  }
  
  func testFeedsRecursively() {
    let exp = self.expectation(description: "feeds")
    var count = 0
    var urls = self.urls
    let initialCount = urls.count
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
      XCTAssertEqual(count, initialCount)
    }
  }
  
  func testFeedsConcurrently() {
    let exp = self.expectation(description: "feeds")
    let repo = self.repo!
    
    let q = DispatchQueue.global(qos: .userInitiated)
    
    var n = urls.count
    var count = 0
    let initialCount = urls.count
    
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
      XCTAssertEqual(count, initialCount)
    }
  }
  
  func testCachedFeeds() {
    let zeroCache = freshCache(classForCoder)
    
    do {
      let exp = self.expectation(description: "populating cache")
      
      let queue = OperationQueue()
      let repo: Browsing = FeedRepository(
        cache: zeroCache, svc: svc, queue: queue)
      
      var found = [String]()
      var feedsBlockCount = 0
      
      let wanted = urls
      
      repo.feeds(urls, feedsBlock: { er, feeds in
        XCTAssertNil(er)
        DispatchQueue.main.async {
          feedsBlockCount += 1
          found += feeds.map { $0.url }
        }
      }) { er in
        XCTAssertNil(er)
        DispatchQueue.main.async {
          XCTAssert(feedsBlockCount > 0, "should run in order")
          XCTAssertEqual(found, wanted)
          exp.fulfill()
        }
      }
      
      waitForExpectations(timeout: 10) { er in
        XCTAssertNil(er)
      }
    }
    
    do {
      let falseHost = "http://localhost:8385"
      let unavailable = makeManger(string: falseHost)
      let queue = OperationQueue()
      let repo: Browsing = FeedRepository(
        cache: zeroCache, svc: unavailable, queue:queue)
      
      var found = [String]()
      var feedsBlockCount = 0
      
      let wanted = urls
      
      let exp = self.expectation(description: "falling back on cache")
      
      repo.feeds(urls, feedsBlock: { er, feeds in
        XCTAssertNil(er)
        DispatchQueue.main.async {
          feedsBlockCount += 1
          found += feeds.map { $0.url }
        }
      }) { er in
        XCTAssertNil(er)
        DispatchQueue.main.async {
          XCTAssert(feedsBlockCount > 0, "should run in order")
          XCTAssertEqual(found, wanted)
          exp.fulfill()
        }
      }
      
      waitForExpectations(timeout: 10) { er in
        XCTAssertNil(er)
      }
    }
  }
  
  func testFeedsOneExtra() {
    let exp = self.expectation(description: "feeds")
    let wanted = urls
    var count = 0
    
    func go() {
      // The Talk Show is redirected, I keep it, because it makes for a good
      // test.
      let extra = try! Common.makeFeed(name: .gruber)
      repo.feeds(urls + [extra.url], feedsBlock: { er, feeds in
        let found = feeds.map { $0.url }
        dump(found)
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
  
}

// MARK: - Entries

extension FeedRepositoryTests {
  
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
    
    let url = "http://feeds.gimletmedia.com/homecomingshow"
    let guid = "6e80b95c2e64f995252fd18b22fc964a5f401b45"
    let locators = [EntryLocator(url: url, guid: guid).including]
    
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
  
  func testEntriesWithUnknownGUID() {
    let exp = self.expectation(description: "entries")
    let repo = self.repo!
    
    let url = "http://feeds.wnyc.org/newyorkerradiohour"
    let guid = "hello, here dawg!"
    let locators = [EntryLocator(url: url, guid: guid)]
    
    repo.entries(locators, entriesBlock: { error, entries in
      switch error as! FeedKitError {
      case .missingEntries(let missingLocators):
        XCTAssertEqual(missingLocators, locators)
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

    func go() {
      let wanted = urls
      var ok = false
      var found = [Entry]()
      
      repo.entries(locators, entriesBlock: { er, entries in
        XCTAssertNil(er)
        XCTAssertFalse(entries.isEmpty)
        DispatchQueue.main.async {
          ok = true
          found += entries
        }
      }) { er in
        XCTAssertNil(er)
        DispatchQueue.main.async {
          XCTAssert(ok, "should run blocks in order")
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
    }

    do {
      var ok = false
      var found = [Entry]()
      repo.entries(locators, entriesBlock: { er, entries in
        XCTAssertNil(er)
        XCTAssertFalse(entries.isEmpty)
        DispatchQueue.main.async {
          ok = true
          found += entries
        }
      }) { er in
        XCTAssertNil(er)
        DispatchQueue.main.async {
          XCTAssert(ok, "should run blocks in order")
          XCTAssertFalse(found.isEmpty)
          go()
        }
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

