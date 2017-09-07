//
//  UserCacheTests.swift
//  FeedKit
//
//  Created by Michael Nisi on 01.07.17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import XCTest
@testable import FeedKit

final class UserCacheTests: XCTestCase {
  
  var cache: UserCache!
  
  override func setUp() {
    super.setUp()
    cache = freshUserCache(self.classForCoder)
    if let url = cache.url {
      XCTAssert(FileManager.default.fileExists(atPath: url.path))
    }
  }
  
  override func tearDown() {
    try! destroyCache(cache)
    super.tearDown()
  }
  
  lazy var locators: [EntryLocator] = {
    let now = TimeInterval(Int(Date().timeIntervalSince1970)) // rounded
    let since = Date(timeIntervalSince1970: now)
    let locators = [
      EntryLocator(url: "https://abc.de", since: since, guid: "123")
    ]
    return locators
  }()
  
}

// MARK: - QueueCaching

extension UserCacheTests {
  
  func testAddEntries() {
    try! cache.add(entries: locators)

    do {
      let wanted = locators.map { Queued.entry($0, Date()) }
      let found = try! cache.queued()
      XCTAssertEqual(found, wanted)
    }
    
    do {
      let wanted = locators.map { Queued.entry($0, Date()) }
      let found = try! cache.locallyQueued()
      XCTAssertEqual(found, wanted)
    }
  }
  
  func testRemoveEntries() {
    do {
      try! cache.add(entries: locators)
      let wanted = locators.map { Queued.entry($0, Date()) }
      let found = try! cache.queued()
      XCTAssertEqual(found, wanted)
      
      // Unpacking the timestamp here, because Queued timestamps, Date() in the 
      // map function above, aren‘t compared by Queued: Equatable.
      switch found.first! {
      case .entry(_, let ts):
        XCTAssertNotNil(ts)
      }
    }
    
    do {
      try! cache.remove(guids: ["123"])
      let found = try! cache.queued()
      XCTAssert(found.isEmpty)
    }
    
    // Entries are rotated between queued and previous.
    
    do {
      let found = try! cache.previous()
      let wanted = locators.map { Queued.entry($0, Date()) }
      XCTAssertEqual(found, wanted)
    }
    
    do {
      try! cache.add(entries: locators)
      let found = try! cache.previous()
      XCTAssert(found.isEmpty)
    }
  }

}

// MARK: - SubscriptionCaching

extension UserCacheTests {
  
  func testAddSubscriptions() {
    try! cache.add(subscriptions: [])
    
    let s = Subscription(url: "http:/abc.de")
    let subscriptions = [s]
    
    do {
      try! cache.add(subscriptions: subscriptions)
      let found = try! cache.subscribed()
      let wanted = subscriptions
      XCTAssertEqual(found, wanted)
      
      XCTAssertNotNil(found.first?.ts)
    }
  }
  
  func testRemoveSubscriptions() {
    try! cache.remove(subscriptions: [])
    
    let s = Subscription(url: "http:/abc.de")
    let subscriptions = [s]
    
    do {
      try! cache.add(subscriptions: subscriptions)
      let found = try! cache.subscribed()
      let wanted = subscriptions
      XCTAssertEqual(found, wanted)
    }
    
    do {
      try! cache.remove(subscriptions: subscriptions)
      let found = try! cache.subscribed()
      let wanted = [Subscription]()
      XCTAssertEqual(found, wanted)
    }
    
  }

}

// MARK: - UserCacheSyncing

extension UserCacheTests {

}
