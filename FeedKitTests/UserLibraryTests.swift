//
//  UserLibraryTests.swift
//  FeedKit
//
//  Created by Michael on 9/8/17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import XCTest
@testable import FeedKit

class UserLibraryTests: XCTestCase {
  
  fileprivate var user: UserLibrary!
  fileprivate var cache: UserCache!

  override func setUp() {
    super.setUp()

    let cache = freshUserCache(self.classForCoder)
    let browser = freshBrowser(self.classForCoder)
    
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    
    let user = UserLibrary.init(cache: cache, browser: browser, queue: queue)
    
    self.user = user
    self.cache = cache
  }
  
  override func tearDown() {
    user = nil
    cache = nil
    super.tearDown()
  }
  
}

// MARK: - Subscribing

extension UserLibraryTests {
  
  func testSubscribe() {
    do {
      let exp = self.expectation(description: "subscribing empty list")
      
      user.add(subscriptions: []) { error in
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertNil(error)
        exp.fulfill()
      }
    }
    
    do {
      let exp = self.expectation(description: "subscribing")

      
      let url = "http://abc.de"
      let subscriptions = [Subscription(url: url)]
      
      user.add(subscriptions: subscriptions) { error in
        XCTAssertNil(error)
        exp.fulfill()
      }
      
      self.waitForExpectations(timeout: 10) { er in
        XCTAssertNil(er)
      }
    }
  }
  
  /// Subscribes to feed at `url` and returns subscriptions for testing.
  @discardableResult
  private func subscribe(
    _ url: String,
    addComplete: @escaping (Error?) -> Void
  ) -> [Subscription] {
    let subscriptions = [Subscription(url: url)]
    user.add(subscriptions: subscriptions, completionBlock: addComplete)
    return subscriptions
  }
  
  func testUnsubscribe() {
    let url = "http://abc.de"
    
    do {
      let exp = self.expectation(description: "subscribing")
      
      subscribe(url) { error in
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertNil(error)
        exp.fulfill()
      }
      
      self.waitForExpectations(timeout: 10) { er in
        XCTAssertNil(er)
      }
    }
    
    do {
      let exp = self.expectation(description: "unsubscribing empty list")
      
      user.unsubscribe([]) { error in
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertNil(error)
        exp.fulfill()
      }
    }
    
    do {
      let exp = self.expectation(description: "unsubscribing")

      user.unsubscribe([url]) { error in
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertNil(error)
        exp.fulfill()
      }
      
      self.waitForExpectations(timeout: 10) { er in
        XCTAssertNil(er)
      }
    }
  }
  
  func testHasSubscription() {
    let url = "http://feeds.feedburner.com/Monocle24TheUrbanist"
    
    do {
      let exp = self.expectation(description: "subscribing")
      
      subscribe(url) { error in
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertNil(error)
        exp.fulfill()
      }
      
      self.waitForExpectations(timeout: 10) { er in
        XCTAssertNil(er)
      }
    }
    
    do {
      self.measure {
        XCTAssertTrue(user.has(subscription: url))
      }
      
    }
  }
  
  func testFeeds() {
    let url = "http://feeds.feedburner.com/Monocle24TheUrbanist"
    
    do {
      let exp = self.expectation(description: "subscribing")
      
      subscribe(url) { error in
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertNil(error)
        exp.fulfill()
      }
      
      self.waitForExpectations(timeout: 10) { er in
        XCTAssertNil(er)
      }
    }
    
    do {
      let exp = self.expectation(description: "fetching feeds")
      
      user.fetchFeeds(feedsBlock: { feeds, error in
        XCTAssertFalse(Thread.isMainThread)
        let found = feeds.first!.url
        let wanted = "http://feeds.feedburner.com/Monocle24TheUrbanist"
        XCTAssertEqual(found, wanted)
      }) { error in
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertNil(error)
        exp.fulfill()
      }
      
      self.waitForExpectations(timeout: 10) { er in
        XCTAssertNil(er)
      }
    }
  }
  
}

// MARK: - Updating

extension UserLibraryTests {

