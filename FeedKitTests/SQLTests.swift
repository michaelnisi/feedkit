//
//  SQLTests.swift
//  FeedKit
//
//  Created by Michael Nisi on 30/10/15.
//  Copyright © 2015 Michael Nisi. All rights reserved.
//

import XCTest
@testable import FeedKit

class SQLTests: XCTestCase {
  var formatter: SQLFormatter!
  
  override func setUp() {
    super.setUp()
    formatter = SQLFormatter()
  }
  
  func testSQLToSelectEntriesByIntervals() {
    let f = formatter.SQLToSelectEntriesByIntervals
    XCTAssertNil(f([]))
    let findings = [
      f([(1, NSDate(timeIntervalSince1970: 0))]),
      f([(1, NSDate(timeIntervalSince1970: 0)), (2, NSDate(timeIntervalSince1970: 3600))])
    ]
    let wantings = [
      "SELECT * FROM entry_view WHERE feedid = 1 AND ts > '1970-01-01 00:00:00' ORDER BY feedid, ts;",
      "SELECT * FROM entry_view WHERE feedid = 1 AND ts > '1970-01-01 00:00:00' OR feedid = 2 AND ts > '1970-01-01 01:00:00' ORDER BY feedid, ts;"
    ]
    for (i, wanted) in wantings.enumerate() {
      let found = findings[i]
      XCTAssertEqual(found, wanted)
    }
  }
  
  func testSQLToSelectFeedsByFeedIDs() {
    let f = SQLToSelectFeedsByFeedIDs
    XCTAssertNil(f([]))
    let findings = [
      f([1]),
      f([1,2,3])
    ]
    let wantings = [
      "SELECT * FROM feed_view WHERE uid = 1;",
      "SELECT * FROM feed_view WHERE uid = 1 OR uid = 2 OR uid = 3;"
    ]
    for (i, wanted) in wantings.enumerate() {
      let found = findings[i]
      XCTAssertEqual(found, wanted)
    }
  }
  
  func testSQLToRemoveFeedsWithFeedIDs() {
    let f = SQLToRemoveFeedsWithFeedIDs
    XCTAssertNil(f([]))
    let findings = [
      f([1]),
      f([1,2,3])
    ]
    let wantings = [
      "DELETE FROM feed WHERE rowid IN(1);",
      "DELETE FROM feed WHERE rowid IN(1, 2, 3);"
    ]
    for (i, wanted) in wantings.enumerate() {
      let found = findings[i]
      XCTAssertEqual(found, wanted)
    }
  }
  
  func testSQLToSelectFeedIDFromURLView() {
    let found = SQLToSelectFeedIDFromURLView("abc")
    let wanted = "SELECT feedid FROM url_view WHERE url = 'abc';"
    XCTAssertEqual(found, wanted)
  }
  
  func testSQLToInsertFeedIDForTerm() {
    let found = SQLToInsertFeedID(1, forTerm: "abc")
    let wanted = "INSERT OR REPLACE INTO search(feedID, term) VALUES(1, 'abc');"
    XCTAssertEqual(found, wanted)
  }
  
  func testSQLToInsertFeedID() {
    let found = SQLToSelectFeedsByTerm("abc", limit: 50)
    let wanted =
      "SELECT * FROM search_view WHERE uid IN (" +
      "SELECT feedid FROM search_fts " +
      "WHERE term MATCH 'abc') " +
      "ORDER BY ts DESC " +
      "LIMIT 50;"
    XCTAssertEqual(found, wanted)
  }
  
  func testSQLToSelectFeedsMatchingTerm() {
    let found = SQLToSelectFeedsMatchingTerm("abc", limit: 3)
    let wanted =
      "SELECT * FROM feed_view WHERE uid IN (" +
      "SELECT rowid FROM feed_fts " +
      "WHERE feed_fts MATCH 'abc*') " +
      "ORDER BY ts DESC " +
      "LIMIT 3;"
    XCTAssertEqual(found, wanted)
  }
  
