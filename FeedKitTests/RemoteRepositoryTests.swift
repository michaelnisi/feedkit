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
  
  func testStigmatizedServiceIdea() {
    let ttls: [CacheTTL] = [.forever, .long, .medium, .none, .short]
    let statuses: [OlaStatus] = [.reachable, .cellular]
    for status in statuses {
      for ttl in ttls {
        let idea = RemoteRepository.ServiceIdea(
          reachability: status,
          expecting: ttl,
          status:  (-1000, Date().timeIntervalSince1970 - 299)
        )
        XCTAssertEqual(idea.ttl, .forever)
        XCTAssertFalse(idea.isOffline)
        XCTAssertFalse(idea.isAvailable)
      }
    }
  }
  
  func testStigmatizedOfflineServiceIdea() {
    let ttls: [CacheTTL] = [.forever, .long, .medium, .none, .short]
    let statuses: [OlaStatus] = [.unknown]
    for status in statuses {
      for ttl in ttls {
        let idea = RemoteRepository.ServiceIdea(
          reachability: status,
          expecting: ttl,
          status:  (-1000, Date().timeIntervalSince1970 - 299)
        )
        XCTAssertEqual(idea.ttl, .forever)
        XCTAssertTrue(idea.isOffline)
        XCTAssertFalse(idea.isAvailable)
      }
    }
  }
  
  func testAcquittedServiceIdea() {
    let ttls: [CacheTTL] = [.forever, .long, .medium, .none, .short]
    let statuses: [OlaStatus] = [.reachable, .cellular]
    for status in statuses {
      for ttl in ttls {
        let idea = RemoteRepository.ServiceIdea(
          reachability: status,
          expecting: ttl,
          status:  (-1000, Date().timeIntervalSince1970 - 300)
        )
        XCTAssertEqual(idea.ttl, ttl)
        XCTAssertFalse(idea.isOffline)
        XCTAssertTrue(idea.isAvailable)
      }
    }
  }
  
  func testAcquittedOfflineServiceIdea() {
    let ttls: [CacheTTL] = [.forever, .long, .medium, .none, .short]
    let statuses: [OlaStatus] = [.unknown]
    for status in statuses {
      for ttl in ttls {
        let idea = RemoteRepository.ServiceIdea(
          reachability: status,
          expecting: ttl,
          status:  (-1000, Date().timeIntervalSince1970 - 300)
        )
        XCTAssertEqual(idea.ttl, .forever)
        XCTAssertTrue(idea.isOffline)
        XCTAssertFalse(idea.isAvailable)
      }
    }
  }
  
}
