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

  func testTrimString() {
    func f(_ s: String) -> String {
      return trimString(s.lowercased(), joinedByString: " ")
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
    for (n, it) in wanted.enumerated() {
      XCTAssertEqual(f(input[n]), it)
    }
  }

  func testTimeIntervalFromJS() {
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
    for (n, it) in wanted.enumerated() {
      XCTAssertEqual(it, found[n])
    }
  }

  func testDateFromDictionary() {
    XCTAssertNil(date(fromDictionary: [String:AnyObject](), withKey: "date"))

    let found = [
      Date(timeIntervalSince1970: -1),
      Date(timeIntervalSince1970: 0),
      Date(timeIntervalSince1970: 1)
    ]
    let wanted: [Date] = [
      date(fromDictionary: ["date": -1000], withKey: "date")!,
      date(fromDictionary: ["date": 0], withKey: "date")!,
      date(fromDictionary: ["date": 1000], withKey: "date")!
    ]
    for (n, it) in wanted.enumerated() {
      XCTAssertEqual(it, found[n])
    }
  }

  func testFeedImagesFromDictionary() {
    let keys = ["image", "img100", "img30", "img60", "img600"]
    let dict = keys.reduce([String:AnyObject]()) { acc, key in
      var images = acc
      images[key] = key as AnyObject?
      return images
    }
    let images = FeedImagesFromDictionary(dict)
    XCTAssertEqual(images.img, "image")
    XCTAssertEqual(images.img100, "img100")
    XCTAssertEqual(images.img30, "img30")
    XCTAssertEqual(images.img60, "img60")
    XCTAssertEqual(images.img600, "img600")
  }

  func testQueryFromString() {
    let f = queryFromString
    XCTAssertNil(f(""))
    XCTAssertNil(f(" "))
    XCTAssertNil(f("   "))
  }

  func testFeedFromInvalidDictonaries() {
    let things: [([String : Any], String)] = [
      ([String : Any](), "feed missing"),
      (["feed":"abc"], "title missing")
    ]
    things.forEach {
      let (dict, wanted) = $0
      var ok = false
      do {
        let _ = try feedFromDictionary(dict as [String : AnyObject])
      } catch FeedKitError.invalidFeed(let reason) {
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
  
  fileprivate func dictAndEntry() -> ([String : Any], Entry) {
    let feed = "abc"
    let title = "Giant Robots"
    let updated = Date(timeIntervalSince1970: 3600)
    
    let dict = [
      "feed": feed,
      "id": "c596b134310d499b13651fed64597de2c9931179",
      "title": title,
      "updated": NSNumber(value: 3600000 as Double) // ms
    ] as [String : Any]
    
    let guid = "c596b134310d499b13651fed64597de2c9931179"
    
    let entry = Entry(
      author: nil,
      enclosure: nil,
      duration: nil,
      feed: feed,
      feedTitle: nil,
      guid: guid,
      img: nil,
      link: nil,
      subtitle: nil,
      summary: nil,
      title: title,
      ts: nil,
      updated: updated
    )
    
    return (dict, entry)
  }

  func testEntryFromDictionary() {
    let (dict, wanted) = dictAndEntry()
    let found = try! entryFromDictionary(dict, podcast: false)
    XCTAssertEqual(found, wanted)
  }
  
  func testEntriesFromPayload() {
    var n = 0
    while n <= 1 {
      let (dict, entry) = dictAndEntry()
      let payload = [dict]
      let wanted = [entry]
      let podcast = n > 0
      let (errors, found) = entriesFromPayload(payload, podcast: podcast)
      if !podcast {
        XCTAssert(errors.isEmpty)
        XCTAssertEqual(found, wanted)
      } else {
        XCTAssert(!errors.isEmpty)
        XCTAssert(found.isEmpty)
      }
      n += 1
    }
  }

  func testEnclosureFromDictionary() {
    let f = enclosureFromDictionary
    do {
      let _ = try f([:])
      let _ = try f(["url": "http://serve.it/rad.mp3", "length": "123456"])
      let _ = try f(["type": "audio/mpeg", "length": "123456"])
      XCTFail("should throw")
    } catch {}
    let found = [
      try! f(["url": "abc", "type": "audio/mpeg"]),
      try! f(["url": "abc", "type": "audio/mpeg", "length": "123"])
    ]
    let wanted = [
      Enclosure(url: "abc", length: nil, type: .audioMPEG),
      Enclosure(url: "abc", length: 123, type: .audioMPEG)
    ]
    for (i, enc) in wanted.enumerated() {
      let it = found[i]!
      XCTAssertEqual(it, enc)
      XCTAssertEqual(it.url, enc.url)
      XCTAssertEqual(it.length, enc.length)
      XCTAssertEqual(it.type, enc.type)
    }
  }
}




