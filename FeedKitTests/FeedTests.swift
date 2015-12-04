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

  func testEquality () {
    let a = try! feedWithName("thetalkshow")
    let b = try! feedWithName("thetalkshow")
    XCTAssertEqual(a, b)
    let c = try! feedWithName("roderickontheline")
    XCTAssertNotEqual(b, c)
  }
}