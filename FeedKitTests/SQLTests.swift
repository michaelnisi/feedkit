//
//  SQLTests.swift
//  FeedKit
//
//  Created by Michael Nisi on 30/10/15.
//  Copyright © 2015 Michael Nisi. All rights reserved.
//

import XCTest

@testable import FeedKit
@testable import Skull

final class SQLTests: XCTestCase {
  var formatter: SQLFormatter!

  override func setUp() {
    super.setUp()
    formatter = SQLFormatter()
  }

  func testSQLStringFromString() {
    let tests = [
      (SQLFormatter.SQLString(from: ""), "''"),
      (SQLFormatter.SQLString(from: "abc'd"), "'abc''d'")
    ]
    
    for (found, wanted) in tests {
      XCTAssertEqual(found, wanted)
    }
  }
  
  func skullColumn(_ name: String, value: Any) -> SkullColumn<Any> {
    return SkullColumn(name: name, value: value)
  }
  
  fileprivate func skullRow(_ keys: [String]) -> SkullRow {
    var row = SkullRow()
    for key in keys {
      let col = skullColumn(key, value: key)
      row[col.name] = col.value
    }
    return row
  }
  
  func testITunesFromRow() {
    let wanted = ITunesItem(
      guid: 123,
      img100: "img100",
      img30: "img30",
      img60: "img60",
      img600: "img600"
    )
    
    do { // feed
      let keys = ["img100", "img30", "img60", "img600"]
      var row = skullRow(keys)
      row["guid"] = 123
      XCTAssertEqual(SQLFormatter.iTunesItem(from: row), wanted)
    }
    
    do { // entry
      let keys = ["img100", "img30", "img60", "img600"]
      var row = skullRow(keys)
      row["feed_guid"] = 123
      XCTAssertEqual(SQLFormatter.iTunesItem(from: row), wanted)
    }
  }
  
  func testFeedFromRow() {
    let keys = [
      "img", "img100", "img30", "img60", "img600", "author", "link", "summary",
      "title", "updated", "url"
    ]
    var row = skullRow(keys)
    
    row["guid"] = 123
    row["uid"] = 0
    row["ts"] = "2016-06-06 06:00:00"
    
    let found = try! formatter.feedFromRow(row)
    
    let iTunes = ITunesItem(
      guid: 123,
      img100: "img100",
      img30: "img30",
      img60: "img60",
      img600: "img600"
    )
    let wanted = Feed(
      author: "author",
      iTunes: iTunes,
      image: "img",
      link: "link",
      originalURL: nil,
      summary: "summary",
      title: "title",
      ts: Date(timeIntervalSince1970: 1465192800),
      uid: 0,
      updated: nil,
      url: "url"
    )
    
    XCTAssertEqual(found, wanted)
    
    XCTAssertEqual(found.author, wanted.author)
    XCTAssertEqual(found.iTunes, wanted.iTunes)
    XCTAssertEqual(found.image, wanted.image)
    XCTAssertEqual(found.link, wanted.link)
    XCTAssertEqual(found.summary, wanted.summary)
    XCTAssertEqual(found.title, wanted.title)
    XCTAssertEqual(found.ts, wanted.ts)
    XCTAssertEqual(found.uid, wanted.uid)
    XCTAssertEqual(found.updated, wanted.updated)
    XCTAssertEqual(found.url, wanted.url)
  }
  
  func testNow() {
    let dateFormat = "yyyy-MM-dd HH:mm:ss"
    let found = formatter.now()
    let length = found.lengthOfBytes(using: String.Encoding.utf8)
    XCTAssertEqual(length, dateFormat.lengthOfBytes(using: String.Encoding.utf8))
  }
  
  func testDateFromString() {
    XCTAssertNil(formatter.date(from: nil))
    XCTAssertNil(formatter.date(from: ""))
    XCTAssertNil(formatter.date(from: "hello"))
    
    let found = formatter.date(from: "2016-06-06 06:00:00")
    let wanted = Date(timeIntervalSince1970: 1465192800)
    XCTAssertEqual(found, wanted)
  }
  
  func testSQLToSelectEntryByGUID() {
    let found = SQLFormatter.SQLToSelectEntryByGUID("abc")
    let wanted = "SELECT * FROM entry_view WHERE guid = 'abc';"
    XCTAssertEqual(found, wanted)
  }

