//
//  FeedKitTests.swift
//  FeedKitTests
//
//  Created by Michael Nisi on 17.07.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import UIKit
import XCTest
import FeedKit

class FeedKitTests: XCTestCase {
  func testFeed () {
    func nilFeed () -> Feed {
      return Feed(author: "", image: "", language: "", link: "", summary: "", title: "", updated: "")
    }
    let found: [Feed?] = [
      feed(Dictionary<String, AnyObject>())
    , feed(["author":-1, "title":"abc"])
    , feed(["title":"def", "image":true])
    , feed(["author":"a", "image":"b", "language":"c", "link":"d", "summary":"e", "title":"f", "updated":"g"])
    ]
    var count = 0
    for (i, wanted: Feed) in enumerate([
      nilFeed()
    , nilFeed()
    , nilFeed()
    , Feed(author: "a", image: "b", language: "c", link: "d", summary: "e", title: "f", updated: "g")
      ]) {
        if let f = found[i] {
          XCTAssertEqual(f, wanted)
          count++
        }
    }
    XCTAssertEqual(count, 1)
  }
}
