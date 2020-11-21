//
//  UserSQLTests.swift
//  FeedKitTests
//
//  Created by Michael Nisi on 06.02.18.
//  Copyright © 2018 Michael Nisi. All rights reserved.
//

import XCTest
import SnapshotTesting

@testable import FeedKit
@testable import Skull

class UserSQLTests: XCTestCase {
  
  var formatter: UserSQLFormatter!
  
  override func setUp() {
    super.setUp()
    formatter = UserSQLFormatter()
  }
  
  override func tearDown() {
    formatter = nil
    super.tearDown()
  }
  
}

// MARK: - Syncing

extension UserSQLTests {
  
  func testSQLToDeleteRecords() {
    XCTAssertEqual(UserSQLFormatter.SQLToDeleteRecords(with: []),
                   "DELETE FROM record WHERE record_name IN();")
    XCTAssertEqual(UserSQLFormatter.SQLToDeleteRecords(with: ["abc", "def"]),
                   "DELETE FROM record WHERE record_name IN('abc', 'def');")
  }
  
  func testSQLToSelectLocallyQueuedEntries() {
    let wanted = "SELECT * FROM locally_queued_entry_view;"
    XCTAssertEqual(UserSQLFormatter.SQLToSelectLocallyQueuedEntries, wanted)
  }
  
  func testSQLToReplaceSynced() {
    let zoneName = "queueZone"
    let recordName = "E49847D6-6251-48E3-9D7D-B70E8B7392CD"
    let changeTag = "e"
    let record = RecordMetadata(zoneName: zoneName, recordName: recordName, changeTag: changeTag)
    
    do {
      let loc = EntryLocator(url: "http://abc.de")
      let queued = Queued.temporary(loc, Date(), nil)
      let synced = Synced.queued(queued, record)
      
      XCTAssertThrowsError(try formatter.SQLToReplace(synced: synced))
    }
    
    let ts = Date(timeIntervalSince1970: 1465192800) // 2016-06-06 06:00:00
    
    do {
      let loc = EntryLocator(url: "http://abc.de", since: nil, guid: "abc", title: nil)
      let queued = Queued.temporary(loc, ts, nil)
      let synced = Synced.queued(queued, record)
      let found = try! formatter.SQLToReplace(synced: synced)
      
      assertSnapshot(matching: found, as: .dump)
    }
    
    do {
      let url = "http://abc.de"
      let loc = EntryLocator(url: url, since: nil, guid: "abc", title: nil)
      let iTunes = Common.makeITunesItem(url: url)
      let queued = Queued.temporary(loc, ts, iTunes)
      let synced = Synced.queued(queued, record)
      let found = try! formatter.SQLToReplace(synced: synced)
      
      assertSnapshot(matching: found, as: .dump)
    }
    
    do {
      let url = "http://abc.de"
      let loc = EntryLocator(url: url, since: nil, guid: "abc", title: nil)
      let iTunes = Common.makeITunesItem(url: url)
      let queued = Queued.pinned(loc, ts, iTunes)
      let synced = Synced.queued(queued, record)
      let found = try! formatter.SQLToReplace(synced: synced)
      
      assertSnapshot(matching: found, as: .dump)
    }
    
    do {
      let url = "http://abc.de"
      let s = Subscription(url: url, ts: ts, iTunes: nil)
      let synced = Synced.subscription(s, record)
      let found = try! formatter.SQLToReplace(synced: synced)
      
       assertSnapshot(matching: found, as: .dump)
    }
  }
  
  func testSQLToSelectLocallySubscribedFeeds() {
    let wanted = "SELECT * FROM locally_subscribed_feed_view;"
    XCTAssertEqual(UserSQLFormatter.SQLToSelectLocallySubscribedFeeds, wanted)
  }
  
}

// MARK: - Subscribing

extension UserSQLTests {
  
  func testSQLToSelectSubscriptions() {
    let wanted = "SELECT * from subscribed_feed_view;"
    XCTAssertEqual(UserSQLFormatter.SQLToSelectSubscriptions, wanted)
  }
  
  func testSQLToSelectZombieFeedGUIDs() {
    let wanted = "SELECT * from zombie_feed_url_view;"
    XCTAssertEqual(UserSQLFormatter.SQLToSelectZombieFeedURLs, wanted)
  }
  
