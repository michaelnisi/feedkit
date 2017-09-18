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
  
  func testEntries() {
    let exp = expectation(description: "entries")
    
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
  
  func testEnqueueEntry() {
    let entry = try! freshEntry(named: "thetalkshow")
    XCTAssertFalse(user.contains(entry: entry))
    
    let exp = expectation(description: "enqueue")
    
    user.enqueue(entry: entry) { error in
      XCTAssertNil(error)
      XCTAssertTrue(self.user.contains(entry: entry))
      
      self.user.enqueue(entry: entry) { error in
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
    user.enqueue(entry: entry) { error in
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
