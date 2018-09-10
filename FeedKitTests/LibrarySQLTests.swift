//
//  LibrarySQLTests.swift
//  FeedKitTests
//
//  Created by Michael Nisi on 06.02.18.
//  Copyright © 2018 Michael Nisi. All rights reserved.
//

import XCTest

@testable import FeedKit
@testable import Skull

class LibrarySQLTests: XCTestCase {
  
  var formatter: LibrarySQLFormatter!
  
  override func setUp() {
    super.setUp()
    formatter = LibrarySQLFormatter()
  }
  
  override func tearDown() {
    formatter = nil
    super.tearDown()
  }
 
}

// MARK: - Browsing (Shared)

extension LibrarySQLTests {
  
  func testFeedFromRow() {
    let url = "http://abc.de"
    
    let keys = [
      "img", "img100", "img30", "img60", "img600", "author", "link", "summary",
      "title", "updated"
    ]
    var row = SQLTests.skullRow(keys)
    
    row["itunes_guid"] = 123
    row["feed_id"] = Int64(0)
    row["ts"] = "2016-06-06 06:00:00"
    row["url"] = url
    
    let found = try! formatter.feedFromRow(row)
    
    let iTunes = ITunesItem(
      url: url,
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
      uid: FeedID(rowid: 0, url: url),
      updated: nil,
      url: url
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
  
  func testSQLToInsertFeed() {
    let feed = Common.makeFeed(name: .gruber)
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
    let feed = Common.makeFeed(name: .gruber)
    let feedID = FeedID(rowid: 1, url: feed.url)
    let found = formatter.SQLToUpdate(feed: feed, with: feedID, from: .hosted)
    
    let wanted = "UPDATE feed SET author = \'Daring Fireball / John Gruber\', itunes_guid = 528458508, img = \'http://daringfireball.net/thetalkshow/graphics/cover-1400.jpg\', img100 = \'abc\', img30 = \'def\', img60 = \'ghi\', img600 = \'jkl\', link = NULL, summary = \'The director’s commentary track for Daring Fireball.\', title = \'The Talk Show With John Gruber\', updated = \'2015-10-17 19:35:01\', url = \'http://daringfireball.net/thetalkshow/rss\' WHERE feed_id = 1;"
    
    XCTAssertEqual(found, wanted)
  }
  
  func testSQLToUpdateITunesFeed() {
    let feed = Common.makeFeed(name: .gruber)
    let feedID = FeedID(rowid: 1, url: feed.url)
    let found = formatter.SQLToUpdate(feed: feed, with: feedID, from: .iTunes)
    
    let wanted = "UPDATE feed SET author = \'Daring Fireball / John Gruber\', itunes_guid = 528458508, img = \'http://daringfireball.net/thetalkshow/graphics/cover-1400.jpg\', img100 = \'abc\', img30 = \'def\', img60 = \'ghi\', img600 = \'jkl\', summary = \'The director’s commentary track for Daring Fireball.\', title = \'The Talk Show With John Gruber\', updated = \'2015-10-17 19:35:01\', url = \'http://daringfireball.net/thetalkshow/rss\' WHERE feed_id = 1;"
    
    XCTAssertEqual(found, wanted, "should keep link")
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

// MARK: - Searching

extension LibrarySQLTests {
  
  func testSuggestionFromRow() {
    XCTAssertThrowsError(try formatter.suggestionFromRow(SkullRow()))
    XCTAssertThrowsError(try formatter.suggestionFromRow(SQLTests.skullRow(["ts"])))
    XCTAssertThrowsError(try formatter.suggestionFromRow(SQLTests.skullRow(["term"])))
    XCTAssertThrowsError(try formatter.suggestionFromRow(SQLTests.skullRow(["term", "ts"])))
    
    var row = SkullRow()
    row["term"] = "abc"
    row["ts"] =  "2016-06-06 06:00:00"
    
    let ts = Date(timeIntervalSince1970: 1465192800)
    let wanted = Suggestion(term: "abc", ts: ts)
    
    let found = try! formatter.suggestionFromRow(row)
    
    XCTAssertEqual(found, wanted)
  }
  
  func testSQLToInsertSuggestionForTerm() {
    let found = LibrarySQLFormatter.SQLToInsertSuggestionForTerm("abc")
    let wanted = "INSERT OR REPLACE INTO sug(term) VALUES('abc');"
    XCTAssertEqual(found, wanted)
  }
  
  func testMakeTokenQueryExpression() {
    func f(_ str: String) -> String {
      return LibrarySQLFormatter.makeTokenQueryExpression(string: str)
    }
    XCTAssertEqual(f("()*:\"^"), "'*'")
    XCTAssertEqual(f("abc("), "'abc*'")
  }
  
  func testSQLToSelectSuggestionsForTerm() {
    let found = LibrarySQLFormatter.SQLToSelectSuggestionsForTerm("abc", limit: 5)
    let wanted = """
    SELECT * FROM sug WHERE rowid IN (
      SELECT rowid FROM sug_fts
      WHERE term MATCH 'abc*'
    ) ORDER BY ts DESC LIMIT 5;
    """
    XCTAssertEqual(found, wanted)
  }
  
  func testSQLToDeleteSuggestionsMatchingTerm() {
    let found = LibrarySQLFormatter.SQLToDeleteSuggestionsMatchingTerm("abc")
    let wanted = """
    DELETE FROM sug WHERE rowid IN (
      SELECT rowid FROM sug_fts
      WHERE term MATCH 'abc*'
    );
    """
    XCTAssertEqual(found, wanted)
  }
  
  func testSQLToInsertFeedIDForTerm() {
    let feedID = FeedID(rowid: 1, url: "http://abc.de")
    let found = LibrarySQLFormatter.SQLToInsert(feedID: feedID, for: "abc")
    let wanted = "INSERT OR REPLACE INTO search(feed_id, term) VALUES(1, 'abc');"
    XCTAssertEqual(found, wanted)
  }
  
  func testSQLToSelectFeedsByTerm() {
    let found = LibrarySQLFormatter.SQLToSelectFeeds(for: "abc", limit: 50)
    let wanted = """
    SELECT DISTINCT * FROM search_view WHERE searchid IN (
      SELECT rowid FROM search_fts
      WHERE term = 'abc'
    ) LIMIT 50;
    """
    XCTAssertEqual(found, wanted)
  }
  
  func testSQLToSelectFeedsMatchingTerm() {
    let found = LibrarySQLFormatter.SQLToSelectFeeds(matching: "abc", limit: 3)
    let wanted = """
    SELECT DISTINCT * FROM feed WHERE feed_id IN (
      SELECT rowid FROM feed_fts
      WHERE feed_fts MATCH 'abc*'
    ) ORDER BY ts DESC LIMIT 3;
    """
    XCTAssertEqual(found, wanted)
  }
  
  func testSQLToSelectEntriesMatchingTerm() {
    let found = LibrarySQLFormatter.SQLToSelectEntries(matching: "abc", limit: 3)
    let wanted = """
    SELECT DISTINCT * FROM entry_view WHERE entry_id IN (
      SELECT rowid FROM entry_fts
      WHERE summary MATCH 'abc*' LIMIT 1000
    ) ORDER BY updated DESC LIMIT 3;
    """
    XCTAssertEqual(found, wanted)
  }
  
  func testSQLToDeleteSearchForTerm() {
    let found = LibrarySQLFormatter.SQLToDeleteSearch(for: "abc")
    let wanted = "DELETE FROM search WHERE term = 'abc';"
    XCTAssertEqual(found, wanted)
  }
  
}


// MARK: - Integrating iTunes Metadata

extension LibrarySQLTests {
  
  func testSQLToUpdate() {
    let url = "http://abc.de"
    
    let iTunes = ITunesItem(
      url: url,
      iTunesID: 123,
      img100: "img100",
      img30: "img30",
      img60: "img60",
      img600: "img600"
    )
    
    let wanted = """
    UPDATE feed SET \
    itunes_guid = \(iTunes.iTunesID), \
    img100 = '\(iTunes.img100)', \
    img30 = '\(iTunes.img30)', \
    img60 = '\(iTunes.img60)', \
    img600 = '\(iTunes.img600)' \
    WHERE url = '\(url)';
    """
    let found = formatter.SQLToUpdate(iTunes: iTunes)
    XCTAssertEqual(found, wanted)
  }
  
}