  func testSQLToSelectEntriesByIntervals() {
    let f = formatter.SQLToSelectEntriesByIntervals
    XCTAssertNil(f([]))
    let findings = [
      f([(1, Date(timeIntervalSince1970: 0))]),
      f([(1, Date(timeIntervalSince1970: 0)), (2, Date(timeIntervalSince1970: 3600))])
    ]
    let wantings = [
      "SELECT * FROM entry_view WHERE feedid = 1 AND updated > '1970-01-01 00:00:00' ORDER BY feedid, updated;",
      "SELECT * FROM entry_view WHERE feedid = 1 AND updated > '1970-01-01 00:00:00' OR feedid = 2 AND updated > '1970-01-01 01:00:00' ORDER BY feedid, updated;"
    ]
    for (i, wanted) in wantings.enumerated() {
      let found = findings[i]
      XCTAssertEqual(found, wanted)
    }
  }

  func testSQLToSelectRowsByIDs() {
    let tests = [
      ("entry_view", SQLFormatter.SQLToSelectEntriesByEntryIDs),
      ("feed_view", SQLFormatter.SQLToSelectFeedsByFeedIDs)
    ]
    for t in tests {
      let (table, f) = t
      XCTAssertNil(f([]))
      let findings = [
        f([1]),
        f([1,2,3])
      ]
      let wantings = [
        "SELECT * FROM \(table) WHERE uid = 1;",
        "SELECT * FROM \(table) WHERE uid = 1 OR uid = 2 OR uid = 3;"
      ]
      for (i, wanted) in wantings.enumerated() {
        let found = findings[i]
        XCTAssertEqual(found, wanted)
      }
    }
  }

  func testSQLToRemoveFeedsWithFeedIDs() {
    let f = SQLFormatter.SQLToRemoveFeedsWithFeedIDs
    XCTAssertNil(f([]))
    let findings = [
      f([1]),
      f([1,2,3])
    ]
    let wantings = [
      "DELETE FROM feed WHERE rowid IN(1);",
      "DELETE FROM feed WHERE rowid IN(1, 2, 3);"
    ]
    for (i, wanted) in wantings.enumerated() {
      let found = findings[i]
      XCTAssertEqual(found, wanted)
    }
  }

  func testSQLToSelectFeedIDFromURLView() {
    let found = SQLFormatter.SQLToSelectFeedIDFromURLView("abc'")
    let wanted = "SELECT feedid FROM url_view WHERE url = 'abc''';"
    XCTAssertEqual(found, wanted)
  }

  func testSQLFormatter() {
    let f = formatter.stringFromAny
    let other = NSObject()
    let found = [
      f(nil),
      f("hello"),
      f("that's amazing"),
      f(0),
      f(1),
      f(2.1),
      f(Date.init(timeIntervalSince1970: 0)),
      f(URL(string: "http://google.com")),
      f(other)
    ]
    let wanted = [
      "NULL",
      "'hello'",
      "'that''s amazing'",
      "0",
      "1",
      "2.1",
      "'1970-01-01 00:00:00'",
      "'http://google.com'",
      "NULL"
    ]
    for (i, wantedString) in wanted.enumerated() {
      let foundString = found[i]
      XCTAssertEqual(foundString, wantedString)
    }
  }

  func testSQLToInsertFeed() {
    let feed = try! feedWithName("thetalkshow")
    let found = formatter.SQLToInsertFeed(feed)
    
    let wanted = "INSERT INTO feed(author, guid, img, img100, img30, img60, img600, link, summary, title, updated, url) VALUES('Daring Fireball / John Gruber', 528458508, 'http://daringfireball.net/thetalkshow/graphics/cover-1400.jpg', 'abc', 'def', 'ghi', 'jkl', NULL, 'The director’s commentary track for Daring Fireball.', 'The Talk Show With John Gruber', '2015-10-17 19:35:01', 'http://daringfireball.net/thetalkshow/rss');"
    
    XCTAssertEqual(found, wanted)
  }

  func testSQLToUpdateFeed() {
    let feed = try! feedWithName("thetalkshow")
    let found = formatter.SQLToUpdateFeed(feed, withID: 1)
    
    let wanted = "UPDATE feed SET author = \'Daring Fireball / John Gruber\', guid = 528458508, img = \'http://daringfireball.net/thetalkshow/graphics/cover-1400.jpg\', img100 = \'abc\', img30 = \'def\', img60 = \'ghi\', img600 = \'jkl\', link = NULL, summary = \'The director’s commentary track for Daring Fireball.\', title = \'The Talk Show With John Gruber\', updated = \'2015-10-17 19:35:01\', url = \'http://daringfireball.net/thetalkshow/rss\' WHERE rowid = 1;"
    
    XCTAssertEqual(found, wanted)
  }

