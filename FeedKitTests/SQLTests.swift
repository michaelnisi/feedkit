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
  
  fileprivate func skullRow(from item: Any) -> SkullRow {
    return Mirror(reflecting: item).children.reduce(SkullRow()) { acc, prop in
      var r = acc
      let col = skullColumn(prop.label!, value: prop.value)
      r[col.name] = col.value
      return r
    }
  }
  
  func testITunesFromRow() {
    let wanted = ITunesItem(
      iTunesID: 123,
      img100: "img100",
      img30: "img30",
      img60: "img60",
      img600: "img600"
    )
    
    do { // feed
      let keys = ["img100", "img30", "img60", "img600"]
      var row = skullRow(keys)
      row["itunes_guid"] = 123
      XCTAssertEqual(SQLFormatter.iTunesItem(from: row), wanted)
    }
    
    do { // entry
      let keys = ["img100", "img30", "img60", "img600"]
      var row = skullRow(keys)
      row["itunes_guid"] = 123
      XCTAssertEqual(SQLFormatter.iTunesItem(from: row), wanted)
    }
  }
  
  func testFeedFromRow() {
    let keys = [
      "img", "img100", "img30", "img60", "img600", "author", "link", "summary",
      "title", "updated", "url"
    ]
    var row = skullRow(keys)
    
    row["itunes_guid"] = 123
    row["feed_id"] = Int64(0)
    row["ts"] = "2016-06-06 06:00:00"
    
    let found = try! formatter.feedFromRow(row)
    
    let iTunes = ITunesItem(
      iTunesID: 123,
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
      uid: FeedID(rowid: 0, url: "url"),
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
    let wanted = "SELECT * FROM entry_view WHERE entry_guid = 'abc';"
    XCTAssertEqual(found, wanted)
  }

  func testSQLToSelectEntriesByIntervals() {
    let findings = [
      formatter.SQLToSelectEntries(within: [
        (FeedID(rowid: 1, url: "http://abc.de"), Date(timeIntervalSince1970: 0))
      ]),
      formatter.SQLToSelectEntries(within: [
        (FeedID(rowid: 1, url: "http://abc.de"), Date(timeIntervalSince1970: 0)),
        (FeedID(rowid: 2, url: "http://efg.hi"), Date(timeIntervalSince1970: 3600))
      ])
    ]
    let wantings = [
      "SELECT * FROM entry_view WHERE feed_id = 1 AND updated > '1970-01-01 00:00:00' ORDER BY feed_id, updated;",
      "SELECT * FROM entry_view WHERE feed_id = 1 AND updated > '1970-01-01 00:00:00' OR feed_id = 2 AND updated > '1970-01-01 01:00:00' ORDER BY feed_id, updated;"
    ]
    for (i, wanted) in wantings.enumerated() {
      let found = findings[i]
      XCTAssertEqual(found, wanted)
    }
  }

  func testSQLToSelectRowsByIDs() {
    let tests = [
      ("entry_view", SQLFormatter.SQLToSelectEntriesByEntryIDs)
    ]
    for t in tests {
      let (table, f) = t
      XCTAssertNil(f([]))
      let findings = [
        f([1]),
        f([1,2,3])
      ]
      let wantings = [
        "SELECT * FROM \(table) WHERE entry_id = 1;",
        "SELECT * FROM \(table) WHERE entry_id = 1 OR entry_id = 2 OR entry_id = 3;"
      ]
      for (i, wanted) in wantings.enumerated() {
        let found = findings[i]
        XCTAssertEqual(found, wanted)
      }
    }
  }

  func testSQLToRemoveFeedsWithFeedIDs() {
    let feedIDs = [
      FeedID(rowid: 1, url: "http://abc.de"),
      FeedID(rowid: 2, url: "http://fgh.ij"),
      FeedID(rowid: 3, url: "http://klm.no")
    ]
    let findings = [
      SQLFormatter.SQLToRemoveFeeds(with: Array(feedIDs.prefix(1))),
      SQLFormatter.SQLToRemoveFeeds(with: feedIDs)
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
    let wanted = "SELECT * FROM url_view WHERE url = 'abc''';"
    XCTAssertEqual(found, wanted)
  }

  func testSQLFormatter() {
    let f = formatter.SQLString
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
    let feed = try! freshFeed(named: "thetalkshow")
    let found = formatter.SQLToInsert(feed: feed)
    
    let wanted = """
    INSERT INTO feed(
      author, itunes_guid, img, img100, img30, img60, img600,
      link, summary, title, updated, url
    ) VALUES(
      'Daring Fireball / John Gruber', 528458508, 'http://daringfireball.net/thetalkshow/graphics/cover-1400.jpg', 'abc', 'def', 'ghi', 'jkl',
      NULL, 'The director’s commentary track for Daring Fireball.', 'The Talk Show With John Gruber', '2015-10-17 19:35:01', 'http://daringfireball.net/thetalkshow/rss'
    );
    """
    
    XCTAssertEqual(found, wanted)
  }

  func testSQLToUpdateFeed() {
    let feed = try! freshFeed(named: "thetalkshow")
    let feedID = FeedID(rowid: 1, url: feed.url)
    let found = formatter.SQLToUpdate(feed: feed, with: feedID)
    
    let wanted = "UPDATE feed SET author = \'Daring Fireball / John Gruber\', itunes_guid = 528458508, img = \'http://daringfireball.net/thetalkshow/graphics/cover-1400.jpg\', img100 = \'abc\', img30 = \'def\', img60 = \'ghi\', img600 = \'jkl\', link = NULL, summary = \'The director’s commentary track for Daring Fireball.\', title = \'The Talk Show With John Gruber\', updated = \'2015-10-17 19:35:01\', url = \'http://daringfireball.net/thetalkshow/rss\' WHERE feed_id = 1;"
    
    XCTAssertEqual(found, wanted)
  }

  func testSQLToInsertEntry() {
    let entry = try! freshEntry(named: "thetalkshow")
    let feedID = FeedID(rowid: 1, url: entry.feed)
    let found = formatter.SQLToInsert(entry: entry, for: feedID)
    
    let wanted = """
    INSERT OR REPLACE INTO entry(
      author, duration, feed_id, entry_guid, img, length,
      link, subtitle, summary, title, type, updated, url
    ) VALUES(
      'Daring Fireball / John Gruber', 9185, 1, 'c596b134310d499b13651fed64597de2c9931179', 'http://daringfireball.net/thetalkshow/graphics/df-logo-1000.png', 110282964,
      'http://daringfireball.net/thetalkshow/2015/10/17/ep-133', 'Andy and Dan talk about the new Microsoft Surface Tablet, the iPad Pro, the new Magic devices, the new iMacs, and more.', 'Serenity Caldwell returns to the show. Topics include this week’s new iMacs; the new “Magic” mouse, trackpad, and keyboard; an overview of Apple Music and iCloud Photos; Facebook’s outrageous background battery usage on iOS; Elon Musk’s gibes on Apple getting into the car industry; and my take on the new *Steve Jobs* movie.', 'Ep. 133: ‘The MacGuffin Tractor’, With Guest Serenity Caldwell', 1, '2015-10-17 19:35:01', 'http://tracking.feedpress.it/link/1068/1894544/228745910-thetalkshow-133a.mp3'
    );
    """
    
    XCTAssertEqual(found, wanted)
  }
}

// Found no rule to separate Browsing into a clear-cut extension.

// MARK: - Searching

extension SQLTests {
  
  func testSuggestionFromRow() {
    XCTAssertThrowsError(try formatter.suggestionFromRow(SkullRow()))
    XCTAssertThrowsError(try formatter.suggestionFromRow(skullRow(["ts"])))
    XCTAssertThrowsError(try formatter.suggestionFromRow(skullRow(["term"])))
    XCTAssertThrowsError(try formatter.suggestionFromRow(skullRow(["term", "ts"])))
    
    var row = SkullRow()
    row["term"] = "abc"
    row["ts"] =  "2016-06-06 06:00:00"
    
    let ts = Date(timeIntervalSince1970: 1465192800)
    let wanted = Suggestion(term: "abc", ts: ts)
    
    let found = try! formatter.suggestionFromRow(row)

    XCTAssertEqual(found, wanted)
  }
  
  func testITunesItemFromRow() {
    do {
      let rows: [SkullRow] = [
        ["itunes_guid": 123, "img100": "a", "img30": "b", "img60": "c", "img600": "d"]
      ]
      
      for row in rows {
        let found = SQLFormatter.iTunesItem(from: row)!
      
        XCTAssertEqual(found.iTunesID, 123)
        XCTAssertEqual(found.img100, "a")
        XCTAssertEqual(found.img30, "b")
        XCTAssertEqual(found.img60, "c")
        XCTAssertEqual(found.img600, "d")
      }
    }
    
    do {
      let row = ["img100": "a", "img30": "b", "img60": "c", "img600": "d"]
      XCTAssertNil(SQLFormatter.iTunesItem(from: row))
    }
  }
  
  func testSQLToInsertSuggestionForTerm() {
    let found = SQLFormatter.SQLToInsertSuggestionForTerm("abc")
    let wanted = "INSERT OR REPLACE INTO sug(term) VALUES('abc');"
    XCTAssertEqual(found, wanted)
  }
  
  func testSQLToSelectSuggestionsForTerm() {
    let found = SQLFormatter.SQLToSelectSuggestionsForTerm("abc", limit: 5)
    let wanted = [
      "SELECT * FROM sug WHERE rowid IN (",
      "SELECT rowid FROM sug_fts ",
      "WHERE term MATCH 'abc*') ",
      "ORDER BY ts DESC ",
      "LIMIT 5;"
    ].joined()
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
    let feedID = FeedID(rowid: 1, url: "http://abc.de")
    let found = SQLFormatter.SQLToInsert(feedID: feedID, for: "abc")
    let wanted = "INSERT OR REPLACE INTO search(feed_id, term) VALUES(1, 'abc');"
    XCTAssertEqual(found, wanted)
  }
  
  func testSQLToSelectFeedsByTerm() {
    let found = SQLFormatter.SQLToSelectFeedsByTerm("abc", limit: 50)
    let wanted = [
      "SELECT DISTINCT * FROM search_view WHERE searchid IN (",
      "SELECT rowid FROM search_fts ",
      "WHERE term = 'abc') ",
      "LIMIT 50;"
    ].joined()
    XCTAssertEqual(found, wanted)
  }
  
  func testSQLToSelectFeedsMatchingTerm() {
    let found = SQLFormatter.SQLToSelectFeedsMatchingTerm("abc", limit: 3)
    let wanted = [
      "SELECT DISTINCT * FROM feed WHERE feed_id IN (",
      "SELECT rowid FROM feed_fts ",
      "WHERE feed_fts MATCH 'abc*') ",
      "ORDER BY ts DESC ",
      "LIMIT 3;"
    ].joined()
    XCTAssertEqual(found, wanted)
  }
  
  func testSQLToSelectEntriesMatchingTerm() {
    let found = SQLFormatter.SQLToSelectEntries(matching: "abc", limit: 3)
    let wanted = [
      "SELECT DISTINCT * FROM entry_view WHERE entry_id IN (",
      "SELECT rowid FROM entry_fts ",
      "WHERE entry_fts MATCH 'abc*') ",
      "ORDER BY updated DESC ",
      "LIMIT 3;"
    ].joined()
    XCTAssertEqual(found, wanted)
  }
  
  func testSQLToDeleteSearchForTerm() {
    let found = SQLFormatter.SQLToDeleteSearch(for: "abc")
    let wanted = "DELETE FROM search WHERE term = 'abc';"
    XCTAssertEqual(found, wanted)
  }
  
}

// MARK: - Integrating iTunes Metadata

extension SQLTests {
  
  func testSQLToUpdate() {
    let iTunes = ITunesItem(
      iTunesID: 123,
      img100: "img100", img30: "img30", img60: "img60", img600: "img600")
    
    let url = "http://abc.de"
    
    let wanted = """
    UPDATE feed SET \
    itunes_guid = \(iTunes.iTunesID), \
    img100 = '\(iTunes.img100)', \
    img30 = '\(iTunes.img30)', \
    img60 = '\(iTunes.img60)', \
    img600 = '\(iTunes.img600)' \
    WHERE url = '\(url)';
    """
    let found = formatter.SQLToUpdate(iTunes: iTunes, where: url)
    XCTAssertEqual(found, wanted)
  }
  
}

// MARK: - Syncing

extension SQLTests {
  
  func testSQLToDeleteRecords() {
    XCTAssertEqual(SQLFormatter.SQLToDeleteRecords(with: []),
      "DELETE FROM record WHERE record_name IN();")
    XCTAssertEqual(SQLFormatter.SQLToDeleteRecords(with: ["abc", "def"]),
      "DELETE FROM record WHERE record_name IN('abc', 'def');")
  }
  
  func testSQLToSelectLocallyQueuedEntries() {
    let wanted = "SELECT * FROM locally_queued_entry_view;"
    XCTAssertEqual(SQLFormatter.SQLToSelectLocallyQueuedEntries, wanted)
  }
  
  func testSQLToReplaceSynced() {
    let zoneName = "queueZone"
    let recordName = "E49847D6-6251-48E3-9D7D-B70E8B7392CD"
    let changeTag = "e"
    let record = RecordMetadata(zoneName: zoneName, recordName: recordName, changeTag: changeTag)
    
    do {
      let loc = EntryLocator(url: "http://abc.de")
      let synced = Synced.entry(loc, Date(), record)
      XCTAssertThrowsError(try formatter.SQLToReplace(synced: synced))
    }
    
    let ts = Date(timeIntervalSince1970: 1465192800) // 2016-06-06 06:00:00
    
    do {
      let loc = EntryLocator(url: "http://abc.de", since: nil, guid: "abc", title: nil)
      let synced = Synced.entry(loc, ts, record)
      let found = try! formatter.SQLToReplace(synced: synced)
      let wanted = "INSERT OR REPLACE INTO record(record_name, zone_name, change_tag) VALUES(\'E49847D6-6251-48E3-9D7D-B70E8B7392CD\', \'queueZone\', \'e\');\nINSERT OR REPLACE INTO entry(entry_guid, feed_url, since) VALUES(\'abc\', \'http://abc.de\', \'1970-01-01 00:00:00\');\nINSERT OR REPLACE INTO queued_entry(entry_guid, ts, record_name) VALUES(\'abc\', \'2016-06-06 06:00:00\', \'E49847D6-6251-48E3-9D7D-B70E8B7392CD\');"
      XCTAssertEqual(found, wanted)
    }
    
    do {
      let url = "http://abc.de"
      let s = Subscription(url: url, iTunes: nil, ts: ts)
      let synced = Synced.subscription(s, record)
      let found = try! formatter.SQLToReplace(synced: synced)
      let wanted = """
      INSERT OR REPLACE INTO record(
        record_name, zone_name, change_tag
      ) VALUES(
        'E49847D6-6251-48E3-9D7D-B70E8B7392CD\', \'queueZone\', \'e\'
      );

      INSERT OR REPLACE INTO feed(
        feed_url, itunes_guid, img100, img30, img60, img600
      ) VALUES(
        'http://abc.de\', NULL, NULL, NULL, NULL, NULL
      );

      INSERT OR REPLACE INTO subscribed_feed(
        feed_url, record_name, ts
      ) VALUES(
        'http://abc.de\', \'E49847D6-6251-48E3-9D7D-B70E8B7392CD\', \'2016-06-06 06:00:00\'
      );
      """

      XCTAssertEqual(found, wanted)
    }
  }
  
  func testSQLToSelectLocallySubscribedFeeds() {
    let wanted = "SELECT * FROM locally_subscribed_feed_view;"
    XCTAssertEqual(SQLFormatter.SQLToSelectLocallySubscribedFeeds, wanted)
  }
  
}

// MARK: - Subscribing

extension SQLTests {
 
  func testSQLToSelectSubscriptions() {
    let wanted = "SELECT * from subscribed_feed_view;"
    XCTAssertEqual(SQLFormatter.SQLToSelectSubscriptions, wanted)
  }
  
  func testSQLToSelectZombieFeedGUIDs() {
    let wanted = "SELECT * from zombie_feed_url_view;"
    XCTAssertEqual(SQLFormatter.SQLToSelectZombieFeedURLs, wanted)
  }
  
  func testSQLToReplaceSubscriptions() {
    do {
      let url = "https://abc.de/rss"
      let s = Subscription(url: url)
      let found = formatter.SQLToReplace(subscription: s)
      let (iTunesID, img100, img30, img60, img600) = ("NULL", "NULL", "NULL", "NULL", "NULL")
      let wanted = """
      INSERT OR REPLACE INTO feed(
        feed_url, itunes_guid, img100, img30, img60, img600
      ) VALUES(
        '\(url)', \(iTunesID), \(img100), \(img30), \(img60), \(img600)
      );
      INSERT OR REPLACE INTO subscribed_feed(feed_url) VALUES('\(url)');
      """
      XCTAssertEqual(found, wanted)
    }
  }
  
  func testSQLToDeleteSubscriptions() {
    XCTAssertEqual(
      SQLFormatter.SQLToDelete(subscribed: []),
      "DELETE FROM subscribed_feed WHERE feed_url IN();")
    
    let url = "http://abc.de"
    let found = SQLFormatter.SQLToDelete(subscribed: [url])
    let wanted = "DELETE FROM subscribed_feed WHERE feed_url IN('\(url)');"
    XCTAssertEqual(found, wanted)
  }
  
}

// MARK: - Queueing

extension SQLTests {
  
  func testSQLToUnqueue() {
    XCTAssertNil(SQLFormatter.SQLToUnqueue(guids: []))

    let guids = ["12three", "45six"]
    let found = SQLFormatter.SQLToUnqueue(guids: guids)
    let wanted = "DELETE FROM queued_entry WHERE entry_guid IN('12three', '45six');"
    XCTAssertEqual(found, wanted)
  }

  func testSQLToSelectAllQueued() {
    XCTAssertEqual(SQLFormatter.SQLToSelectAllQueued,
                   "SELECT * FROM queued_entry_view ORDER BY ts DESC;")
  }
  
  func testSQLToSelectAllPrevious() {
    XCTAssertEqual(SQLFormatter.SQLToSelectAllPrevious,
                   "SELECT * FROM prev_entry_view ORDER BY ts DESC;")
  }
  
  func testSQLToQueueEntry() {
    do {
      let locator = EntryLocator(url: "http://abc.de")
      XCTAssertThrowsError(try formatter.SQLToQueue(entry: locator))
    }
    
    do {
      let guid = "12three"
      let url = "abc.de"
      let since = Date(timeIntervalSince1970: 1465192800) // 2016-06-06 06:00:00
      let locator = EntryLocator(url: url, since: since, guid: guid)
      let found = try! formatter.SQLToQueue(entry: locator)
      let wanted = """
      INSERT OR REPLACE INTO entry(
        entry_guid, feed_url, since
      ) VALUES(
        '12three\', \'abc.de\', \'2016-06-06 06:00:00\'
      );
      INSERT OR REPLACE INTO queued_entry(entry_guid) VALUES(\'12three\');
      """
      XCTAssertEqual(found, wanted)
    }
  }
  
  func testQueuedLocatorFromRow() {
    let keys = ["guid", "url", "since", "ts"]
    var row = skullRow(keys)
    
    let guid = "12three"
    let url = "abc.de"
    
    row["entry_guid"] = guid
    row["feed_url"] = url
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