  func testSQLToSelectEntriesMatchingTerm() {
    let found = SQLToSelectEntriesMatchingTerm("abc", limit: 3)
    let wanted =
      "SELECT * FROM entry_view WHERE uid IN (" +
      "SELECT rowid FROM entry_fts " +
      "WHERE entry_fts MATCH 'abc*') " +
      "ORDER BY ts DESC " +
      "LIMIT 3;"
    XCTAssertEqual(found, wanted)
  }
  
  func testSQLFormatter() {
    let f = formatter.stringFromAnyObject
    let found = [
      f(nil),
      f("hello"),
      f("that's amazing"),
      f(0),
      f(1),
      f(2.1),
      f(NSDate.init(timeIntervalSince1970: 0))
    ]
    let wanted = [
      "NULL",
      "'hello'",
      "'that''s amazing'",
      "0",
      "1",
      "2.1",
      "'1970-01-01 00:00:00'"
    ]
    for (i, wantedString) in wanted.enumerate() {
      let foundString = found[i]
      XCTAssertEqual(foundString, wantedString)
    }
  }
  
  func testSQLToInsertFeed() {
    let feed = try! feedWithName("thetalkshow")
    let found = formatter.SQLToInsertFeed(feed)
    let wanted = "INSERT INTO feed(author, guid, img, img100, img30, img60, img600, link, summary, title, updated, url) VALUES('Daring Fireball / John Gruber', 528458508, 'http://daringfireball.net/thetalkshow/graphics/cover-1400.jpg', NULL, NULL, NULL, NULL, 'http://feeds.muleradio.net/thetalkshow', 'The director’s commentary track for Daring Fireball.', 'The Talk Show With John Gruber', '2015-10-17 19:35:01', 'http://feeds.muleradio.net/thetalkshow');"
    XCTAssertEqual(found, wanted)
  }
  
  func testSQLToUpdateFeed() {
    let feed = try! feedWithName("thetalkshow")
    let found = formatter.SQLToUpdateFeed(feed, withID: 1)
    let wanted = "UPDATE feed SET author = 'Daring Fireball / John Gruber', guid = 528458508, img = 'http://daringfireball.net/thetalkshow/graphics/cover-1400.jpg', img100 = NULL, img30 = NULL, img60 = NULL, img600 = NULL, link = 'http://feeds.muleradio.net/thetalkshow', summary = 'The director’s commentary track for Daring Fireball.', title = 'The Talk Show With John Gruber', updated = '2015-10-17 19:35:01', url = 'http://feeds.muleradio.net/thetalkshow' WHERE rowid = 1;"
    XCTAssertEqual(found, wanted)
  }
  
  func testSQLToInsertEntry() {
    let entry = try! entryWithName("thetalkshow")
    let found = formatter.SQLToInsertEntry(entry, forFeedID: 1)
    let wanted = "INSERT OR REPLACE INTO entry(author, duration, feedid, id, img, length, link, subtitle, summary, title, type, updated, url) VALUES('Daring Fireball / John Gruber', '02:33:05', 1, 'http://daringfireball.net/thetalkshow/2015/10/17/ep-133', 'http://daringfireball.net/thetalkshow/graphics/df-logo-1000.png,', 110282964, 'http://daringfireball.net/thetalkshow/2015/10/17/ep-133', 'Andy and Dan talk about the new Microsoft Surface Tablet, the iPad Pro, the new Magic devices, the new iMacs, and more.', 'Serenity Caldwell returns to the show. Topics include this week’s new iMacs; the new “Magic” mouse, trackpad, and keyboard; an overview of Apple Music and iCloud Photos; Facebook’s outrageous background battery usage on iOS; Elon Musk’s gibes on Apple getting into the car industry; and my take on the new *Steve Jobs* movie.', 'Ep. 133: ‘The MacGuffin Tractor’, With Guest Serenity Caldwell', 0, '2015-10-17 19:35:01', 'http://tracking.feedpress.it/link/1068/1894544/228745910-thetalkshow-133a.mp3');"
    XCTAssertEqual(found, wanted)
  }
}
