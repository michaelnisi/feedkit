//
//  UserCacheTests.swift
//  FeedKit
//
//  Created by Michael Nisi on 01.07.17.
//  Copyright © 2017 Michael Nisi. All rights reserved.
//

import XCTest
@testable import FeedKit

final class UserCacheTests: XCTestCase {
  
  var cache: UserCache!
  
  override func setUp() {
    super.setUp()
    cache = freshUserCache(self.classForCoder)
    if let url = cache.url {
      XCTAssert(FileManager.default.fileExists(atPath: url.path))
    }
  }
  
  override func tearDown() {
    try! destroyCache(cache)
    super.tearDown()
  }
  
  lazy var locators: [EntryLocator] = {
    let now = TimeInterval(Int(Date().timeIntervalSince1970)) // rounded
    let since = Date(timeIntervalSince1970: now)
    let locators = [
      EntryLocator(url: "https://abc.de", since: since, guid: "123")
    ]
    return locators
  }()
  
  func testAddEntries() {
    try! cache.add(locators)
    
    let wanted = locators.map {
      Queued.entry($0, Date())
    }
    let found = try! cache.queued()
    XCTAssertEqual(found, wanted)
  }
  
  func testRemoveEntries() {
    try! cache.add(locators)
    
    do { // check if they‘ve actually been added
      let wanted = locators.map {
        Queued.entry($0, Date())
      }
      let found = try! cache.queued()
      XCTAssertEqual(found, wanted)
    }
    
    try! cache.remove(guids: ["123"])
    
    let found = try! cache.queued()
    XCTAssert(found.isEmpty)
  }
  
}
