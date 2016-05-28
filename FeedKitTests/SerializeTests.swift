//
//  SerializeTests.swift
//  FeedKit
//
//  Created by Michael Nisi on 10.02.15.
//  Copyright (c) 2015 Michael Nisi. All rights reserved.
//

import XCTest
@testable import FeedKit

class SerializeTests: XCTestCase {

  func testTrimString () {
    func f (s: String) -> String {
      return trimString(s.lowercaseString, joinedByString: " ")
    }
    let input = [
      "apple",
      "apple watch",
      "  apple  watch ",
      "  apple     Watch Kit  ",
      " ",
      ""
    ]
    let wanted = [
      "apple",
      "apple watch",
      "apple watch",
      "apple watch kit",
      "",
      ""
    ]
    for (n, it) in wanted.enumerate() {
      XCTAssertEqual(f(input[n]), it)
    }
  }
  
  func testQueryFromString() {
    let f = queryFromString
    XCTAssertNil(f(""))
    XCTAssertNil(f(" "))
    XCTAssertNil(f("   "))
  }

  func testTimeIntervalFromJS () {
    let found = [
      timeIntervalFromJS(-1000),
      timeIntervalFromJS(0),
      timeIntervalFromJS(1000)
    ]
    let wanted = [
      -1.0,
      0.0,
      1.0
    ]
    for (n, it) in wanted.enumerate() {
      XCTAssertEqual(it, found[n])
    }
  }
  
  func testFeedFromInvalidDictonaries() {
    let things = [
      ([String:AnyObject](), "feed missing"),
      (["feed":"abc"], "title missing")
    ]
    things.forEach { (let dict, let wanted) in
      var ok = false
      do {
        try feedFromDictionary(dict)
      } catch FeedKitError.InvalidFeed(let reason) {
        XCTAssertEqual(reason, wanted)
        ok = true
      } catch {
        XCTFail("should be caught")
      }
      XCTAssert(ok)
    }
  }
  
  func testFeedFromDictionary() {
    let dict = ["feed": "abc", "title": "A title"]
    let wanted = Feed(author: nil, iTunesGuid: nil, images: nil, link: nil,
      summary: nil, title: "A title", ts: nil, uid: nil, updated: nil,
      url: "abc"
    )
    let found = try! feedFromDictionary(dict)
    XCTAssertEqual(found, wanted)
  }
  
  // TODO: Replace alibi with proper test
  func testFeedsFromPayload() {
    let dict = ["feed": "abc", "title": "A title"]
    let wanted = [Feed(author: nil, iTunesGuid: nil, images: nil, link: nil,
      summary: nil, title: "A title", ts: nil, uid: nil, updated: nil,
      url: "abc"
    )]
    let (errors, feeds) = feedsFromPayload([dict])
    XCTAssert(errors.isEmpty)
    XCTAssertEqual(feeds, wanted)
  }
  
  func testEntryFromDictionary() {
    let feed = "abc"
    let title = "Giant Robots"
    let id = "abc:def"
    let updated = NSDate(timeIntervalSince1970: 3600)
    let dict = [
      "feed": feed,
      "title": title,
      "id": id,
      "updated": NSNumber(double: 3600000) // ms
    ]
    let guid = entryGUID(feed, id: id, updated: updated)
    let wanted = Entry(author: nil, enclosure: nil, duration: nil, feed: feed,
      feedTitle: nil, guid: guid, id: id, img: nil, link: nil, subtitle: nil,
      summary: nil, title: title, ts: nil, updated: updated
    )
    let found = try! entryFromDictionary(dict, podcast: false)
    XCTAssertEqual(found, wanted)
  }
  
  func testEnclosureFromDictionary () {
    let f = enclosureFromDictionary
    do {
      try f([:])
      try f(["url": "http://serve.it/rad.mp3", "length": "123456"])
      try f(["type": "audio/mpeg", "length": "123456"])
      XCTFail("should throw")
    } catch {}
    let found = [
      try! f(["url": "abc", "type": "audio/mpeg"]),
      try! f(["url": "abc", "type": "audio/mpeg", "length": "123"])
    ]
    let wanted = [
      Enclosure(url: "abc", length: nil, type: .AudioMPEG),
      Enclosure(url: "abc", length: 123, type: .AudioMPEG)
    ]
    for (i, enc) in wanted.enumerate() {
      let it = found[i]!
      XCTAssertEqual(it, enc)
      XCTAssertEqual(it.url, enc.url)
      XCTAssertEqual(it.length, enc.length)
      XCTAssertEqual(it.type, enc.type)
    }
  }
}




