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
    //
  }
  
  override func tearDown() {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    super.tearDown()
  }
  
  func testOfflineServiceIdea() {
    let ideas = [
      RemoteRepository.ServiceIdea(
        reachability: .unknown, expecting: .forever),
      RemoteRepository.ServiceIdea(
        reachability: .unknown, expecting: .long),
      RemoteRepository.ServiceIdea(
        reachability: .unknown, expecting: .medium),
      RemoteRepository.ServiceIdea(
        reachability: .unknown, expecting: .none),
      RemoteRepository.ServiceIdea(
        reachability: .unknown, expecting: .short)
    ]
    for idea in ideas {
      XCTAssertFalse(idea.isAvailable)
      XCTAssertTrue(idea.isOffline)
      XCTAssertEqual(idea.ttl, .forever)
    }
  }
  
  func testOnlineServiceIdea() {
    let ttls: [CacheTTL] = [.forever, .long, .medium, .none, .short]
    let statuses: [OlaStatus] = [.reachable, .cellular]
    for status in statuses {
      for ttl in ttls {
        let idea = RemoteRepository.ServiceIdea(reachability: status, expecting: ttl)
        XCTAssertEqual(idea.ttl, ttl)
        XCTAssertFalse(idea.isOffline)
        XCTAssertTrue(idea.isAvailable)
      }
    }
  }
  
}