  func testLatestEntriesUsingSubscriptions() {
    let entries = try! entriesFromFile()
    let urls = Set(entries.map { $0.url })
    
    do {
      let subscriptions = Set(urls.map { Subscription(url: $0) })
      let found = UserLibrary.newer(from: entries, than: subscriptions)
      XCTAssertEqual(found, [])
    }
    
    do {
      // 2015-10-23T04:00:00.000Z
      let ts = Date(timeIntervalSince1970:
        serialize.timeIntervalFromJS(1445572800000)
      )
      let subscriptions: Set<Subscription> = [
        Subscription(url: "http://feeds.wnyc.org/newyorkerradiohour", ts: ts)
      ]
      let found = UserLibrary.newer(from: entries, than: subscriptions)
      XCTAssertEqual(found.count, 1)
      XCTAssertEqual(
        found.first!.title,
        "Episode Two: Amy Schumer, Jorge Ramos, and the Search for a Lost Father")
    }
  }
  
  func testUpdate() {
    do {
      let exp = expectation(description: "update")
      user.update { newData, error in
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertNil(error)
        XCTAssertFalse(newData)
        exp.fulfill()
      }
      waitForExpectations(timeout: 10) { er in
        XCTAssertNil(er)
      }
    }
  }
  
  func testPrepareUpdate() {
    do {
      let locators = [EntryLocator]()
      let subscriptions = [Subscription]()
      let found = PrepareUpdateOperation.merge(locators, with: subscriptions)
      XCTAssertEqual(found, [])
    }
    
    do {
      let locators = [EntryLocator]()
      let url = "http://abc.de"
      let ts = Date.init(timeIntervalSince1970: 0)
      let subscriptions = [Subscription(url: url, ts: ts)]
      let found = PrepareUpdateOperation.merge(locators, with: subscriptions)
      let wanted = [EntryLocator(url: url, since: ts)]
      XCTAssertEqual(found, wanted)
    }
  }
  
  func testEnqueueLatest() {
    let many = try! entriesFromFile()
    let latest = EnqueueOperation.latest(entries: many)
    let urls = latest.map { $0.feed }
    let unique = Set(urls)
    XCTAssertEqual(unique.count, urls.count, "should be unique")
    
    let found = latest.sorted { $0.updated > $1.updated }.map { $0.title }
    let wanted = [
      "Best Of: Gloria Steinem / Carrie Brownstein",
      "Playing With Perceptions",
      "Episode Two: Amy Schumer, Jorge Ramos, and the Search for a Lost Father",
      "`Josh N Chuck\'s Hallowe\'en Spooky Scarefest",
      "Mini-Episode: Lena Dunham & Emma Stone",
      "Show 56 - Kings of Kings",
      "Episode 19: Bite Marks",
      "#319: And the Call Was Coming from the Basement",
      "Update: New Normal?",
      "Episode 12: What We Know"
    ]
    XCTAssertEqual(found, wanted)
  }
  
}

// MARK: - Queueing

extension UserLibraryTests {
  
  func testMissingEntries() {
    do {
      let exp = expectation(description: "initially fetching queue")
      
      user.fetchQueue(entriesBlock: { entries, error in
        XCTFail("should not call block")
      }) { error in
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertNil(error)
        exp.fulfill()
      }
      
      waitForExpectations(timeout: 10) { er in
        XCTAssertNil(er)
      }
    }
    
    let entries = try! entriesFromFile()
    let entriesToQueue = Array(Set(entries.prefix(5)))
    
    do {
      let exp = expectation(description: "enqueue")
      
      user.enqueue(entries: entriesToQueue) { error in
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertNil(error)
        exp.fulfill()
      }
      
      waitForExpectations(timeout: 10) { error in
        XCTAssertNil(error)
      }
    }
    
    do {
      let exp = expectation(description: "fetching queue")
      
      var acc = [Entry]()
      
      user.fetchQueue(entriesBlock: { entries, error in
        XCTAssertFalse(Thread.isMainThread)

        guard let er = error as? FeedKitError else {
          return XCTFail("should error")
        }
        
        switch er {
        case .missingEntries(let missing):
          XCTAssertEqual(missing.count, 2)

        default:
          XCTFail("should err expectedly")
        }
        
        acc.append(contentsOf: entries)
      }) { error in
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertNil(error)
        
        // The missing entries, self-healingly, have been removed from the
        // queue by now.
        
        XCTAssertEqual(acc, [], "should remove unavailable entries")
        
        print(acc.map { $0.enclosure?.url })
        
        exp.fulfill()
      }
      
      waitForExpectations(timeout: 10) { er in
        XCTAssertNil(er)
      }
    }
    
  }
  
