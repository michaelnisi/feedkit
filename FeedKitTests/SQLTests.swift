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

  static func skullColumn(_ name: String, value: Any) -> SkullColumn<Any> {
    return SkullColumn(name: name, value: value)
  }

  static func skullRow(_ keys: [String]) -> SkullRow {
    var row = SkullRow()
    for key in keys {
      let col = skullColumn(key, value: key)
      row[col.name] = col.value
    }
    return row
  }

  static func skullRow(from item: Any) -> SkullRow {
    return Mirror(reflecting: item).children.reduce(SkullRow()) { acc, prop in
      var r = acc
      let col = skullColumn(prop.label!, value: prop.value)
      r[col.name] = col.value
      return r
    }
  }

  func testITunesItemFromRow() {
    let url = "http://abc.de"
    
    let keys = ["img100", "img30", "img60", "img600"]
    
    let wanted = ITunesItem(
      url: url,
      iTunesID: 123,
      img100: "img100",
      img30: "img30",
      img60: "img60",
      img600: "img600"
    )
  
    do { // without iTunes GUID
      let row = SQLTests.skullRow(keys)
      XCTAssertNil(SQLFormatter.iTunesItem(from: row, url: url))
      XCTAssertNil(SQLFormatter.iTunesItem(from: row, url: nil))
    }

    do { // feed
      var row = SQLTests.skullRow(keys)
      row["itunes_guid"] = 123
      XCTAssertEqual(SQLFormatter.iTunesItem(from: row, url: url), wanted)
    }

    do { // entry
      var row = SQLTests.skullRow(keys)
      row["itunes_guid"] = 123
      XCTAssertEqual(SQLFormatter.iTunesItem(from: row, url: url), wanted)
    }
    
    do { // implicit URL
      var row = SQLTests.skullRow(keys)
      row["itunes_guid"] = 123
      row["feed_url"] = url
      XCTAssertEqual(SQLFormatter.iTunesItem(from: row, url: nil), wanted)
    }
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
    let found = LibrarySQLFormatter.SQLToSelectEntryByGUID("abc")
    let wanted = "SELECT * FROM entry_view WHERE entry_guid = 'abc';"
    XCTAssertEqual(found, wanted)
  }

  func testSQLToSelectRowsByIDs() {
    let tests = [
      ("entry_view", LibrarySQLFormatter.SQLToSelectEntriesByEntryIDs)
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
      LibrarySQLFormatter.SQLToRemoveFeeds(with: Array(feedIDs.prefix(1))),
      LibrarySQLFormatter.SQLToRemoveFeeds(with: feedIDs)
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
    let found = LibrarySQLFormatter.SQLToSelectFeedIDFromURLView("abc'")
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

}





