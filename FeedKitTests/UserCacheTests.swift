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
    cache = Common.makeUserCache()
    if let url = cache.url {
      XCTAssert(FileManager.default.fileExists(atPath: url.path))
    }
  }
  
  override func tearDown() {
    try! Common.destroyCache(cache)
    super.tearDown()
  }
  
  lazy var someLocators: [EntryLocator] = {
    let now = TimeInterval(Int(Date().timeIntervalSince1970)) // rounded
    let since = Date(timeIntervalSince1970: now)
    let locators = [
      EntryLocator(url: "https://abc.de", since: since, guid: "123")
    ]
    return locators
  }()
  
  lazy var someQueued = someLocators.map { Queued(entry: $0) }
  
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

      try! cache.add(queued: locators.map { Queued(entry: $0) })
      
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
      
      try! cache.add(queued: locators.map { Queued(entry: $0) })
      try! cache.trim()
      
      let queued = try! cache.queued()
      XCTAssertEqual(queued.count, 1)
      
      guard case Queued.temporary(let found, _, _) = queued.first! else {
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
      
      try! cache.add(queued: locators.map { Queued.pinned($0, Date(), nil) })
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
      
      try! cache.add(queued: locators.map { Queued.pinned($0, Date(), nil) })
      let more = [EntryLocator(url: url, since: Date(), guid: "ghi"),]
      try! cache.add(queued: more.map { Queued(entry: $0) })
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
        let host = URL(string: url)!.host!
        let guid = "\(host)#\(i)"
        let loc = EntryLocator(url: url, since: since, guid: guid)
        tmp.append(loc)
      }
      return tmp
    }
    
    assert(locators.count == 10)
  
    try! cache.add(queued: locators.map { Queued(entry: $0) })
  
    do {
      let found = try! cache.newest()
      let wanted = [locators[0], locators[5]]
      XCTAssertEqual(found, wanted)
    }
    
    do {
      try! cache.removeQueued()
      let found = try! cache.stalePreviousGUIDs()
      let wanted = urls.reduce([String]()) { acc, url in
        var tmp = acc
        for i in 1...4 {
          let host = URL(string: url)!.host!
          let guid = "\(host)#\(i)"
          tmp.append(guid)
        }
        return tmp
      }
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
      let queued = locators.map { Queued(entry: $0) }
      XCTAssertThrowsError(try cache.add(queued: queued), wanted) {
        error in
        switch error {
        case FeedKitError.invalidEntryLocator(let reason):
          XCTAssertEqual(reason, wanted)
        default:
          XCTFail()
        }
      }
    }
    
    try! cache.add(queued: someQueued)

    do {
      let wanted = someLocators.map { Queued(entry: $0) }
      let found = try! cache.queued()
      XCTAssertEqual(found, wanted)
      let guid = someLocators.first?.guid
      XCTAssertTrue(try! cache.isQueued(guid!))
    }
    
    do {
      let wanted = someLocators.map { Queued(entry: $0) }
      let found = try! cache.locallyQueued()
      XCTAssertEqual(found, wanted)
    }
    
    do {
      let all = try! cache.all()
      let wanted = someLocators.map { Queued(entry: $0) }
      XCTAssertEqual(all, wanted)
    }
    
    do {
      let latest = try! cache.newest()
      XCTAssertEqual(latest, someLocators)
    }
  }
  
  func testRemoveAll() {
    do {
      let queued = someLocators.map { Queued(entry: $0) }
      try! cache.add(queued: queued)
      let wanted = queued
      let found = try! cache.queued()
      XCTAssertEqual(found, wanted)
      let guid = someLocators.first?.guid
      XCTAssertTrue(try! cache.isQueued(guid!))
    }
    
    do {
      try! cache.removeQueued()
      let found = try! cache.queued()
      let wanted = [Queued]()
      XCTAssertEqual(found, wanted)
      let guid = someLocators.first?.guid
      XCTAssertFalse(try! cache.isQueued(guid!))
    }
    
    do {
      let all = try! cache.all()
      let found = all.map { $0.entryLocator }
      let wanted = someLocators
      XCTAssertEqual(found, wanted)
    }
    
    do {
      let latest = try! cache.newest()
      XCTAssertEqual(latest, someLocators)
      dump(latest)
    }
    
  }

  func testRemoveEntries() {
    do {
      let wanted = someQueued
      try! cache.add(queued: wanted)
      let found = try! cache.queued()
      XCTAssertEqual(found, wanted)
    }
    
    do {
      let guids = someLocators.map { $0.guid! }
      try! cache.removeQueued(guids)
      let found = try! cache.queued()
      XCTAssert(found.isEmpty)
    }
    
    // Entries are rotated between queued and previous.
    
    do {
      let found = try! cache.previous()
      let wanted = someLocators.map { Queued.previous($0, Date()) }
      XCTAssertEqual(found, wanted)
    }
    
    do {
      try! cache.add(queued: someQueued)
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
      let temp = Queued.temporary(a.locator, Date(), nil)
      let synced = [Synced.queued(temp, a.rec)]
      
      try! cache.add(synced: synced)
      
      XCTAssertTrue(try! cache.isQueued(a.locator.guid!))
    }
    
    do {
      let pinned = Queued.pinned(a.locator, Date(), nil)
      let synced = [Synced.queued(pinned, a.rec)]
      
      try! cache.add(synced: synced)
      
      XCTAssertTrue(try! cache.isQueued(a.locator.guid!))
    }
    
    do {
      let pinned = Queued.pinned(a.locator, Date(), nil)
      let temp = Queued.temporary(b.locator, Date(timeIntervalSinceNow: -1), nil)
      
      let synced = [
        Synced.queued(pinned, a.rec),
        Synced.queued(temp, b.rec)
      ]
      
      try! cache.add(synced: synced)

      XCTAssertTrue(try! cache.isQueued(a.locator.guid!))
      XCTAssertTrue(try! cache.isQueued(b.locator.guid!))
      
      let found = try! cache.queued()
      XCTAssertEqual(found.count, 2)
      
      let wanted: [Queued] = synced.compactMap {
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
    
    do {
      try! cache.add(queued: someQueued)
   
      let found = try! cache.locallyQueued()
      let wanted = someQueued
      XCTAssertEqual(found, wanted)
    }
    
    do {
      try! cache.add(queued: someQueued)
    }
  }
  
  func testLocallyDequeued() {
    XCTAssertEqual(try! cache.locallyDequeued(), [])
    
    try! cache.add(queued: someQueued)
    let queued = try! cache.locallyQueued()
    
    try! cache.removeQueued()
    XCTAssert(try! cache.locallyQueued().isEmpty)
    
    let found = try! cache.locallyDequeued()
    let wanted: [Queued] = queued.map {
      switch $0 {
      case .pinned(let loc, let ts, _),
           .temporary(let loc, let ts, _):
        return .previous(loc, ts)
      default:
        fatalError("unexpected case")
      }
    }
    XCTAssertEqual(found, wanted)
  }
  
  func testQueuedViaSync() {
    XCTAssertEqual(try! cache.queued(), [])
    
    do {
      let loc = someLocators.first!
      let uuidString = UUID().uuidString
      let record = RecordMetadata(
        zoneName: "abc", recordName: uuidString, changeTag: "a")
      let ts = Date()
      let queued = Queued.temporary(loc, ts, nil)
      let synced = Synced.queued(queued, record)
      
      try! cache.add(synced: [synced])

      XCTAssertEqual(try! cache.locallyQueued(), [])
      
      let wanted = Queued.temporary(loc, ts, nil)
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
      try! cache.purgeZone(named: "queueZone")
      XCTAssertEqual(try! cache.queued(), [])
      XCTAssertEqual(try! cache.locallyQueued(), [])
      XCTAssertTrue(try! cache.zombieRecords().isEmpty)
      
      try! cache.purgeZone(named: "libraryZone")
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
        url: url,
        iTunesID: 123,
        img100: "img100",
        img30: "img30",
        img60: "img60",
        img600: "img600"
      )
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
