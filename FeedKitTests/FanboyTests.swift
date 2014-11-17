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
    let baseURL = NSURL(string: "http://localhost:8383")!
    let conf = NSURLSessionConfiguration.defaultSessionConfiguration()
    svc = FanboyService(baseURL: baseURL, conf: conf)
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
  
  func testSuggestionsFromEmpty () {
    let (error, suggestions) = suggestionsFrom([])
    XCTAssertNil(error)
    XCTAssert(nil == suggestions)
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
    let (er, result) = f(dict)
    if let found = er {
      XCTAssertEqual(found, wanted)
    } else {
      XCTAssert(false, "should error")
    }
    XCTAssert(nil == result)
  }

  func testSuggest () {
    let svc = self.svc!
    let exp = self.expectationWithDescription("suggest")
    svc.suggest("china") { er, res in
      XCTAssertNil(er)
      let wanted = [Suggestion(cat: .Store, term: "china", ts: nil)]
      XCTAssertEqual(res!, wanted)
      exp.fulfill()
    }
    self.waitForExpectationsWithTimeout(10) { er in
      XCTAssertNil(er)
      // XCTAssertEqual(svc.handlers.count, 0)
    }
  }
  
  func testSuggestCancel () {
    let svc = self.svc!
    let exp = self.expectationWithDescription("suggest")
    let t = svc.suggest("china") { er, res in
      XCTAssertEqual(er!.code, -999) // "cancelled"
      XCTAssert(nil == res)
      exp.fulfill()
    }
    t?.cancel()
    self.waitForExpectationsWithTimeout(10) { er in
      XCTAssertNil(er)
      // XCTAssertEqual(svc.handlers.count, 0)
    }
  }
  
  func testSuggestSerial () {
    let svc = self.svc!
    let exp = self.expectationWithDescription("suggest")
    var i = 10
    var n = i
    while i-- > 0 {
      svc.suggest("china") { error, suggestions in
        XCTAssertNil(error)
        let wanted = [Suggestion(cat: .Store, term: "china", ts: nil)]
        XCTAssertEqual(suggestions!, wanted)
        if --n == 0 {
          exp.fulfill()
        }
      }
    }
    self.waitForExpectationsWithTimeout(10) { er in
      XCTAssertNil(er)
      // XCTAssertEqual(svc.handlers.count, 0)
    }
  }
}
