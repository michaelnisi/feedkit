//
//  TransformTests.swift
//  FeedKit
//
//  Created by Michael Nisi on 25.09.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import UIKit
import XCTest
import FeedKit

class TransformTests: XCTestCase {
  typealias AnyFrom = NSDictionary -> (NSError?, AnyObject?)
  func shouldError (from: AnyFrom, dict: NSDictionary, wanted: NSError) {
    let (er, result: AnyObject?) = from(dict)
    if let found = er {
      XCTAssertEqual(found, wanted)
    } else {
      XCTAssert(false, "should error")
    }
    XCTAssertNil(result)
  }

  func testFeedFromValid () {
    let dict = ["title":"a", "feed":"b"]
    let (er, feed) = feedFrom(dict)
    XCTAssertNil(er)
    if let found = feed {
      let wanted = Feed(
        author: nil
      , image: nil
      , language: nil
      , link: nil
      , summary: nil
      , title: "a"
      , updated: 0.0
      , url: NSURL(string:"http://some.io/rss")
      )
      XCTAssertEqual(found, wanted)
    } else {
      XCTAssert(false, "should have feed")
    }
  }

  func testFeedFromInvalid () {
    let dict = ["title":"invalid"]
    let wanted = NSError(
      domain: "FeedKit.manger"
    , code: 1
    , userInfo: ["message":"missing fields (title or feed) in {\n    title = invalid;\n}"]
    )
    shouldError(feedFrom, dict: dict, wanted: wanted)
  }

  func testEnclosureFromInvalid () {
    let dict = ["href":"href"]
    let wanted = NSError(
      domain: "FeedKit.manger"
    , code: 1
    , userInfo: ["message":"missing fields (url, length, or type) in {\n    href = href;\n}"]
    )
    shouldError(enclosureFrom, dict: dict, wanted: wanted)
  }

  func testEnclosureFromValid () {
    let dict = [
      "url":"http://cdn.io/some.mp3"
    , "length":"100"
    , "type":"audio/mpeg"
    ]
    let (er, enclosure) = enclosureFrom(dict)
    XCTAssertNil(er)
    if let found = enclosure {
      let wanted = Enclosure(
        href: NSURL(string:"http://cdn.io/some.mp3")
      , length: 100
      , type: "audio/mpeg"
      )
      XCTAssertEqual(found, wanted)
    } else {
      XCTAssert(false, "should have enclosure")
    }
  }

  func testEntryFromInvalid () {
    let dict = ["title":"a"]
    let wanted = NSError(
      domain: "FeedKit.manger"
    , code: 1
    , userInfo: ["message":"missing fields (title or enclosure) in {\n    title = a;\n}"]
    )
    shouldError(entryFrom, dict: dict, wanted: wanted)
  }
}

