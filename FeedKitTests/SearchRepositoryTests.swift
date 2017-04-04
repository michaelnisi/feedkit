//
//  SearchRepositoryTests.swift
//  FeedKit
//
//  Created by Michael Nisi on 17/12/15.
//  Copyright © 2015 Michael Nisi. All rights reserved.
//

import XCTest
import FanboyKit
import Ola
import Patron

@testable import FeedKit

private func freshFanboy(url: URL, target: DispatchQueue) -> Fanboy {
  let conf = URLSessionConfiguration.default
  conf.httpShouldUsePipelining = true
  conf.requestCachePolicy = .reloadIgnoringLocalCacheData
  let session = URLSession(configuration: conf)

  let client = Patron(URL: url, session: session, target: target)
  
  return Fanboy(client: client)
}

class SearchRepositoryTests: XCTestCase {
  var repo: Searching!
  var cache: Cache!
  var svc: Fanboy!
  
  // TODO: Mock remote service
  
  override func setUp() {
    super.setUp()
    
    let url = URL(string: "http://localhost:8383")!
    let target = DispatchQueue(
      label: "ink.codes.fanboy.json",
      attributes: DispatchQueue.Attributes.concurrent
    )
    svc = freshFanboy(url: url, target: target)
    
    cache = freshCache(self.classForCoder)
    let queue = OperationQueue()
    // TODO: Determine optimal queue for Ola
    let probe = Ola(host: "localhost", queue: target)!
    
    repo = SearchRepository(cache: cache, svc: svc, queue: queue, probe: probe)
  }
  
  override func tearDown() {
    try! destroyCache(cache)
    super.tearDown()
  }
  
  // MARK: Search
  
  func testSearch() {
    let exp = self.expectation(description: "search")
    func go(_ done: Bool = false) {
      repo.search("john   gruber", perFindGroupBlock: { error, finds in
        XCTAssertNil(error)
        XCTAssert(finds.count > 0)
        if !done {
          for find in finds {
            XCTAssertNil(find.ts)
          }
        }
      }) { error in
        XCTAssertNil(error)
        if done {
          DispatchQueue.main.async() {
            exp.fulfill()
          }
        } else {
          DispatchQueue.main.async() {
            go(true)
          }
        }
      }
    }
    go()
    self.waitForExpectations(timeout: 61) { er in
      XCTAssertNil(er)
    }
  }
  
  func testSearchWithNoResult() {
    let exp = self.expectation(description: "search")
    func go(_ terms: [String]) {
      guard !terms.isEmpty else {
        return DispatchQueue.main.async {
          exp.fulfill()
        }
      }
      var t = terms
      let term = t.removeFirst()
      repo.search(term, perFindGroupBlock: { error, finds in
        XCTAssertNil(error)
        XCTAssertEqual(finds.count, 0)
      }) { error in
        XCTAssertNil(error)
        DispatchQueue.main.async() {
          go(t)
        }
      }
    }
    // Mere speculation that these return no results from iTunes.
    go(["0", "0a", "0", "0a"])
    self.waitForExpectations(timeout: 61) { er in
      XCTAssertNil(er)
    }
  }
  
  func testSearchConcurrently() {
    let exp = self.expectation(description: "search")
    let repo = self.repo!
    let terms = ["apple", "gruber", "newyorker", "nyt", "literature"]
    var count = terms.count

    let q = DispatchQueue.global(qos: .userInitiated)
    
    for term in terms {
      q.async {
        repo.search(term, perFindGroupBlock: { er, finds in
          XCTAssertNil(er)
          XCTAssertNotNil(finds)
        }) { error in
          XCTAssertNil(error)
          DispatchQueue.main.async() {
            count -= 1
            if count == 0 {
              exp.fulfill()
            }
          }
        }
      }
    }
    self.waitForExpectations(timeout: 61) { er in
      XCTAssertNil(er)
    }
  }
  
