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
  
  func testRemoveAll() {
    do {
      try! cache.add(entries: locators)
      let wanted = locators.map { Queued.entry($0, Date()) }
      let found = try! cache.queued()
      XCTAssertEqual(found, wanted)
    }
    
    do {
      try! cache.removeAll()
      let found = try! cache.queued()
      let wanted = [Queued]()
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

// MARK: - UserCacheSyncing

extension UserCacheTests {
  
  fileprivate func freshSynced() -> [Synced] {
    let zoneName = "queueZone"
    let recordName = "E49847D6-6251-48E3-9D7D-B70E8B7392CD"
  
    let record = RecordMetadata(
      zoneName: zoneName, recordName: recordName, changeTag: "e")
    let url = "http://abc.de"
    let guid = "abc"
    let loc = EntryLocator(url: url, guid: guid)
    let s = Synced.entry(loc, Date(), record)
  
    return [s]
  }
  
  func testAddSynced() {
    let synced = freshSynced()
    try! cache.add(synced: synced)
  }
  
  func testRemoveSynced() {
    let recordName = "E49847D6-6251-48E3-9D7D-B70E8B7392CD"
    let recordNames = [recordName]
    try! cache.remove(recordNames: recordNames)
  }
  
  func testLocallyQueued() {
    XCTAssertEqual(try! cache.locallyQueued(), [])
    
    try! cache.add(entries: locators)
   
    let queued = try! cache.locallyQueued()
    
    let found: [EntryLocator] = queued.flatMap {
      switch $0 {
      case .entry(let loc, _):
        return loc
      }
    }
    let wanted = locators
    XCTAssertEqual(found, wanted)
  }
  
  func testLocallySubscribed() {
    let s = Subscription(url: "http:/abc.de")
    let subscriptions = [s]
    try! cache.add(subscriptions: subscriptions)
    
    let found = try! cache.locallySubscribed()
    let wanted = subscriptions
    XCTAssertEqual(found, wanted)
  }
  
  func testZombieRecords() {
    XCTAssert(try! cache.zombieRecords().isEmpty)
  }
  
}

// MARK: - SubscriptionCaching

extension UserCacheTests {
  
  func testAddSubscriptions() {
    try! cache.add(subscriptions: [])
    
    let url = "http:/abc.de"
    let s = Subscription(url: url)
    let subscriptions = [s]
    
    XCTAssertFalse(try! cache.has(url))
    
    do {
      try! cache.add(subscriptions: subscriptions)
      let found = try! cache.subscribed()
      let wanted = subscriptions
      XCTAssertEqual(found, wanted)
      XCTAssertNotNil(found.first?.ts)
      
      XCTAssert(try! cache.has(url))
    }
  }
  
  func testRemoveSubscriptions() {
    try! cache.remove(urls: [])
    
    let url = "http:/abc.de"
    let s = Subscription(url: url)
    let subscriptions = [s]
    
    do {
      try! cache.add(subscriptions: subscriptions)
      let found = try! cache.subscribed()
      let wanted = subscriptions
      XCTAssertEqual(found, wanted)
      
      XCTAssert(try! cache.has(url))
    }
    
    do {
      let urls = subscriptions.map { $0.url }
      try! cache.remove(urls: urls)
      let found = try! cache.subscribed()
      let wanted = [Subscription]()
      XCTAssertEqual(found, wanted)
      
      XCTAssertFalse(try! cache.has(url))
    }
    
  }

}
