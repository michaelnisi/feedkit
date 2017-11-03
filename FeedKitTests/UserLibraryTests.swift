//
//  UserLibraryTests.swift
//  FeedKit
//
//  Created by Michael on 9/8/17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import XCTest
@testable import FeedKit

// TODO: Review callbacks and notifications

class UserLibraryTests: XCTestCase {
  
  fileprivate var user: UserLibrary!
  fileprivate var cache: UserCache!
  
  override func setUp() {
    super.setUp()
    
    let dq = DispatchQueue(label: "ink.codes.feedkit.user")
    
    dq.sync {
      let cache = freshUserCache(self.classForCoder)
      let browser = freshBrowser(self.classForCoder)
      
      let queue = OperationQueue()
      queue.underlyingQueue = dq
      queue.maxConcurrentOperationCount = 1

      let user = UserLibrary(cache: cache, browser: browser, queue: queue)
      
      self.user = user
      self.cache = cache
    }
  }
  
  override func tearDown() {
    user = nil
    super.tearDown()
  }
  
}

// MARK: - Subscribing

extension UserLibraryTests {
  
  func testSubscribe() {
    XCTAssertThrowsError(try user.add(subscriptions: []))
    
    do {
      let exp = self.expectation(description: "subscribing")
      
      let obs = NotificationCenter.default.addObserver(
        forName: .FKSubscriptionsDidChange,
        object: self.user,
        queue: nil) { notification in
        exp.fulfill()
      }
      
      let url = "http://abc.de"
      let subscriptions = [Subscription(url: url)]
      
      try! user.add(subscriptions: subscriptions) { error in
        XCTAssertNil(error)
      }
      self.waitForExpectations(timeout: 10) { er in
        XCTAssertNil(er)
        NotificationCenter.default.removeObserver(obs)
      }
    }
  }
  
  /// Subscribes to default feed and return subscriptions for testing.
  @discardableResult
  private func subscribe(addComplete: @escaping (Error?) -> Void) -> [Subscription] {
    let url = "http://feeds.feedburner.com/Monocle24TheUrbanist"
    let subscriptions = [Subscription(url: url)]
    try! user.add(subscriptions: subscriptions, addComplete: addComplete)
    return subscriptions
  }
  
  func testUnsubscribe() {
    XCTAssertThrowsError(try user.unsubscribe(from: []))
    
    do {
      let exp = self.expectation(description: "subscribing")
      
      let obs = NotificationCenter.default.addObserver(
        forName: .FKSubscriptionsDidChange,
        object: self.user,
        queue: nil) { notification in
        exp.fulfill()
      }
      
      subscribe { error in
        XCTAssertNil(error)
      }
      
      self.waitForExpectations(timeout: 10) { er in
        XCTAssertNil(er)
        NotificationCenter.default.removeObserver(obs)
      }
    }
    
    do {
      let exp = self.expectation(description: "unsubscribing")
      let url = "http://feeds.feedburner.com/Monocle24TheUrbanist"
      
      let obs = NotificationCenter.default.addObserver(
        forName: .FKSubscriptionsDidChange,
        object: self.user,
        queue: nil) { notification in
        XCTAssertFalse(self.user.has(subscription: url))
        exp.fulfill()
      }
      
      var cb: ((Error?) -> Void)? = { error in
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
    do {
      let exp = self.expectation(description: "subscribing")
      
      subscribe { error in
        XCTAssertNil(error)
        exp.fulfill()
      }
      
      self.waitForExpectations(timeout: 10) { er in
        XCTAssertNil(er)
      }
    }
    
    do {
      let url = "http://feeds.feedburner.com/Monocle24TheUrbanist"
      self.measure {
        XCTAssertTrue(user.has(subscription: url))
      }
      
    }
  }
  
  func testFeeds() {
    do {
      let exp = self.expectation(description: "subscribing")
      
      subscribe { error in
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
  
  func testUpdate() {
    do {
      let exp = expectation(description: "update")
      user.update { newData, error in
        XCTAssertNil(error)
        exp.fulfill()
      }
      waitForExpectations(timeout: 10) { er in
        XCTAssertNil(er)
      }
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
      
      user.enqueue(entries: entriesToQueue) { error in
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
          dump(missing)
          
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
      object: self.user,
      queue: nil) { notification in
      exp.fulfill()
    }
    
    user.enqueue(entries: [entry]) { error in
      XCTAssertNil(error)
      XCTAssertTrue(self.user.contains(entry: entry))
      
      self.user.enqueue(entries: [entry]) { error in
        guard let er = error as? QueueError else {
          return XCTFail("should err")
        }
        
        switch er {
        case .alreadyInQueue:
          break
        default:
          XCTFail("should be expected error")
        }
      }
    }
    
    waitForExpectations(timeout: 10) { er in
      XCTAssertNil(er)
      NotificationCenter.default.removeObserver(obs)
    }
  }
  
  func testDequeueEntry() {
    let entry = try! freshEntry(named: "thetalkshow")
    XCTAssertFalse(user.contains(entry: entry))
    
    do {
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
    
    do {
      let exp = expectation(description: "enqueueing")
      
      user.enqueue(entries: [entry]) { error in
        XCTAssertNil(error)
        XCTAssertTrue(self.user.contains(entry: entry))
        exp.fulfill()
      }
      
      waitForExpectations(timeout: 10) { er in
        XCTAssertNil(er)
      }
    }
    
    do {
      let exp = expectation(description: "dequeueing")
      
      let obs = NotificationCenter.default.addObserver(
        forName: .FKQueueDidChange,
        object: nil,
        queue: nil) { notification in
        DispatchQueue.main.async {
          exp.fulfill()
        }
      }
      
      user.dequeue(entry: entry) { error in
        XCTAssertNil(error)
      }
      
      waitForExpectations(timeout: 10) { er in
        XCTAssertNil(er)
        NotificationCenter.default.removeObserver(obs)
      }
    }
  }
  
  func testContainsEntry() {
    let entry = try! freshEntry(named: "thetalkshow")
    XCTAssertFalse(user.contains(entry: entry))
    
    let exp = expectation(description: "enqueue")
    user.enqueue(entries: [entry]) { error in
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
