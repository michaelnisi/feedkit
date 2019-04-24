//
//  LibrarySQLTests.swift
//  FeedKitTests
//
//  Created by Michael Nisi on 06.02.18.
//  Copyright © 2018 Michael Nisi. All rights reserved.
//

import XCTest
import SnapshotTesting

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
      uid: Feed.ID(rowid: 0, url: url),
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
        (Feed.ID(rowid: 1, url: "http://abc.de"), Date(timeIntervalSince1970: 0))
        ]),
      formatter.SQLToSelectEntries(within: [
        (Feed.ID(rowid: 1, url: "http://abc.de"), Date(timeIntervalSince1970: 0)),
        (Feed.ID(rowid: 2, url: "http://efg.hi"), Date(timeIntervalSince1970: 3600))
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
    
     assertSnapshot(matching: found, as: .dump)
  }
  
  func testSQLToUpdateFeed() {
    let feed = Common.makeFeed(name: .gruber)
    let feedID = Feed.ID(rowid: 1, url: feed.url)
    let found = formatter.SQLToUpdate(feed: feed, with: feedID, from: .hosted)
    
    assertSnapshot(matching: found, as: .dump)
  }
  
  func testSQLToUpdateITunesFeed() {
    let feed = Common.makeFeed(name: .gruber)
    let feedID = Feed.ID(rowid: 1, url: feed.url)
    let found = formatter.SQLToUpdate(feed: feed, with: feedID, from: .iTunes)

    assertSnapshot(matching: found, as: .dump, named: "should keep link")
  }
  
  func testSQLToInsertEntry() {
    let entry = Common.makeEntry(name: .gruber)
    let feedID = Feed.ID(rowid: 1, url: entry.feed)
    let found = formatter.SQLToInsert(entry: entry, for: feedID)
    
     assertSnapshot(matching: found, as: .dump)
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

     assertSnapshot(matching: found, as: .dump)
  }
  
  func testSQLToDeleteSuggestionsMatchingTerm() {
    let found = LibrarySQLFormatter.SQLToDeleteSuggestionsMatchingTerm("abc")
    
     assertSnapshot(matching: found, as: .dump)
  }
  
  func testSQLToInsertFeedIDForTerm() {
    let feedID = Feed.ID(rowid: 1, url: "http://abc.de")
    let found = LibrarySQLFormatter.SQLToInsert(feedID: feedID, for: "abc")
    let wanted = "INSERT OR REPLACE INTO search(feed_id, term) VALUES(1, 'abc');"
    XCTAssertEqual(found, wanted)
  }
  
  func testSQLToSelectFeedsByTerm() {
    let found = LibrarySQLFormatter.SQLToSelectFeeds(for: "abc", limit: 50)
    
     assertSnapshot(matching: found, as: .dump)
  }
  
  func testSQLToSelectFeedsMatchingTerm() {
    let found = LibrarySQLFormatter.SQLToSelectFeeds(matching: "abc", limit: 3)
    
     assertSnapshot(matching: found, as: .dump)
  }
  
  func testSQLToSelectEntriesMatchingTerm() {
    let found = LibrarySQLFormatter.SQLToSelectEntries(matching: "abc", limit: 3)
    
     assertSnapshot(matching: found, as: .dump)
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
    
    let found = formatter.SQLToUpdate(iTunes: iTunes)
    
    assertSnapshot(matching: found, as: .dump)
  }
  
}
