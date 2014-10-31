//
//  FanboyTests.swift
//  FeedKit
//
//  Created by Michael Nisi on 09.10.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import UIKit
import XCTest
import FeedKit

class FanboyTests: XCTestCase {
  var svc: FanboyService?

  override func setUp () {
    super.setUp()
    svc = FanboyService(host: "localhost", port: 8383)
    XCTAssertEqual(svc!.baseURL.absoluteString!, "http://localhost:8383")
  }

  override func tearDown () {
    svc = nil
    super.tearDown()
  }


  func testQueryURL () {
    let found = queryURL(svc!.baseURL, "search", "apple")!.absoluteString
    let wanted = "http://localhost:8383/search?q=apple"
    XCTAssertEqual(found!, wanted)
  }

  func testSearchResultFromValid () {
    let f = searchResultFrom
    let author = "Apple Inc."
    let feed = "http://www.apple.com/podcasts/filmmaker_uk/oliver/oliver.xml"
    let dict = [
      "author": author
    , "feed": feed
    ]
    let (er, result) = f(dict)
    XCTAssertNil(er)
    if let found = result {
      let wanted = SearchResult(
       author: author
        , cat: .Store
      , feed: NSURL(string: feed)!
      )
      XCTAssertEqual(found, wanted)
    } else {
      XCTAssert(false, "should have result")
    }
  }

  func testSearchResultFromInvalid () {
    let f = searchResultFrom
    let author = "Apple Inc."
    let dict = [
      "author": author
    ]
    let wanted = NSError(
      domain: domain
    , code: 1
    , userInfo: ["message":"missing fields (author or feed) in {\n    author = \"\(author)\";\n}"]
    )
    shouldError(f, dict, wanted)
  }

  func testSuggest () {
    let exp = self.expectationWithDescription("suggest")
    svc!.suggest("china") { er, res in
      XCTAssertNil(er)
      let wanted = [Suggestion(cat: .Store, term: "china")]
      XCTAssertEqual(res!, wanted)
      exp.fulfill()
    }
    self.waitForExpectationsWithTimeout(10) { er in
      XCTAssertNil(er)
    }
  }
}
