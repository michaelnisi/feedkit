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
    }
  }
  
  override func tearDown() {
    user = nil
    super.tearDown()
  }
  
}

// MARK: - Subscribing

// TODO: Check that notifications are being sent

extension UserLibraryTests {
  
  func testSubscribe() {
    try! user.add(subscriptions: [])
    
    do {
      let url = "http://abc.de"
      let subscriptions = [Subscription(url: url)]
      try! user.add(subscriptions: subscriptions)
    }
  }
  
  func testUnsubscribe() {
    try! user.unsubscribe(from: [])
    
    do {
      let url = "http://abc.de"
      let subscriptions = [Subscription(url: url)]
      try! user.add(subscriptions: subscriptions)
      try! user.unsubscribe(from: [url])
    }
  }
  
  func testHasSubscription() {
    let url = "http://abc.de"
    let subscriptions = [Subscription(url: url)]
    try! user.add(subscriptions: subscriptions)
    
    let exp = self.expectation(description: "has")
    
    user.has(subscription: url) { yes, error in
      guard error == nil else {
        return XCTFail("should not error: \(error!)")
      }
      XCTAssertTrue(yes)
      exp.fulfill()
    }
    
    self.waitForExpectations(timeout: 10) { er in
      XCTAssertNil(er)
    }
  }
  
  func testFeeds() {
    let url = "http://feeds.feedburner.com/Monocle24TheUrbanist"
    let subscriptions = [Subscription(url: url)]
    try! user.add(subscriptions: subscriptions)
    
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
    
    let exp = expectation(description: "enqueue")
    
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
