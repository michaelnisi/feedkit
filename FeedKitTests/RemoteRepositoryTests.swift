//
//  RemoteRepositoryTests.swift
//  FeedKitTests
//
//  Created by Michael Nisi on 30.04.18.
//  Copyright © 2018 Michael Nisi. All rights reserved.
//

import XCTest
import Ola

@testable import FeedKit

class RemoteRepositoryTests: XCTestCase {
  
  var repo: RemoteRepository!
  
  override func setUp() {
    super.setUp()
    let queue = OperationQueue()
    let probe = Ola(host: "localhost")!
    repo = RemoteRepository(queue: queue, probe: probe)
  }
  
  override func tearDown() {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    super.tearDown()
  }
  
  func testExample() {
    // This is an example of a functional test case.
    // Use XCTAssert and related functions to verify your tests produce the correct results.
  }
  
}
