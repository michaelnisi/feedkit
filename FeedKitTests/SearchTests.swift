//
//  SearchTests.swift
//  FeedKit
//
//  Created by Michael Nisi on 04.03.15.
//  Copyright (c) 2015 Michael Nisi. All rights reserved.
//

import FeedKit
import XCTest

class  SearchTests: XCTestCase {

  func testSuggestion () {
    let a = Suggestion(term: "abc", ts: nil)
    let b = Suggestion(term: "abc", ts: nil)
    XCTAssertEqual(a, b)
    XCTAssertEqual(SearchItem.Sug(a), SearchItem.Sug(b))
  }

  func testSearchResult () {
    let feed = NSURL(string: "http://apple.com")!
    let a = SearchResult(
      author: "Apple Inc."
    , feed: feed
    , guid: 123
    , images: nil
    , title: "The title"
    , ts: nil
    )
    let b = SearchResult(
      author: "Apple Inc."
    , feed: feed
    , guid: 123
    , images: nil
    , title: "The title"
    , ts: nil
    )
    XCTAssertEqual(a, b)
    XCTAssertEqual(SearchItem.Res(a), SearchItem.Res(b))
  }

  func testReduceSuggestions () {
    let a = Suggestion(term: "abc", ts: nil)
    XCTAssertEqual(reduceSuggestions([a], nil)!, [SearchItem.Sug(a)])
    XCTAssertEqual(reduceSuggestions([a], [])!, [SearchItem.Sug(a)])
    let b = Suggestion(term: "abc", ts: nil)
    XCTAssertEqual(reduceSuggestions([a], [b])!, [])
    let c = Suggestion(term: "ghi", ts: nil)
    XCTAssertEqual(reduceSuggestions([c], [a])!.first!, SearchItem.Sug(c))
    XCTAssertEqual(reduceSuggestions([c], [a])!.count, 1)
    XCTAssert(reduceSuggestions([c], [a, a, a, a, a]) == nil)

    let d = Suggestion(term: "jkl", ts: nil)
    let e = Suggestion(term: "mno", ts: nil)
    let f = Suggestion(term: "pqr", ts: nil)
    let g = Suggestion(term: "stu", ts: nil)
    let sugs = [a, b, c, e, f, g]
    if let items = reduceSuggestions(sugs, nil) {
      XCTAssertEqual(items.count, sugs.count - 1)
      let wanted = sugs.map { SearchItem.Sug($0) }
      for (i, item) in enumerate(items) {
        XCTAssertEqual(item, wanted[i])
      }
    } else {
      XCTFail("should yield items")
    }
  }

  func testReduceSearchResults () {
    let a = SearchResult(
      author: "abc"
    , feed: NSURL(string: "http://apple.com")!
    , guid: 123
    , images: nil
    , title: "def"
    , ts: NSDate())
    XCTAssertEqual(reduceResults([a], nil)!, [SearchItem.Res(a)])
    XCTAssertEqual(reduceResults([a], [])!, [SearchItem.Res(a)])
    // Should be covered by `testReduceSuggestions`.
  }
}
