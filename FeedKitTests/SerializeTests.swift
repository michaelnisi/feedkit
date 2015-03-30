//
//  SerializeTests.swift
//  FeedKit
//
//  Created by Michael Nisi on 10.02.15.
//  Copyright (c) 2015 Michael Nisi. All rights reserved.
//

import XCTest

class SerializeTests: XCTestCase {
  override func setUp() {
    super.setUp()
  }

  override func tearDown() {
    super.tearDown()
  }

  func testTrimStringJoinedByString () {
    func trim (s: String) -> String {
      return trimString(s, joinedByString: "+")
    }
    let found = [
      "apple"
    , "apple watch"
    , "  apple  watch "
    , "  apple     watch kit  "
    , " "
    , ""
    ].map(trim)
    let wanted = [
      "apple"
    , "apple+watch"
    , "apple+watch"
    , "apple+watch+kit"
    , ""
    , ""
    ]
    XCTAssertEqual(found, wanted)
  }
}
