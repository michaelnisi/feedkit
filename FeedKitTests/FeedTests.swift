//
//  FeedTests.swift
//  FeedKit
//
//  Created by Michael Nisi on 22.07.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import XCTest
import FeedKit

class FeedTests: XCTestCase {
  
  func testInitializers () {
    let feed = Feed(title: "a", url: "b")
    XCTAssertEqual(feed.title, "a")
    XCTAssertEqual(feed.url, "b")
  }
  
  func testEquality () {
    let a = Feed(title: "a", url: "b")
    let b = Feed(title: "a", url: "b")
    XCTAssertEqual(a, b)
  }
}
