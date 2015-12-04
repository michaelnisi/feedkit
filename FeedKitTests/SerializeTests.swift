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
      return trimString(s, joinedByString: "+")
    }
    let input = [
      "apple",
      "apple watch",
      "  apple  watch ",
      "  apple     watch kit  ",
      " ",
      ""
    ]
    let wanted = [
      "apple",
      "apple+watch",
      "apple+watch",
      "apple+watch+kit",
      "",
      ""
    ]
    for (n, it) in wanted.enumerate() {
      XCTAssertEqual(it, f(input[n]))
    }
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

  func testQueryFromString () {
    XCTAssertNil(queryFromString(""))
    XCTAssertNil(queryFromString(" "))
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




