//
//  SearchRepositoryTests.swift
//  FeedKit
//
//  Created by Michael Nisi on 03.11.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import UIKit
import XCTest
import FeedKit

class SearchRepositoryTests: XCTestCase {
  var repo: SearchRepository?

  func svc () -> FanboyService {
    let queue = NSOperationQueue()
    queue.name = "\(domain).fanboy"
    return FanboyService(host: "localhost", port: 8383, queue: queue)
  }

  override func setUp () {
    super.setUp()
    let queue = NSOperationQueue()
    queue.name = "\(domain).search"
    let cache = Cache() // TODO: Not sure if like this opaque initializer.
    repo = SearchRepository(queue: queue, svc: svc(), cache: cache)
  }

  override func tearDown () {
    repo = nil
    super.tearDown()
  }

  func testSuggest () {
    let exp = self.expectationWithDescription("suggest")
    repo?.suggest("china", cb: { (error, found) -> Void in
      XCTAssertNil(error)
      let wanted = [Suggestion(cat: .Store, term: "china")]
      XCTAssertEqual(found!, wanted)
    }, end: { error -> Void in
      XCTAssertNil(error)
      exp.fulfill()
    })
    self.waitForExpectationsWithTimeout(10) { er in
      XCTAssertNil(er)
    }
  }
}
