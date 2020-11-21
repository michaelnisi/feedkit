//
//  HashTests.swift
//  FeedKitTests
//
//  Created by Michael on 10/17/17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import XCTest
@testable import FeedKit

class HashTests: XCTestCase {

  func testDjb2Hash32() {
    for _ in 0..<5 { XCTAssertEqual(djb2Hash32(string: ""), 5381) }
    for _ in 0..<5 { XCTAssertEqual(djb2Hash32(string: "abc"), 193485963) }
    for _ in 0..<5 { XCTAssertEqual(djb2Hash32(string: "cba"), 193488139) }
    for _ in 0..<5 { XCTAssertEqual(djb2Hash32(string: "/var/folders/7y/05zkq_bd0lbdfsszjxy2t4600000gn/T/com.apple.dt.XCTest/IDETestRunSession-7D269FB6-77C3-4546-90A9-27EE92A1B3C7/FeedKitTests-55402F23-E986-4614-8429-2BBCFF745535/Session-FeedKitTests-2017-10-17_120730-gAlTfb.lo"), 314931176) }
    for _ in 0..<5 { XCTAssertEqual(djb2Hash32(string: "/var/folders/7y/05zkq_bd0lbdfsszjxy2t4600000gn/T/com.apple.dt.XCTest/IDETestRunSession-7D269FB6-77C3-4546-90A9-27EE92A1B3C7/FeedKitTests-55402F23-E986-4614-8429-2BBCFF745535/Session-FeedKitTests-2017-10-17_120730-gAlTfc.lo"), 314967113) }
  }

}