  func testSQLToInsertEntry() {
    let entry = try! entryWithName("thetalkshow")
    let found = formatter.SQLToInsertEntry(entry, forFeedID: 1)
    
    let wanted = "INSERT OR REPLACE INTO entry(author, duration, feedid, guid, img, length, link, subtitle, summary, title, type, updated, url) VALUES('Daring Fireball / John Gruber', 9185, 1, 'c596b134310d499b13651fed64597de2c9931179', 'http://daringfireball.net/thetalkshow/graphics/df-logo-1000.png', 110282964, 'http://daringfireball.net/thetalkshow/2015/10/17/ep-133', 'Andy and Dan talk about the new Microsoft Surface Tablet, the iPad Pro, the new Magic devices, the new iMacs, and more.', 'Serenity Caldwell returns to the show. Topics include this week’s new iMacs; the new “Magic” mouse, trackpad, and keyboard; an overview of Apple Music and iCloud Photos; Facebook’s outrageous background battery usage on iOS; Elon Musk’s gibes on Apple getting into the car industry; and my take on the new *Steve Jobs* movie.', 'Ep. 133: ‘The MacGuffin Tractor’, With Guest Serenity Caldwell', 1, '2015-10-17 19:35:01', 'http://tracking.feedpress.it/link/1068/1894544/228745910-thetalkshow-133a.mp3');"
    
    XCTAssertEqual(found, wanted)
  }
}

// Found no rule to separate Browsing into a clear-cut extension.

// MARK: - Searching

extension SQLTests {
  
  func testITunesItemFromRow() {
    let wanted = ITunesItem(guid: 123, img100: "img100", img30: "img30",
                            img60: "img60", img600: "img600")
    
    let row = Mirror(reflecting: wanted).children.reduce(SkullRow()) { acc, prop in
      var r = acc
      let col = skullColumn(prop.label!, value: prop.value)
      r[col.name] = col.value
      return r
    }
    
    let iTunes = SQLFormatter.iTunesItem(from: row)!
    
    XCTAssertEqual(iTunes.guid, 123)
    XCTAssertEqual(iTunes.img100, "img100")
    XCTAssertEqual(iTunes.img30, "img30")
    XCTAssertEqual(iTunes.img60, "img60")
    XCTAssertEqual(iTunes.img600, "img600")
  }
  
  func testSQLToInsertSuggestionForTerm() {
    let found = SQLFormatter.SQLToInsertSuggestionForTerm("abc")
    let wanted = "INSERT OR REPLACE INTO sug(term) VALUES('abc');"
    XCTAssertEqual(found, wanted)
  }
  
  func testSQLToSelectSuggestionsForTerm() {
    let found = SQLFormatter.SQLToSelectSuggestionsForTerm("abc", limit: 5)
    let wanted = "SELECT * FROM sug WHERE rowid IN (" +
      "SELECT rowid FROM sug_fts " +
      "WHERE term MATCH 'abc*') " +
      "ORDER BY ts DESC " +
      "LIMIT 5;"
    XCTAssertEqual(found, wanted)
  }
  
  func testSQLToDeleteSuggestionsMatchingTerm() {
    let found = SQLFormatter.SQLToDeleteSuggestionsMatchingTerm("abc")
    let wanted = "DELETE FROM sug " +
      "WHERE rowid IN (" +
      "SELECT rowid FROM sug_fts WHERE term MATCH 'abc*');"
    XCTAssertEqual(found, wanted)
  }
  
  func testSQLToInsertFeedIDForTerm() {
    let found = SQLFormatter.SQLToInsertFeedID(1, forTerm: "abc")
    let wanted = "INSERT OR REPLACE INTO search(feedID, term) VALUES(1, 'abc');"
    XCTAssertEqual(found, wanted)
  }
  
  func testSQLToSelectFeedsByTerm() {
    let found = SQLFormatter.SQLToSelectFeedsByTerm("abc", limit: 50)
    let wanted = "SELECT DISTINCT * FROM search_view WHERE searchid IN (" +
      "SELECT rowid FROM search_fts " +
      "WHERE term = 'abc') " +
      "LIMIT 50;"
    XCTAssertEqual(found, wanted)
  }
  
