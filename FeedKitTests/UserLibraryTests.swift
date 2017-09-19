//
//  UserLibraryTests.swift
//  FeedKit
//
//  Created by Michael on 9/8/17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import XCTest
@testable import FeedKit

fileprivate class Site {
  fileprivate var subscriptions = [Subscription]()
}

extension Site: SubscribeDelegate {
  func queue(_ queue: Subscribing, added: Subscription) {
    subscriptions.append(added)
  }
  
  func queue(_ queue: Subscribing, removed: Subscription) {
    guard let index = subscriptions.index(of: removed) else {
      fatalError("unexpected subscription")
    }
    subscriptions.remove(at: index)
  }
}

extension Site: QueueDelegate {
  func queue(_ queue: Queueing, added: Entry) {
    dump(added)
  }
  
  func queue(_ queue: Queueing, removedGUID: String) {
    dump(removedGUID)
  }
}

class UserLibraryTests: XCTestCase {
  
  fileprivate var user: UserLibrary!
  fileprivate var site: Site!
  
  override func setUp() {
    super.setUp()
    
    let dq = DispatchQueue(label: "ink.codes.feedkit.user")
    
    dq.sync {
      let cache = freshUserCache(self.classForCoder)
      let browser = freshBrowser(self.classForCoder)
      
      let queue = OperationQueue()
      queue.underlyingQueue = dq
      queue.maxConcurrentOperationCount = 1
      
      let site = Site()
      
      let user = UserLibrary(cache: cache, browser: browser, queue: queue)
      user.subscribeDelegate = site
      user.queueDelegate = site
      
      self.user = user
      self.site = site
    }
  }
  
  override func tearDown() {
    site = nil
    user = nil
    super.tearDown()
  }
  
}

// MARK: - Subscribing

// TODO: Check that notifications are being sent

extension UserLibraryTests {
  
  func testSubscribe() {
    try! user.subscribe(to: [])
    
    do {
      try! user.subscribe(to: ["http://abc.de"])
      
      let wanted = [Subscription(url: "http://abc.de")]
      XCTAssertEqual(site.subscriptions, wanted)
    }
  }
  
  func testUnsubscribe() {
    try! user.unsubscribe(from: [])
    
    do {
      try! user.subscribe(to: ["http://abc.de"])
      try! user.unsubscribe(from: ["http://abc.de"])
      
      XCTAssertEqual(site.subscriptions, [])
    }
  }
  
  func testHasSubscription() {
    try! user.subscribe(to: ["http://abc.de"])
    
    let exp = self.expectation(description: "has")
    
    user.has(subscription: 123) { yes, error in
      guard error == nil else {
        return XCTFail("should not error: \(error!)")
      }
      XCTAssertFalse(yes)
      exp.fulfill()
    }
    
    self.waitForExpectations(timeout: 10) { er in
      XCTAssertNil(er)
    }
  }
  
  func testFeeds() {
    let url = "http://feeds.feedburner.com/Monocle24TheUrbanist"
    
    try! user.subscribe(to: [url])
    
    let exp = self.expectation(description: "feeds")
    exp.expectedFulfillmentCount = 12
    exp.assertForOverFulfill = true
    
    user.feeds(feedsBlock: { error, feeds in
      let found = feeds.first!.url
      let wanted = url
      XCTAssertEqual(found, wanted)
      exp.fulfill()
    }) { error in
      guard error == nil else {
        return XCTFail("should not error: \(error!)")
      }
      exp.fulfill()
    }
    
    for _ in 0..<10 {
      user.feeds(feedsBlock: { error, feeds in
        XCTFail()
      }, feedsCompletionBlock: { error in
        XCTAssertEqual(error as? FeedKitError, FeedKitError.cancelledByUser)
        exp.fulfill()
      }).cancel()
    }
    
    self.waitForExpectations(timeout: 10) { er in
      XCTAssertNil(er)
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
      let exp = expectation(description: "entries-1")
      
      user.entries(entriesBlock: { error, entries in
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
      let exp = expectation(description: "entries-2")
      
      var acc = [Entry]()
      
      user.entries(entriesBlock: { error, entries in
        guard let er = error as? FeedKitError else {
          return XCTFail("should error")
        }
        
        switch er {
        case .missingEntries(let missing):
          func guids(lhs: EntryLocator, rhs: EntryLocator) -> Bool  {
            let a = lhs.guid
            let b = rhs.guid
            return Int(a!)! < Int(b!)!
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
        
        
        
        // Receiving five missing entries error here, while still getting the
        // entries, because these are not the fetched ones, but those stored
        // in the queue. This means we are queueing invalid entries.
        
        acc.append(contentsOf: entries)
      }) { error in
        XCTAssertNil(error)
        XCTAssertEqual(acc, entriesToQueue)
        
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
    
    let exp = expectation(description: "enqueue")
    
    user.enqueue(entries: [entry]) { error in
      XCTAssertNil(error)
      XCTAssertTrue(self.user.contains(entry: entry))
      
      self.user.enqueue(entries: [entry]) { error in
        guard let er = error as? QueueError else {
          return XCTFail("should err")
        }
        
        switch er {
        case .alreadyInQueue(let guid):
          XCTAssertEqual(guid, entry.guid.hashValue)
        default:
          XCTFail("should be expected error")
        }
        
        exp.fulfill()
      }
    }
    
    waitForExpectations(timeout: 10) { er in
      XCTAssertNil(er)
    }
  }
  
  func testDequeueEntry() {
    let entry = try! freshEntry(named: "thetalkshow")
    XCTAssertFalse(user.contains(entry: entry))
    
    let exp = expectation(description: "dequeue")
    
    user.dequeue(entry: entry) { error in
      guard let er = error as? QueueError else {
        return XCTFail("should err")
      }
      
      switch er {
      case .notInQueue(let guid):
        XCTAssertEqual(guid, entry.guid.hashValue)
      default:
        XCTFail("should be expected error")
      }
      
      exp.fulfill()
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