  func testSearchCancel() {
    let exp = self.expectation(description: "search")
    let op = repo.search("apple", perFindGroupBlock: { er, finds in
      XCTFail("should not get dispatched")
    }) { error in
      XCTAssertEqual(error as? FeedKitError , FeedKitError.cancelledByUser)
      DispatchQueue.main.async() {
        exp.fulfill()
      }
    }
    op.cancel()
    self.waitForExpectations(timeout: 10) { er in
      XCTAssertNil(er)
    }
  }
  
  // MARK: Suggest
  
  func feedsFromFile(_ name: String = "feeds") throws -> [Feed] {
    let bundle = Bundle(for: self.classForCoder)
    let feedsURL = bundle.url(forResource: name, withExtension: "json")
    return try feedsFromFileAtURL(feedsURL!)
  }
  
  func entriesFromFile() throws -> [Entry] {
    let bundle = Bundle(for: self.classForCoder)
    let entriesURL = bundle.url(forResource: "entries", withExtension: "json")
    return try entriesFromFileAtURL(entriesURL!)
  }
  
  func populate() throws -> ([Feed], [Entry]) {
    let feeds = try! feedsFromFile()
    try! cache.update(feeds: feeds)
    
    let entries = try! entriesFromFile()
    try! cache.updateEntries(entries)
    
    return (feeds, entries)
  }
  
  func testSuggest() {
    let exp = self.expectation(description: "suggest")
    var op: SessionTaskOperation?
    func go(until: Bool = false) {
      var found:UInt = 4
      func shift () { found = found << 1 }
      repo.suggest("a", perFindGroupBlock: { er, finds in
        XCTAssertNil(er)
        XCTAssertFalse(finds.isEmpty)
        for find in finds {
          switch find {
          case .suggestedTerm:
            if found ==  4 { shift() }
          case .recentSearch:
            if found ==  8 { shift() }
          case .suggestedFeed:
            if found == 16 { shift() }
          case .suggestedEntry:
            if found == 32 { shift() }
          default:
            break // TODO: Remove default case
          }
        }
      }) { er in
        XCTAssertNil(er)
        let wanted = UInt(64)
        XCTAssertEqual(found, wanted, "should apply callback sequentially")
        guard until else {
          return
        }
        exp.fulfill()
      }
    }
    
    let _ = try! populate()
    
    let terms = ["apple", "automobile", "art"]
    terms.forEach { term in
      repo.search(term, perFindGroupBlock: { error, finds in
        XCTAssertNil(error)
        XCTAssert(finds.count > 0)
      }) { error in
        DispatchQueue.main.async {
          go(until: term == "art")
        }
      }
    }
    self.waitForExpectations(timeout: 10) { er in
      XCTAssertNil(er)
    }
  }
  
  func testFirstSuggestion() {
    let exp = self.expectation(description: "suggest")
    let term = "apple"
    var found: String?
    repo.suggest(term, perFindGroupBlock: { error, finds in
      XCTAssertNil(error)
      XCTAssert(!finds.isEmpty, "should never be empty")
      guard found == nil else { return }
      switch finds.first! {
      case .suggestedTerm(let sug):
        found = sug.term
      default:
        XCTFail("should suggest term")
      }
    }) { error in
      XCTAssertNil(error)
      XCTAssertEqual(found, term)
      exp.fulfill()
    }
    self.waitForExpectations(timeout: 10) { er in XCTAssertNil(er) }
  }
    
  func testCancelledSuggest() {
    for _ in 0...100 {
      let exp = self.expectation(description: "suggest")
      let op = repo.suggest("a", perFindGroupBlock: { _, _ in
        XCTFail("should not get dispatched")
        }) { er in
          do {
            throw er!
          } catch FeedKitError.cancelledByUser {
            exp.fulfill()
          } catch {
            XCTFail("should not pass unexpected error")
          }
      }
      op.cancel()
      self.waitForExpectations(timeout: 10) { er in
        XCTAssertNil(er)
      }
    }
  }
}
