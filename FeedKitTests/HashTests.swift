//
//  HashTests.swift
//  FeedKit
//
//  Created by Michael on 9/5/17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import XCTest
@testable import FeedKit


class HashTests: XCTestCase {
  
  override func setUp() {
    super.setUp()
    // Put setup code here. This method is called before the invocation of each test method in the class.
  }
  
  override func tearDown() {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    super.tearDown()
  }
  
  func testDjb2HashPerformance() {
    self.measure {
      let url = "http://daringfireball.net/thetalkshow/rss"
      for _ in 0...1000 {
        let h = djb2Hash(string: url)
        XCTAssertEqual(h, -1126244948)
        

      }
    }
  }
  
}
