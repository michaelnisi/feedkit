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

  func feed (_ updated: Double = 1411930683000) -> Feed {
    return Feed(
      author: "Daring Fireball / John Gruber"
    , image: "http://daringfireball.net/thetalkshow/graphics/cover-1400.jpg"
    , language: "en"
    , link: NSURL(string: "http://feeds.muleradio.net/thetalkshow")
    , summary: "The director’s commentary track for Daring Fireball."
    , title: "The Talk Show With John Gruber"
    , updated: updated
    , url: NSURL(string: "http://feeds.muleradio.net/thetalkshow")!
    )
  }

  func testEquality () {
    let a = feed()
    let b = feed(1411930683001)
    XCTAssertNotEqual(a, b)
    let c = feed()
    XCTAssertEqual(a, c)
  }
}
