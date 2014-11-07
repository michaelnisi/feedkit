//
//  CacheTests.swift
//  FeedKit
//
//  Created by Michael Nisi on 02.11.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import UIKit
import XCTest
import FeedKit

class CacheTests: XCTestCase {
  var cache: Cache?

  override func setUp() {
    super.setUp()
    cache = Cache()
  }

  override func tearDown() {
    cache = nil
    super.tearDown()
  }

  func testSuggestions () {
    XCTAssertNotNil(cache?.addSuggestions([]), "should error when empty")

    let terms = ["apple", "google", "samsung"]
    let input = terms.map({ term in
      Suggestion(cat: .Store, term: term)
    })
    let er = cache?.addSuggestions(input)
    XCTAssertNil(er)
    XCTAssertNil(cache?.addSuggestions(input), "should replace")
    let (error, suggestions) = cache!.suggestionsForTerm("a")
    if let output = suggestions {
      XCTAssertEqual(output.count, 1)
      let found: Suggestion = output.first!
      let wanted: Suggestion = input.first!
      XCTAssertEqual(found, wanted)
    } else {
      XCTFail("should find suggestions")
    }
  }
}
