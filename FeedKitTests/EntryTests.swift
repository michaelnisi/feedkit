//
//  EntryTests.swift
//  FeedKit
//
//  Created by Michael Nisi on 25.09.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import UIKit
import XCTest

import FeedKit

class EntryTests: XCTestCase {
  
  func entry (_ updated: Double = 0) -> Entry {
    let enclosure = Enclosure(
      href: NSURL(string:"http://cdn.abc.tv")!
    , length: 123
    , type: "audio/mpeg"
    )
    return Entry(
      author: "John Doe"
    , enclosure: enclosure
    , duration: 1000
    , id: "abc"
    , image: "def"
    , link: NSURL(string:"ghi")
    , subtitle: "lmn"
    , summary: "opq"
    , title: "rst"
    , updated: updated
    )
  }
  
  func testEquality () {
    let a = entry()
    let b = entry(1)
    XCTAssertNotEqual(a, b)
    let c = entry(0)
    XCTAssertEqual(a, c)
  }
}