  func testSQLToSelectFeedsMatchingTerm() {
    let found = SQLFormatter.SQLToSelectFeedsMatchingTerm("abc", limit: 3)
    let wanted = "SELECT DISTINCT * FROM feed_view WHERE uid IN (" +
      "SELECT rowid FROM feed_fts " +
      "WHERE feed_fts MATCH 'abc*') " +
      "ORDER BY ts DESC " +
      "LIMIT 3;"
    XCTAssertEqual(found, wanted)
  }
  
  func testSQLToSelectEntriesMatchingTerm() {
    let found = SQLFormatter.SQLToSelectEntries(matching: "abc", limit: 3)
    let wanted = "SELECT DISTINCT * FROM entry_view WHERE uid IN (" +
    "SELECT rowid FROM entry_fts " +
    "WHERE entry_fts MATCH 'abc*') " +
    "ORDER BY updated DESC " +
    "LIMIT 3;"
    XCTAssertEqual(found, wanted)
  }
  
  func testSQLToDeleteSearchForTerm() {
    let found = SQLFormatter.SQLToDeleteSearch(for: "abc")
    let wanted = "DELETE FROM search WHERE term='abc';"
    XCTAssertEqual(found, wanted)
  }
  
}

// MARK: - Syncing

extension SQLTests {
  
  func testSQLToDeleteRecords() {
    XCTAssertNil(SQLFormatter.SQLToDeleteRecords(with: []))
    XCTAssertEqual(SQLFormatter.SQLToDeleteRecords(with: ["abc", "def"]),
      "DELETE FROM record WHERE record_name IN('abc', 'def');")
  }
  
  func testSQLToSelectLocallyQueuedEntries() {
    let wanted = "SELECT * FROM locally_queued_entry;"
    XCTAssertEqual(SQLFormatter.SQLToSelectLocallyQueuedEntries, wanted)
  }
  
  func testSQLToQueueSynced() {
    let loc = EntryLocator(url: "http://abc.de")
    let name = "E49847D6-6251-48E3-9D7D-B70E8B7392CD" // actual record name
    let record = RecordMetadata(name: name, changeTag: "e")
    let synced = Synced.entry(loc, Date(), record)
    XCTAssertThrowsError(try formatter.SQLToQueueSynced(locator: synced))
  }
  
}

// MARK: - Queueing

extension SQLTests {
  
  func testSQLToUnqueue() {
    XCTAssertNil(SQLFormatter.SQLToUnqueue(guids: []))

    let guids = ["12three", "45six"]
    let found = SQLFormatter.SQLToUnqueue(guids: guids)
    let wanted = "DELETE FROM queued_entry WHERE guid IN('12three', '45six');"
    XCTAssertEqual(found, wanted)
  }

  func testSQLToSelectAllQueued() {
    XCTAssertEqual(SQLFormatter.SQLToSelectAllQueued, "SELECT * FROM queued_entry_view ORDER BY ts DESC;")
  }
  
  func testSQLToQueueEntry() {
    do {
      let guid = "12three"
      let url = "abc.de"
      let since = Date(timeIntervalSince1970: 1465192800)
      let locator = EntryLocator(url: url, since: since, guid: guid)
      let found = formatter.SQLToQueue(entry: locator, with: guid)
      let wanted = "INSERT OR REPLACE INTO entry(guid, url, since) VALUES(\'12three\', \'abc.de\', \'2016-06-06 06:00:00\');\nINSERT OR REPLACE INTO queued_entry(guid) VALUES(\'12three\');"
      XCTAssertEqual(found, wanted)
    }
  }
  
  func testQueuedLocatorFromRow() {
    let keys = ["guid", "url", "since", "ts"]
    var row = skullRow(keys)
    
    let guid = "12three"
    let url = "abc.de"
    
    row["guid"] = guid
    row["url"] = url
    row["since"] = "2016-06-06 06:00:00" // UTC
    
    // This hassle of producing a timestamp is unnecessary, really, because 
    // Queued: Equatable only compares locator, not the timestamp.
    
    let now = formatter.now()
    row["ts"] = now
    let ts = formatter.date(from: now)    
    let found = formatter.queuedLocator(from: row)
    
    let since = Date(timeIntervalSince1970: 1465192800)
    let locator = EntryLocator(url: url, since: since, guid: guid)
    
    let wanted = Queued.entry(locator, ts!)
    
    XCTAssertEqual(found, wanted)
  }
  
}
