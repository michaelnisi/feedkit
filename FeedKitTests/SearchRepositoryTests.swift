//
//  SearchRepositoryTests.swift
//  FeedKit
//
//  Created by Michael Nisi on 03.11.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import FeedKit
import Skull
import XCTest

class SearchRepositoryTests: XCTestCase {
  struct Constants {
    static let URL = "http://127.0.0.1:8383"
  }
  
  var repo: SearchRepository!
  
  override func setUp () {
    super.setUp()
    
    let label = "\(domain).cache"
    let cacheQueue = dispatch_queue_create(label, DISPATCH_QUEUE_SERIAL)
    let db = Skull()
    let schema = schemaForClass(self.dynamicType)
    let ttl: NSTimeInterval = 3600
    let cache = Cache(
      db: db, queue: cacheQueue, rm: true, schema: schema, ttl: ttl)!
    
    let baseURL = NSURL(string: Constants.URL)!
    let conf = NSURLSessionConfiguration.defaultSessionConfiguration()
    let svc = FanboyService(baseURL: baseURL, conf: conf)
    
    let queue = NSOperationQueue()
    queue.name = "\(domain).search"
    repo = SearchRepository(cache: cache, queue: queue, svc: svc)
  }

  func testSearch () {
    let exp = self.expectationWithDescription("search")
    var found = [SearchItem]()
    repo.search("china") { error, items in
      println(items)
      XCTAssertNil(error)
      found += items
    }.completionBlock = {
      exp.fulfill()
    }
    self.waitForExpectationsWithTimeout(10) { er in
      XCTAssertNil(er)
      XCTAssertEqual(found.count, 50) // hearsay
    }
  }

  func testSuggest () {
    let exp = self.expectationWithDescription("suggest")
    var found = [SearchItem]()
    repo.suggest("china") { error, items in
      XCTAssertNil(error)
      found += items
      }.completionBlock = {
        exp.fulfill()
    }
    self.waitForExpectationsWithTimeout(10) { er in
      XCTAssertNil(er)
      XCTAssertEqual(found.count, 1)
      let first = found.first!
      switch first {
      case .Res(let result):
        XCTFail("should be suggestion")
      case .Sug(let suggestion):
        XCTAssertEqual(suggestion.term, "china")
        XCTAssertNil(suggestion.ts)
      }
    }
  }
}
