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
      
      try! user.add(subscriptions: []) { error in
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertNil(error)
        exp.fulfill()
      }
    }
    
    do {
      let exp = self.expectation(description: "subscribing")
      
      let obs = NotificationCenter.default.addObserver(
        forName: .FKSubscriptionsDidChange,
        object: nil,
        queue: OperationQueue.main) { notification in
        assert(Thread.isMainThread)
        exp.fulfill()
      }
      
      let url = "http://abc.de"
      let subscriptions = [Subscription(url: url)]
      
      try! user.add(subscriptions: subscriptions)
      
      self.waitForExpectations(timeout: 10) { er in
        XCTAssertNil(er)
        NotificationCenter.default.removeObserver(obs)
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
    try! user.add(subscriptions: subscriptions, addComplete: addComplete)
    return subscriptions
  }
  
  func testUnsubscribe() {
    let url = "http://abc.de"
    
    do {
      let exp = self.expectation(description: "subscribing")
      
      let obs = NotificationCenter.default.addObserver(
        forName: .FKSubscriptionsDidChange,
        object: self.user,
        queue: OperationQueue.main) { notification in
        assert(Thread.isMainThread)
        exp.fulfill()
      }
      
      subscribe(url) { error in
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertNil(error)
      }
      
      self.waitForExpectations(timeout: 10) { er in
        XCTAssertNil(er)
        NotificationCenter.default.removeObserver(obs)
      }
    }
    
    do {
      let exp = self.expectation(description: "unsubscribing empty list")
      
      try! user.unsubscribe(from: []) { error in
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertNil(error)
        exp.fulfill()
      }
    }
    
    do {
      let exp = self.expectation(description: "unsubscribing")

      let obs = NotificationCenter.default.addObserver(
        forName: .FKSubscriptionsDidChange,
        object: self.user,
        queue: OperationQueue.main) { notification in
        XCTAssertFalse(self.user.has(subscription: url))
        assert(Thread.isMainThread)
        exp.fulfill()
      }
      
      var cb: ((Error?) -> Void)? = { error in
        XCTAssertFalse(Thread.isMainThread)
        XCTAssertNil(error)
      }
      
      try! user.unsubscribe(from: [url], unsubscribeComplete: cb)
      cb = nil // stinker
      
      self.waitForExpectations(timeout: 10) { er in
        XCTAssertNil(er)
        NotificationCenter.default.removeObserver(obs)
      }
    }
  }
  
  func testHasSubscription() {
    let url = "http://feeds.feedburner.com/Monocle24TheUrbanist"
    
    do {
      let exp = self.expectation(description: "subscribing")
      
      subscribe(url) { error in
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
        let found = feeds.first!.url
        let wanted = "http://feeds.feedburner.com/Monocle24TheUrbanist"
        XCTAssertEqual(found, wanted)
      }) { error in
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
}

// MARK: - Queueing

extension UserLibraryTests {
  
  func testMissingEntries() {
    do {
      let exp = expectation(description: "initially fetching queue")
      
      user.fetchQueue(entriesBlock: { entries, error in
        XCTFail("should not call block")
      }) { error in
        XCTAssertNil(error)
        exp.fulfill()
      }
      
      waitForExpectations(timeout: 10) { er in
        XCTAssertNil(er)
      }
    }
    
    let entries = try! entriesFromFile()
    let entriesToQueue = Array(entries.prefix(5))
    
    do {
      let exp = expectation(description: "enqueue")
      
      try! user.enqueue(entries: entriesToQueue) { error in
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
        guard let er = error as? FeedKitError else {
          return XCTFail("should error")
        }
        
        switch er {
        case .missingEntries(let missing):
          func guids(lhs: EntryLocator, rhs: EntryLocator) -> Bool  {
            return lhs.guid!.hashValue < rhs.guid!.hashValue
          }
          
          let found = missing.sorted(by: guids)
          let wanted = entriesToQueue.map { EntryLocator(entry: $0) }.sorted(by: guids)
          
          XCTAssertEqual(found.count, wanted.count)
         
          found.enumerated().forEach { offset, a in
            let b = wanted[offset]
            XCTAssertEqual(a, b)
          }
          
           XCTAssertEqual(found, wanted)
        default:
          XCTFail("should err expectedly")
        }
        
        acc.append(contentsOf: entries)
      }) { error in
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
    
    let obs = NotificationCenter.default.addObserver(
      forName: .FKQueueDidChange,
      object: nil,
      queue: OperationQueue.main) { notification in
      assert(Thread.isMainThread)
      exp.fulfill()
    }
    
    try! user.enqueue(entries: [entry]) { error in
      XCTAssertNil(error)
      XCTAssertTrue(self.user.contains(entry: entry))
      
      try! self.user.enqueue(entries: [entry]) { error in
        guard case .alreadyInQueue = error as! QueueError else {
          return XCTFail("should throw expectedly")
        }
      }
    }
    
    waitForExpectations(timeout: 10) { er in
      XCTAssertNil(er)
      NotificationCenter.default.removeObserver(obs)
    }
  }
  
  func testDequeingNotEnqueued() {
    let entry = try! freshEntry(named: "thetalkshow")
    XCTAssertFalse(user.contains(entry: entry))
    
    let exp = expectation(description: "dequeueing not enqueued")
    
    user.dequeue(entry: entry) { error in
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
    
    let obs = NotificationCenter.default.addObserver(
      forName: .FKQueueDidChange,
      object: nil,
      queue: OperationQueue.main) { notification in
        assert(Thread.isMainThread)
        exp.fulfill()
    }
    
    try! user.enqueue(entries: [entry]) { error in
      XCTAssertNil(error)
      XCTAssertTrue(self.user.contains(entry: entry))
    }
    
    waitForExpectations(timeout: 10) { er in
      XCTAssertNil(er)
      NotificationCenter.default.removeObserver(obs)
    }
  }
  
  func testDequeueing() {
    let entry = try! freshEntry(named: "thetalkshow")
    XCTAssertFalse(user.contains(entry: entry))
    
    let exp = expectation(description: "dequeueing")
    var obs: Any?
    
    try! user.enqueue(entries: [entry]) { error in
      XCTAssertNil(error)
      XCTAssertTrue(self.user.contains(entry: entry))

      self.user.dequeue(entry: entry) { error in
        XCTAssertNil(error)
        
        obs = NotificationCenter.default.addObserver(
          forName: .FKQueueDidChange,
          object: nil,
          queue: OperationQueue.main) { notification in
            assert(Thread.isMainThread)
            exp.fulfill()
        }
      }
    }
    
    waitForExpectations(timeout: 10) { er in
      XCTAssertNil(er)
      NotificationCenter.default.removeObserver(obs!)
    }
  }
  
  func testContainsEntry() {
    let entry = try! freshEntry(named: "thetalkshow")
    XCTAssertFalse(user.contains(entry: entry))
    
    let exp = expectation(description: "enqueue")
    try! user.enqueue(entries: [entry]) { error in
      XCTAssertNil(error)
      XCTAssertTrue(self.user.contains(entry: entry))
      
      self.user.dequeue(entry: entry) { error in
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
