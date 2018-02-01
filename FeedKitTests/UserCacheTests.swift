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
  
  func testTrim() {
    do {
      try! cache.trim()
      XCTAssert(try! cache.queued().isEmpty)
    }
    
    do {
      let url = "http://abc.de"
      let locators = [
        EntryLocator(url: url, since: Date(), guid: "abc"),
        EntryLocator(url: url, since: Date.distantPast, guid: "def")
      ]
      
      try! cache.add(entries: locators)
      
      let newest = try! cache.newest()
      XCTAssertEqual(newest.count, 1)
      
      let found = newest.first
      let wanted = locators.first
      XCTAssertEqual(found, wanted, "should be newest")
    }
    
    do {
      let url = "http://abc.de"
      let locators = [
        EntryLocator(url: url, since: Date(), guid: "abc"),
        EntryLocator(url: url, since: Date.distantPast, guid: "def")
      ]
      
      try! cache.add(entries: locators)
      try! cache.trim()
      
      let queued = try! cache.queued()
      XCTAssertEqual(queued.count, 1)
      
      guard case Queued.temporary(let found, _) = queued.first! else {
        return XCTFail("should enqueue entry")
      }
      let wanted = locators.first
      XCTAssertEqual(found, wanted, "should be newest")
    }
    
    do {
      let url = "http://abc.de"
      let locators = [
        EntryLocator(url: url, since: Date(), guid: "abc"),
        EntryLocator(url: url, since: Date.distantPast, guid: "def")
      ]
      
      try! cache.add(entries: locators, belonging: .user)
      try! cache.trim()
      
      let queued = try! cache.queued()
      XCTAssertEqual(queued.count, 2)
      
      let found: [EntryLocator] = queued.map { $0.entryLocator }
      let wanted = locators
      XCTAssertEqual(found, wanted, "should keep all")
    }
    
    do {
      let url = "http://abc.de"
      // Must be older to be kept, behaviour for equal dates is undefined.
      let older = Date().addingTimeInterval(-1)
      let locators = [
        EntryLocator(url: url, since: older, guid: "abc"),
        EntryLocator(url: url, since: Date.distantPast, guid: "def")
      ]
      
      try! cache.add(entries: locators, belonging: .user)
      let more = [EntryLocator(url: url, since: Date(), guid: "ghi"),]
      try! cache.add(entries: more)
      try! cache.trim()
      
      let queued = try! cache.queued()
      XCTAssertEqual(queued.count, 3)
      XCTAssert(queued.contains {
        guard case .pinned = $0 else { return false }
        return true
      })
      
      let found: [EntryLocator] = queued.map { $0.entryLocator }
      let wanted = locators + more
      XCTAssertEqual(found, wanted, "should keep all")
    }
    
  }

  func testNewest() {
    let urls = ["http://abc.de", "http://fgh.ijk"]
    let now = Date()
    let locators = urls.reduce([EntryLocator]()) { acc, url in
      var tmp = acc
      for i in 0...4 {
        let since = now.addingTimeInterval(TimeInterval(-i))
        let guid = "\(url)/\(i)"
        let loc = EntryLocator(url: url, since: since, guid: guid)
        tmp.append(loc)
      }
      return tmp
    }
    
    assert(locators.count == 10)
  
    try! cache.add(entries: locators)
  
    do {
      let found = try! cache.newest()
      let wanted = [locators[0], locators[5]]
      XCTAssertEqual(found, wanted)
    }
    
    do {
      try! cache.removeQueued()
      let found = try! cache.stalePreviousGUIDs()
      let wanted = [
        "http://abc.de/1",
        "http://abc.de/2",
        "http://abc.de/3",
        "http://abc.de/4",
        "http://fgh.ijk/1",
        "http://fgh.ijk/2",
        "http://fgh.ijk/3",
        "http://fgh.ijk/4"
      ]
      XCTAssertEqual(found, wanted, "should exclude latest of each")
    }
    
    do {
      try! cache.removeStalePrevious()
      let prev = try! cache.previous()
      XCTAssertEqual(prev.count, 2)
      let found: [EntryLocator] = prev.map { $0.entryLocator }
      XCTAssertEqual(found.count, 2)
      let wanted = try! cache.newest()
      XCTAssertEqual(found, wanted)
    }
  }
  
  func testAddEntries() {
    do {
      let locators = [EntryLocator(url: "http://abc.de")]
      let wanted = "missing guid"
      XCTAssertThrowsError(try cache.add(entries: locators), wanted) {
        error in
        switch error {
        case FeedKitError.invalidEntryLocator(let reason):
          XCTAssertEqual(reason, wanted)
        default:
          XCTFail()
        }
      }
    }
    
    try! cache.add(entries: locators)

    do {
      let wanted = locators.map { Queued.temporary($0, Date()) }
      let found = try! cache.queued()
      XCTAssertEqual(found, wanted)
      let guid = locators.first?.guid
      XCTAssertTrue(try! cache.isQueued(guid!))
    }
    
    do {
      let wanted = locators.map { Queued.temporary($0, Date()) }
      let found = try! cache.locallyQueued()
      XCTAssertEqual(found, wanted)
    }
    
    do {
      let all = try! cache.all()
      let wanted = locators.map { Queued.temporary($0, Date()) }
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
      let wanted = locators.map { Queued.temporary($0, Date()) }
      let found = try! cache.queued()
      XCTAssertEqual(found, wanted)
      let guid = locators.first?.guid
      XCTAssertTrue(try! cache.isQueued(guid!))
    }
    
    do {
      try! cache.removeQueued()
      let found = try! cache.queued()
      let wanted = [Queued]()
      XCTAssertEqual(found, wanted)
      let guid = locators.first?.guid
      XCTAssertFalse(try! cache.isQueued(guid!))
    }
    
    do {
      let all = try! cache.all()
      let found = all.map { $0.entryLocator }
      let wanted = locators
      XCTAssertEqual(found, wanted)
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
      let wanted = locators.map { Queued.temporary($0, Date()) }
      let found = try! cache.queued()
      XCTAssertEqual(found, wanted)
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
      let wanted = locators.map { Queued.previous($0, Date()) }
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
  
  func testAddSynced() {
    struct A {
      let rec = RecordMetadata(
        zoneName: "queueZone",
        recordName: UUID().uuidString,
        changeTag: "e"
      )
      let locator = EntryLocator(
        url: "http://abc.de",
        guid: UUID().uuidString
      )
    }

    struct B {
      let rec = RecordMetadata(
        zoneName: "queueZone",
        recordName: UUID().uuidString,
        changeTag: "e"
      )
      let locator = EntryLocator(
        url: "http://abc.de",
        guid: UUID().uuidString
      )
    }

    let a = A()
    let b = B()

    do {
      let temp = Queued.temporary(a.locator, Date())
      let synced = [Synced.queued(temp, a.rec)]
      
      try! cache.add(synced: synced)
      
      XCTAssertTrue(try! cache.isQueued(a.locator.guid!))
    }
    
    do {
      let pinned = Queued.pinned(a.locator, Date())
      let synced = [Synced.queued(pinned, a.rec)]
      
      try! cache.add(synced: synced)
      
      XCTAssertTrue(try! cache.isQueued(a.locator.guid!))
    }
    
    do {
      let pinned = Queued.pinned(a.locator, Date())
      let temp = Queued.temporary(b.locator, Date(timeIntervalSinceNow: -1))
      
      let synced = [
        Synced.queued(pinned, a.rec),
        Synced.queued(temp, b.rec)
      ]
      
      try! cache.add(synced: synced)

      XCTAssertTrue(try! cache.isQueued(a.locator.guid!))
      XCTAssertTrue(try! cache.isQueued(b.locator.guid!))
      
      let found = try! cache.queued()
      XCTAssertEqual(found.count, 2)
      
      let wanted: [Queued] = synced.flatMap {
        guard case .queued(let q, _) = $0 else { return nil }
        return q
      }
      XCTAssertEqual(found, wanted)
    }
  }
  
  func testRemoveSynced() {
    let recordNames = [UUID().uuidString]
    try! cache.remove(recordNames: recordNames)
  }
  
  func testLocallyQueued() {
    XCTAssertEqual(try! cache.locallyQueued(), [])
    
    try! cache.add(entries: locators)
   
    let queued = try! cache.locallyQueued()
    
    let found: [EntryLocator] = queued.map { $0.entryLocator }
    let wanted = locators
    XCTAssertEqual(found, wanted)
  }
  
  func testQueuedViaSync() {
    XCTAssertEqual(try! cache.queued(), [])
    
    do {
      let loc = locators.first!
      let uuidString = UUID().uuidString
      let record = RecordMetadata(
        zoneName: "abc", recordName: uuidString, changeTag: "a")
      let ts = Date()
      let queued = Queued.temporary(loc, ts)
      let synced = Synced.queued(queued, record)
      
      try! cache.add(synced: [synced])

      XCTAssertEqual(try! cache.locallyQueued(), [])
      
      let wanted = Queued.temporary(loc, ts)
      XCTAssertEqual(try! cache.queued(), [wanted])
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
      
      XCTAssertFalse(try! cache.isSubscribed(url))
      
      try! cache.add(subscriptions: subscriptions)
      let found = try! cache.subscribed()
      let wanted = subscriptions
      XCTAssertEqual(found, wanted)
      XCTAssertNotNil(found.first?.ts)
      
      XCTAssert(try! cache.isSubscribed(url))
    }
    
    do {
      let url = "http://abc.de"
      let iTunes = ITunesItem(
        iTunesID: 123, img100: "img100", img30: "img30", img60: "img60",
        img600: "img600")
      let s = Subscription(url: url, iTunes: iTunes)
      let subscriptions = [s]
      
      XCTAssertTrue(try! cache.isSubscribed(url))
      
      try! cache.add(subscriptions: subscriptions)
      let found = try! cache.subscribed()
      let wanted = subscriptions
      XCTAssertEqual(found.count, wanted.count)
      XCTAssertEqual(found, wanted)
      XCTAssertNotNil(found.first?.ts)
      
      XCTAssertEqual(found.first?.iTunes, wanted.first?.iTunes)
      
      XCTAssert(try! cache.isSubscribed(url))
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
      
      XCTAssert(try! cache.isSubscribed(url))
    }
    
    do {
      let urls = subscriptions.map { $0.url }
      try! cache.remove(urls: urls)
      let found = try! cache.subscribed()
      let wanted = [Subscription]()
      XCTAssertEqual(found, wanted)
      
      XCTAssertFalse(try! cache.isSubscribed(url))
    }
    
  }

}