  func testSQLToReplaceSubscriptions() {
    do {
      let url = "https://abc.de/rss"
      let s = Subscription(url: url)
      let found = formatter.SQLToReplace(subscription: s)
      
      assertSnapshot(matching: found, as: .dump)
    }
    
    do {
      let url = "https://abc.de/rss"
      let iTunes = Common.makeITunesItem(url: url)
      let s = Subscription(url: url, ts: nil, iTunes: iTunes)
      let found = formatter.SQLToReplace(subscription: s)
      
       assertSnapshot(matching: found, as: .dump)
    }
    
    do {
      let url = "https://abc.de/rss"
      let iTunes = Common.makeITunesItem(url: url)
      let s = Subscription(url: url, ts: Date(), iTunes: iTunes)
      let found = formatter.SQLToReplace(subscription: s)
      
       assertSnapshot(matching: found, as: .dump)
    }
  }
  
  func testSQLToDeleteSubscriptions() {
    XCTAssertEqual(
      UserSQLFormatter.SQLToDelete(subscribed: []),
      "DELETE FROM subscribed_feed WHERE feed_url IN();")
    
    let url = "http://abc.de"
    let found = UserSQLFormatter.SQLToDelete(subscribed: [url])
    let wanted = "DELETE FROM subscribed_feed WHERE feed_url IN('\(url)');"
    XCTAssertEqual(found, wanted)
  }
  
}

// MARK: - Queueing

extension UserSQLTests {
  
  func testSQLToUnqueue() {
    XCTAssertEqual(UserSQLFormatter.SQLToUnqueue(guids: []),
                   "DELETE FROM queued_entry WHERE entry_guid IN();")
    
    let guids = ["12three", "45six"]
    let found = UserSQLFormatter.SQLToUnqueue(guids: guids)
    let wanted =
    "DELETE FROM queued_entry WHERE entry_guid IN('12three', '45six');"
    XCTAssertEqual(found, wanted)
  }
  
  func testSQLToSelectAllQueued() {
    XCTAssertEqual(UserSQLFormatter.SQLToSelectAllQueued,
                   "SELECT * FROM queued_entry_view ORDER BY ts DESC;")
  }
  
  func testSQLToSelectAllPrevious() {
    XCTAssertEqual(UserSQLFormatter.SQLToSelectAllPrevious,
                   "SELECT * FROM prev_entry_view ORDER BY ts DESC;")
  }
  
  func testSQLToQueueEntry() {
    do {
      let locator = EntryLocator(url: "http://abc.de")
      let q = Queued(entry: locator)
      XCTAssertThrowsError(try formatter.SQLToReplace(queued: q))
    }
    
    let guid = "12three"
    let url = "abc.de"
    let since = Date(timeIntervalSince1970: 1465192800) // 2016-06-06 06:00:00
    let locator = EntryLocator(url: url, since: since, guid: guid)
    
    do {
      let q = Queued(entry: locator)
      let found = try! formatter.SQLToReplace(queued: q)
      
       assertSnapshot(matching: found, as: .dump)
    }
    
    do {
      let q = Queued.pinned(locator, Date(), nil)
      let found = try! formatter.SQLToReplace(queued: q)
      
       assertSnapshot(matching: found, as: .dump)
    }
    
    do {
      let q = Queued.previous(locator, Date())
      let found = try! formatter.SQLToReplace(queued: q)
      
       assertSnapshot(matching: found, as: .dump)
    }
  }
  
  func testQueuedFromRow() {
    do {
      let url = "abc.de"
      let guid = "123"
      let now = formatter.now()
      
      let row = [
        "entry_guid": guid,
        "feed_url": url,
        "since": "2016-06-06 06:00:00",
        "ts": now
      ]
      
      let found = formatter.queued(from: row)
      
      let since = Date(timeIntervalSince1970: 1465192800)
      let locator = EntryLocator(url: url, since: since, guid: guid)
      let ts = formatter.date(from: now)
      let wanted = Queued.temporary(locator, ts!, nil)
      
      XCTAssertEqual(found, wanted)
    }
    
    do {
      let url = "http://abc.de"
      let guid = "123"
      let now = formatter.now()
      
      let row = [
        "entry_guid": guid,
        "feed_url": url,
        "since": "2016-06-06 06:00:00",
        "ts": now,
        "pinned_ts": now
      ]
      
      let found = formatter.queued(from: row)
      
      let since = Date(timeIntervalSince1970: 1465192800)
      let locator = EntryLocator(url: url, since: since, guid: guid)
      let ts = formatter.date(from: now)
      let wanted = Queued.pinned(locator, ts!, nil)
      
      XCTAssertEqual(found, wanted)
    }
  }
  
}
