//
//  SearchTests.swift
//  FeedKit
//
//  Created by Michael Nisi on 04.03.15.
//  Copyright (c) 2015 Michael Nisi. All rights reserved.
//

@testable import FeedKit
import XCTest

class  SearchTests: XCTestCase {

  func testSuggestion () {
    let a = Suggestion(term: "abc", ts: nil)
    let b = Suggestion(term: "abc", ts: nil)
    XCTAssertEqual(a, b)
    XCTAssertEqual(SearchItem.Sug(a), SearchItem.Sug(b))
  }

  func testReduceSuggestions () {
    let a = Suggestion(term: "abc", ts: nil)
    XCTAssertEqual(reduceSuggestions([a], b: nil)!, [SearchItem.Sug(a)])
    XCTAssertEqual(reduceSuggestions([a], b: [])!, [SearchItem.Sug(a)])
    let b = Suggestion(term: "abc", ts: nil)
    XCTAssertEqual(reduceSuggestions([a], b: [b])!, [])
    let c = Suggestion(term: "ghi", ts: nil)
    XCTAssertEqual(reduceSuggestions([c], b: [a])!.first!, SearchItem.Sug(c))
    XCTAssertEqual(reduceSuggestions([c], b: [a])!.count, 1)
    XCTAssert(reduceSuggestions([c], b: [a, a, a, a, a]) == nil)

    _ = Suggestion(term: "jkl", ts: nil)
    let e = Suggestion(term: "mno", ts: nil)
    let f = Suggestion(term: "pqr", ts: nil)
    let g = Suggestion(term: "stu", ts: nil)
    let sugs = [a, b, c, e, f, g]
    if let items = reduceSuggestions(sugs, b: nil) {
      XCTAssertEqual(items.count, sugs.count - 1)
      let wanted = sugs.map { SearchItem.Sug($0) }
      for (i, item) in items.enumerate() {
        XCTAssertEqual(item, wanted[i])
      }
    } else {
      XCTFail("should yield items")
    }
  }
}
