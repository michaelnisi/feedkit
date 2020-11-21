//
//  SerializeTests.swift
//  FeedKit
//
//  Created by Michael Nisi on 10.02.15.
//  Copyright (c) 2015 Michael Nisi. All rights reserved.
//

import XCTest
@testable import FeedKit

final class SerializeTests: XCTestCase {
  
  func testLowercasedURL() {
    let found = [
      lowercasedURL(string: "http://ABC.DE/hello"),
      lowercasedURL(string: "http://ABC.DE/HELLO")
    ]
    let wanted = [
      "http://abc.de/hello",
      "http://abc.de/HELLO"
    ]
    for (i, str) in wanted.enumerated() {
      XCTAssertEqual(found[i], str)
    }
  }

  func testTimeIntervalFromJS() {
    let found = [
      serialize.timeIntervalFromJS(-1000),
      serialize.timeIntervalFromJS(0),
      serialize.timeIntervalFromJS(1000)
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
    let k = "key"
    
    XCTAssertNil(serialize.date(from: [k: -1], forKey: k))
    XCTAssertNil(serialize.date(from: [k: -0], forKey: k))
    XCTAssertNil(serialize.date(from: [k: 1], forKey: k))
    XCTAssertNil(serialize.date(from: [String : AnyObject](), forKey: k))
    XCTAssertNil(serialize.date(from: [k: 1000], forKey: k))
    
    let found = Date(timeIntervalSince1970: serialize.watershed).description
    XCTAssertEqual(found, "1990-01-01 00:00:00 +0000")
    
    XCTAssertNil(serialize.date(from: [k: serialize.watershed], forKey: k))
    
    let newer = serialize.watershed * 1000 + 1
    XCTAssertNotNil(serialize.date(from: [k: newer], forKey: k))
  }

  func testFeedImagesFromDictionary() {
    let dict: [String : Any] = [
      "guid": 123,
      "img100": "abc",
      "img30": "def",
      "img60": "ghi",
      "img600": "jkl"
    ]
    
    let found = serialize.makeITunesItem(url: "http://abc.de", payload: dict)!
    
    let wanted = ITunesItem(
      url: "http://abc.de",
      iTunesID: 123,
      img100: "abc",
      img30: "def",
      img60: "ghi",
      img600: "jkl"
    )
    
    XCTAssertEqual(found, wanted)
    XCTAssertEqual(found.iTunesID, wanted.iTunesID)
    XCTAssertEqual(found.img100, wanted.img100)
    XCTAssertEqual(found.img30, wanted.img30)
    XCTAssertEqual(found.img60, wanted.img60)
    XCTAssertEqual(found.img600, wanted.img600)
  }

  func testFeedFromInvalidDictonaries() {
    let things: [([String : Any], String)] = [
      ([String : Any](), "feed missing"),
      (["feed": "http://abc.de"], "title missing: http://abc.de")
    ]
    things.forEach {
      let (json, wanted) = $0
      var ok = false
      do {
        let _ = try serialize.feed(from: json as [String : AnyObject])
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
    let dict = ["feed": "http://abc.DE/hellO", "title": "A title"]
    let wanted = Feed(
      author: nil,
      iTunes: nil,
      image: nil,
      link: nil,
      originalURL: nil,
      summary: nil,
      title: "A title",
      ts: nil,
      uid: nil,
      updated: nil,
      url: "http://abc.de/hellO"
    )
    let found = try! serialize.feed(from: dict)
    XCTAssertEqual(found, wanted)
  }
  
  func testFeedsFromPayload() {
    let dict = ["feed": "http://abc.de", "title": "A title"]
    let wanted = [Feed(
      author: nil,
      iTunes: nil,
      image: nil,
      link: nil,
      originalURL: nil,
      summary: nil,
      title: "A title",
      ts: nil,
      uid: nil,
      updated: nil,
      url: "http://abc.de"
    )]
    let payload = [dict, dict]
    let (errors, feeds) = serialize.feeds(from: payload)
    XCTAssert(errors.isEmpty)
    XCTAssertEqual(feeds, wanted)
  }
  
  fileprivate func dictAndEntry() -> ([String : Any], Entry) {
    let feed = "abc"
    let title = "Giant Robots"
    let updated = Date(timeIntervalSince1970: 3600)
    let guid = "123"
    
    let dict = [
      "url": feed,
      "id": guid,
      "title": title,
      "updated": NSNumber(value: 3600000 as Double) // ms
    ] as [String : Any]
    
    let entry = Entry(
      author: nil,
      duration: nil,
      enclosure: nil,
      feed: feed,
      feedImage: nil,
      feedTitle: nil,
      guid: guid,
      iTunes: nil,
      image: nil,
      link: nil,
      originalURL: nil,
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
    do {
      let found = try serialize.entry(from: dict, podcast: false)
      XCTAssertEqual(found, wanted)
    } catch {
      XCTFail("should not throw")
    }
  }
  
  func testEntriesFromPayload() {
    var n = 0
    while n <= 1 {
      let (dict, entry) = dictAndEntry()
      let payload = [dict]
      let wanted = [entry]
      let podcast = n > 0
      let (errors, found) = serialize.entries(from: payload, podcast: podcast)
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
    func f(_ json: [String : Any]) throws -> Enclosure? { // lazyiness
      return try serialize.enclosure(from: json)
    }
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




