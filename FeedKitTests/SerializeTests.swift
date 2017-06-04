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

  func testTrimString() {
    func f(_ s: String) -> String {
      return replaceWhitespaces(in: s.lowercased(), with: " ")
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
    let k = "key"
    
    XCTAssertNil(date(fromDictionary: [k: -1], withKey: k))
    XCTAssertNil(date(fromDictionary: [k: -0], withKey: k))
    XCTAssertNotNil(date(fromDictionary: [k: 1], withKey: k))
    
    XCTAssertNil(date(fromDictionary: [String : AnyObject](), withKey: k))
    
    XCTAssertEqual(Date(timeIntervalSince1970: 1),
                   date(fromDictionary: [k: 1000], withKey: k)!)
  }

  func testFeedImagesFromDictionary() {
    let wanted = ITunesItem(guid: 123, img100: nil, img30: nil, img60: nil, img600: nil)!
    let dict = Mirror(reflecting: wanted).children.reduce([String : AnyObject]()) { acc, prop in
      var d = acc
      d[prop.label!] = prop.value as AnyObject
      return d
    }
    let found = iTunesItem(from: dict)!
    XCTAssertEqual(found, wanted)
    XCTAssertEqual(found.guid, wanted.guid)
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
        let _ = try feed(from: json as [String : AnyObject])
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
    let found = try! feed(from: dict)
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
    let (errors, feeds) = feedsFromPayload([dict])
    XCTAssert(errors.isEmpty)
    XCTAssertEqual(feeds, wanted)
  }
  
  fileprivate func dictAndEntry() -> ([String : Any], Entry) {
    let feed = "abc"
    let title = "Giant Robots"
    let updated = Date(timeIntervalSince1970: 3600)
    
    let dict = [
      "url": feed,
      "id": "c596b134310d499b13651fed64597de2c9931179",
      "title": title,
      "updated": NSNumber(value: 3600000 as Double) // ms
    ] as [String : Any]
    
    let guid = "c596b134310d499b13651fed64597de2c9931179"
    
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
      let found = try entryFromDictionary(dict, podcast: false)
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




