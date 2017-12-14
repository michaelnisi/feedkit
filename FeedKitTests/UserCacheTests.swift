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

  func testNewest() {
    let urls = ["http://abc.de", "http://fgh.ijk"]
    let locators = urls.reduce([EntryLocator]()) { acc, url in
      var tmp = acc
      for index in 1...5 {
        if url == "http://abc.de" && index == 5 {
          continue
        }
        let since = Date(timeIntervalSince1970: Double(index) * 10)
        let guid = "\(url)/\(index)"
        let loc = EntryLocator(url: url, since: since, guid: guid)
        tmp.append(loc)
      }
      return tmp
    }
  
    try! cache.add(entries: locators)
  
    do {
      let found = try! cache.newest()
      let a = urls.last!
      let b = urls.first!
      let since = Date(timeIntervalSince1970: 50)
      
      let wanted = [
        EntryLocator(url: a, since: since, guid: "\(a)/5"),
        EntryLocator(url: b, since: since, guid: "\(b)/4")
      ]
      XCTAssertEqual(found, wanted)
    }
    
    do {
      try! cache.removeQueued()
      let found = try! cache.stalePreviousGUIDs()
      let wanted = [
        "http://abc.de/1",
        "http://abc.de/2",
        "http://abc.de/3",
        "http://fgh.ijk/1",
        "http://fgh.ijk/2",
        "http://fgh.ijk/3",
        "http://fgh.ijk/4"
      ]
      XCTAssertEqual(wanted, found, "should exclude latest of each")
    }
    
    do {
      try! cache.removeStalePrevious()
      let prev = try! cache.previous()
      XCTAssertEqual(prev.count, 2)
      let found: [EntryLocator] = prev.flatMap {
        if case .entry(let loc, _) = $0 {
          return loc
        }
        return nil
      }
      XCTAssertEqual(found.count, 2)
      let wanted = Array(try! cache.newest().reversed())
      XCTAssertEqual(found, wanted)
    }
  }
  
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
    
    do {
      let all = try! cache.all()
      let wanted = locators.map { Queued.entry($0, Date()) }
      XCTAssertEqual(all, wanted)
    }
    
    do {
      let latest = try! cache.newest()
      XCTAssertEqual(latest, locators)
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
      try! cache.removeQueued()
      let found = try! cache.queued()
      let wanted = [Queued]()
      XCTAssertEqual(found, wanted)
    }
    
    do {
      let all = try! cache.all()
      let wanted = locators.map { Queued.entry($0, Date()) }
      XCTAssertEqual(all, wanted)
    }
    
    do {
      let latest = try! cache.newest()
      XCTAssertEqual(latest, locators)
      dump(latest)
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
      let guids = locators.map { $0.guid! }
      try! cache.removeQueued(guids)
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
    let guid = "abc"
    XCTAssertTrue(try! cache.contains(guid))
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
  
  func testQueuedViaSync() {
    XCTAssertEqual(try! cache.queued(), [])
    
    do {
      let locator = locators.first!
      let uuidString = UUID().uuidString
      let record = RecordMetadata(
        zoneName: "abc", recordName: uuidString, changeTag: "a")
      let ts = Date()
      let synced = Synced.entry(locator, ts, record)
      
      try! cache.add(synced: [synced])

      XCTAssertEqual(try! cache.locallyQueued(), [])
      
      let queued = Queued.entry(locator, ts)
      XCTAssertEqual(try! cache.queued(), [queued])
    }
  }
  
  func testLocallySubscribed() {
    XCTAssertEqual(try! cache.locallySubscribed(), [])
    
    let s = Subscription(url: "http://abc.de")
    let subscriptions = [s]
    
    do {
      try! cache.add(subscriptions: subscriptions)
      
      let found = try! cache.locallySubscribed()
      let wanted = subscriptions
      XCTAssertEqual(found, wanted)
    }
    
    do {
      let uuidString = UUID().uuidString
      let record = RecordMetadata(
        zoneName: "abc", recordName: uuidString, changeTag: "a")
      let synced = Synced.subscription(s, record)
      
      try! cache.add(synced: [synced])
      
      XCTAssertEqual(try! cache.locallySubscribed(), [])
    }
  }
  
  func testSubscribedViaSync() {
    XCTAssertEqual(try! cache.subscribed(), [])
    
    do {
      let subscription = Subscription(url: "http://abc.de")
      let uuidString = UUID().uuidString
      let record = RecordMetadata(
        zoneName: "abc", recordName: uuidString, changeTag: "a")
      let synced = Synced.subscription(subscription, record)
      
      try! cache.add(synced: [synced])
      
      XCTAssertEqual(try! cache.locallySubscribed(), [])
      XCTAssertEqual(try! cache.subscribed(), [subscription])
    }
  }
  
  func testCleaningUp() {
    let recordName = UUID().uuidString
    let record = RecordMetadata(
      zoneName: "abc", recordName: recordName, changeTag: "a")
    
    do {
      let subscription = Subscription(url: "http://abc.de")
      let synced = Synced.subscription(subscription, record)
      try! cache.add(synced: [synced])
      XCTAssertEqual(try! cache.locallySubscribed(), [])
      XCTAssertEqual(try! cache.subscribed(), [subscription])
    }
    
    do {
      try! cache.remove(urls: ["http://abc.de"])
      let found = try! cache.zombieRecords().first!
      let wanted = (record.zoneName, record.recordName)
      XCTAssertEqual(found.0, wanted.0)
      XCTAssertEqual(found.1, wanted.1)
    }
    
    do {
      try! cache.deleteZombies()
      XCTAssertTrue(try! cache.zombieRecords().isEmpty)
    }
    
    do {
      try! cache.removeQueue()
      XCTAssertEqual(try! cache.queued(), [])
      XCTAssertEqual(try! cache.locallyQueued(), [])
      XCTAssertTrue(try! cache.zombieRecords().isEmpty)
      
      try! cache.removeLibrary()
      XCTAssertEqual(try! cache.subscribed(), [])
      XCTAssertEqual(try! cache.locallySubscribed(), [])
      XCTAssertTrue(try! cache.zombieRecords().isEmpty)
    }
  }
  
}

// MARK: - SubscriptionCaching

extension UserCacheTests {
  
  func testAddSubscriptions() {
    try! cache.add(subscriptions: [])

    do {
      let url = "http://abc.de"
      let s = Subscription(url: url)
      let subscriptions = [s]
      
      XCTAssertFalse(try! cache.has(url))
      
      try! cache.add(subscriptions: subscriptions)
      let found = try! cache.subscribed()
      let wanted = subscriptions
      XCTAssertEqual(found, wanted)
      XCTAssertNotNil(found.first?.ts)
      
      XCTAssert(try! cache.has(url))
    }
    
    do {
      let url = "http://abc.de"
      let iTunes = ITunesItem(
        iTunesID: 123, img100: "img100", img30: "img30", img60: "img60",
        img600: "img600")
      let s = Subscription(url: url, iTunes: iTunes)
      let subscriptions = [s]
      
      XCTAssertTrue(try! cache.has(url))
      
      try! cache.add(subscriptions: subscriptions)
      let found = try! cache.subscribed()
      let wanted = subscriptions
      XCTAssertEqual(found.count, wanted.count)
      XCTAssertEqual(found, wanted)
      XCTAssertNotNil(found.first?.ts)
      
      XCTAssertEqual(found.first?.iTunes, wanted.first?.iTunes)
      
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
