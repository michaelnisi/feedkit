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
  
  func testFeedFrom () {
    let a = ["title":"a"]
    let aa = feedFrom(a)
    XCTAssert(aa == nil)
    
    let b = ["title":"a", "feed":"b"]
    let bb = feedFrom(b)
    XCTAssert(bb != nil)
  }
  
  func testFeedsFrom () {
    XCTAssertEqual(feedsFrom([]).count, 0)
    XCTAssertEqual(feedsFrom([["title":"a"]]).count, 0)
    XCTAssertEqual(feedsFrom([["title":"a", "feed":"b"]]).count, 1)
  }
}

