//
//  SuggestionTest.swift
//  FeedKit
//
//  Created by Michael Nisi on 15.11.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import XCTest
import FeedKit

class SuggestionTest: XCTestCase {
  override func setUp () {
   super.setUp()
  }

  override func tearDown () {
    super.tearDown()
  }

  func testStale () {
    let a = Suggestion(cat: .Store, term: "apple", ts: nil)
    XCTAssertFalse(a.stale(0))
    let b = Suggestion(cat: .Store, term: "apple", ts: NSDate())
    XCTAssert(b.stale(0))
  }
}