  func testEnqueueEntry() {
    let entry = try! freshEntry(named: "thetalkshow")
    XCTAssertFalse(user.contains(entry: entry))
    
    let exp = expectation(description: "enqueueing")

    user.enqueue(entries: [entry]) { error in
      XCTAssertFalse(Thread.isMainThread)
      XCTAssertNil(error)
      XCTAssertTrue(self.user.contains(entry: entry))

      self.user.enqueue(entries: [entry]) { error in
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertNil(error, "should not error any longer")
        exp.fulfill()
      }
    }
    
    waitForExpectations(timeout: 10) { er in
      XCTAssertNil(er)
    }
  }
  
  func testDequeingNotEnqueued() {
    let entry = try! freshEntry(named: "thetalkshow")
    XCTAssertFalse(user.contains(entry: entry))
    
    let exp = expectation(description: "dequeueing not enqueued")
    
    user.dequeue(entry: entry) { error in
      XCTAssertFalse(Thread.isMainThread)

      guard let er = error as? QueueError else {
        return XCTFail("should err")
      }
      
      switch er {
      case .notInQueue:
        break
      default:
        XCTFail("should be expected error")
      }
      
      exp.fulfill()
    }
    
    waitForExpectations(timeout: 10) { er in
      XCTAssertNil(er)
    }
  }
  
  func testEnqueueing() {
    let entry = try! freshEntry(named: "thetalkshow")
    XCTAssertFalse(user.contains(entry: entry))
    
    let exp = expectation(description: "enqueueing")

    user.enqueue(entries: [entry]) { error in
      XCTAssertFalse(Thread.isMainThread)
      XCTAssertNil(error)
      XCTAssertTrue(self.user.contains(entry: entry))
      exp.fulfill()
    }
    
    waitForExpectations(timeout: 10) { er in
      XCTAssertNil(er)
    }
  }
  
  func testDequeueing() {
    let entry = try! freshEntry(named: "thetalkshow")
    XCTAssertFalse(user.contains(entry: entry))
    
    let exp = expectation(description: "dequeueing")
    
    user.enqueue(entries: [entry]) { error in
      XCTAssertFalse(Thread.isMainThread)
      XCTAssertNil(error)
      XCTAssertTrue(self.user.contains(entry: entry))

      self.user.dequeue(entry: entry) { error in
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertNil(error)

        exp.fulfill()
      }
    }
    
    waitForExpectations(timeout: 10) { er in
      XCTAssertNil(er)
    }
  }

  func testDequeueingByFeed() {
    let entry = try! freshEntry(named: "thetalkshow")
    XCTAssertFalse(user.contains(entry: entry))

    let exp = expectation(description: "dequeueing")

    user.enqueue(entries: [entry]) { error in
      XCTAssertFalse(Thread.isMainThread)
      XCTAssertNil(error)

      XCTAssertTrue(self.user.contains(entry: entry))

      self.user.dequeue(feed: entry.feed) { error in
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertNil(error)
        exp.fulfill()
      }
    }

    waitForExpectations(timeout: 10) { er in
      XCTAssertNil(er)
    }
  }

  func testContainsEntry() {
    let entry = try! freshEntry(named: "thetalkshow")
    XCTAssertFalse(user.contains(entry: entry))
    
    let exp = expectation(description: "enqueue")
    user.enqueue(entries: [entry]) { error in
      XCTAssertFalse(Thread.isMainThread)
      XCTAssertNil(error)
      XCTAssertTrue(self.user.contains(entry: entry))
      
      self.user.dequeue(entry: entry) { error in
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertNil(error)
        XCTAssertFalse(self.user.contains(entry: entry))
        exp.fulfill()
      }
    }
    
    waitForExpectations(timeout: 10) { er in
      XCTAssertNil(er)
    }
  }
  
  func testNext() {
    XCTAssertNil(user.next())
  }
  
  func testPrevious() {
    XCTAssertNil(user.previous())
  }
  
}
