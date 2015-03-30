//
//  FanboyTests.swift
//  FeedKit
//
//  Created by Michael Nisi on 09.10.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import FeedKit
import UIKit
import XCTest

class FanboyTests: XCTestCase {
  struct Constants {
    static let URL = "http://127.0.0.1:8383"
    // static let URL = "https://10.0.1.24"
    static let SECRET = "beep"
  }
  var svc: FanboyService?

  override func setUp () {
    super.setUp()
    let conf = NSURLSessionConfiguration.defaultSessionConfiguration()
    conf.HTTPAdditionalHeaders = ["secret": Constants.SECRET]
    let baseURL = NSURL(string: Constants.URL)!
    svc = FanboyService(baseURL: baseURL, conf: conf)
    let bundle = NSBundle(forClass: self.dynamicType)
    let url = bundle.URLForResource("local", withExtension: "der")!
    svc!.addCertificateAtURL(url)
  }

  override func tearDown () {
    svc = nil
    super.tearDown()
  }

  func testQueryFromString () {
    XCTAssertNil(queryFromString(""))
    XCTAssertNil(queryFromString(" "))
  }

  func testQueryURL () {
    func t (term: String) -> String {
      if let url = queryURL(svc!.baseURL, "search", term) {
        return url.absoluteString!
      }
      return "invalid URL"
    }
    let found = ["apple", "apple watch"].map(t)
    let wanted = [
      "\(Constants.URL)/search?q=apple"
    , "\(Constants.URL)/search?q=apple+watch"
    ]
    XCTAssertEqual(found, wanted)
  }

  func testSuggestionsFromEmpty () {
    let (error, suggestions) = suggestionsFrom([])
    XCTAssertNil(error)
    XCTAssert(nil == suggestions)
  }

  func testSearchResultFromValid () {
    let f = searchResultFromDictionary
    let author = "Apple Inc."
    let feed = "http://www.apple.com/podcasts/filmmaker_uk/oliver/oliver.xml"
    let guid = 763718821
    let img100 = "http://a4.mzstatic.com"
    let img30 = "http://a4.mzstatic.com"
    let img60 = "http://a4.mzstatic.com"
    let img600 = "http://a4.mzstatic.com"
    let title = "Meet the Chef: Jamie Oliver"
    let ts: NSTimeInterval = 1423561670666
    let updated: NSTimeInterval = 1385122020000

    let dict: [String:AnyObject] = [
      "author": author
    , "feed": feed
    , "guid": guid
    , "img100": img100
    , "img30": img30
    , "img60": img60
    , "img600": img600
    , "title": title
    , "ts": ts
    , "updated": updated
    ]
    let (er, result) = f(dict)

    let images = ITunesImages(
      img100: img100
    , img30: img30
    , img600: img600
    , img60: img60
    )

    let updatedDate = NSDate(timeIntervalSince1970: updated)
    let tsDate = NSDate(timeIntervalSince1970: ts)
    XCTAssertNil(er)
    if let found = result {
      let wanted = SearchResult(
        author: author
      , feed: feed
      , guid: guid
      , images: images
      , title: title
      , ts: nil
      )
      XCTAssertEqual(found, wanted)
    } else {
      XCTAssert(false, "should have result")
    }
  }

  func testSearchResultFromInvalid () {
    let f = searchResultFromDictionary
    let author = "Apple Inc."
    let dict = [
      "author": author
    ]
    let wanted = NSError(
      domain: domain
    , code: 1
    , userInfo: ["message":"missing fields in [author: \(author)]"]
    )
    let (er, result) = f(dict)
    if let found = er {
      XCTAssertEqual(found, wanted)
    } else {
      XCTAssert(false, "should error")
    }
    XCTAssert(nil == result)
  }
  
  func testSearchResultPerf () {
    let author = "Apple Inc."
    let feed = "http://www.apple.com/podcasts/filmmaker_uk/oliver/oliver.xml"
    let guid = 763718821
    let img100 = "http://a4.mzstatic.com"
    let img30 = "http://a4.mzstatic.com"
    let img60 = "http://a4.mzstatic.com"
    let img600 = "http://a4.mzstatic.com"
    let title = "Meet the Chef: Jamie Oliver"
    let ts: NSTimeInterval = 1423561670666
    let updated: NSTimeInterval = 1385122020000
    
    let dict: [String:AnyObject] = [
      "author": author
      , "feed": feed
      , "guid": guid
      , "img100": img100
      , "img30": img30
      , "img60": img60
      , "img600": img600
      , "title": title
      , "ts": ts
      , "updated": updated
    ]
    
    self.measureBlock() {
      let (er, result) = searchResultFromDictionary(dict)
    }
  }

  func testSearch () {
    let svc = self.svc!
    let exp = self.expectationWithDescription("search")
    svc.search("china") { error, searchResults in
      XCTAssertNil(error)
      XCTAssertEqual(searchResults!.count, 50) // speculation
      exp.fulfill()
    }
    self.waitForExpectationsWithTimeout(10) { er in
      XCTAssertNil(er)
    }
  }

  func testSearchCancel () {
    let svc = self.svc!
    let exp = self.expectationWithDescription("search")
    svc.search("china") { er, res in
      XCTAssertEqual(er!.code, -999) // "cancelled"
      XCTAssert(nil == res)
      exp.fulfill()
    }?.cancel()
    self.waitForExpectationsWithTimeout(10) { er in
      XCTAssertNil(er)
    }
  }

  func testSuggest () {
    let svc = self.svc!
    let exp = self.expectationWithDescription("suggest")
    svc.suggest("china") { er, res in
      XCTAssertNil(er)
      let wanted = [Suggestion(term: "china", ts: nil)]
      XCTAssertEqual(res!, wanted)
      exp.fulfill()
    }
    self.waitForExpectationsWithTimeout(10) { er in
      XCTAssertNil(er)
    }
  }

  func testSuggestCancel () {
    let svc = self.svc!
    let exp = self.expectationWithDescription("suggest")
    svc.suggest("china") { er, res in
      XCTAssertEqual(er!.code, -999) // "cancelled"
      XCTAssert(nil == res)
      exp.fulfill()
    }?.cancel()
    self.waitForExpectationsWithTimeout(10) { er in
      XCTAssertNil(er)
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
        let wanted = [Suggestion(term: "china", ts: nil)]
        XCTAssertEqual(suggestions!, wanted)
        if --n == 0 {
          exp.fulfill()
        }
      }
    }
    self.waitForExpectationsWithTimeout(10) { er in
      XCTAssertNil(er)
    }
  }

  func testHandlers () {
    XCTAssertEqual(svc!.handlers.count, 0)
  }
}
