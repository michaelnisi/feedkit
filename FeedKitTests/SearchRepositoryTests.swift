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

final class SearchRepositoryTests: XCTestCase {
  var repo: Searching!
  var cache: FeedCache!
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
    
    func go(prev: [Find]?, cb: @escaping ([Find]) -> Void) {
      
      var acc = [Find]()
      
      repo.search("monocle", perFindGroupBlock: { error, finds in
        XCTAssertNil(error)
        XCTAssert(finds.count > 0)
        
        let wanted = Array(Set(finds))
        XCTAssertEqual(finds.count, wanted.count, "should be unique")
        
        acc = acc + finds
        
        if let prevFinds = prev {
          
          for (i, find) in finds.enumerated() {
            XCTAssertNotNil(find.ts, "cached should have timestamp")
            
            let prevFind = prevFinds[i]
            XCTAssertEqual(
              find, prevFind, "fresh and cached should be in the same order")
          }
        }
      }) { error in
        XCTAssertNil(error)
        DispatchQueue.main.async() {
          cb(acc)
        }
      }
    }
    
    go(prev: nil) { finds in
      go(prev: finds) { _ in
        DispatchQueue.main.async {
          exp.fulfill()
        }
      }
    }
    
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
    // Mere speculation that these are yielding no results from iTunes.
    go(["🙈", "🙉", "🙊"])
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
    for _ in 0...100 {
      let exp = self.expectation(description: "search")
      let term = randomString(length: max(Int(arc4random_uniform(8)), 1))
      let op = repo.search(term, perFindGroupBlock: { _, _ in
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

  // MARK: Suggest

  func feedsFromFile(_ name: String = "feeds") throws -> [Feed] {
    let bundle = Bundle(for: self.classForCoder)
    let feedsURL = bundle.url(forResource: name, withExtension: "json")
    return try feedsFromFileAtURL(feedsURL!)
  }

  @discardableResult func populate() throws -> ([Feed], [Entry]) {
    let feeds = try! feedsFromFile()
    try! cache.update(feeds: feeds)

    let entries = try! entriesFromFile()
    try! cache.update(entries: entries)

    return (feeds, entries)
  }

  func testSuggest() {
    func suggest(cb: @escaping () -> Void) {
      var found:UInt = 4
      func shift () { found = found << 1 }
      
      var acc = [Find]()
      
      repo.suggest("a", perFindGroupBlock: { er, finds in
        XCTAssertNil(er)
        XCTAssertFalse(finds.isEmpty)
        
        acc.append(contentsOf: finds)

        // XCTAssertEqual(finds.count, Set(finds).count, "should be unique")

        for find in finds {
          switch find {
          case .suggestedTerm:
            if found ==  4 { shift() }
          case .recentSearch:

            // TODO: Review suggesting
            //
            // Understand why, in these test results at least, no recent
            // searches are being considered. I don’t know if this is correct.

            break
          case .suggestedFeed:
            if found == 8 { shift() }
          case .suggestedEntry:
            if found == 16 { shift() }
          case .foundFeed:
            fatalError("unexpected result")
          }
        }
      }) { er in
        XCTAssertNil(er)
        let first = Find.suggestedTerm(Suggestion(term: "a", ts: nil))
        XCTAssertEqual(acc.first, first)
        
        let wanted = UInt(32)
        XCTAssertEqual(found, wanted, "should find things sequentially")
        
        cb()
      }
    }

    let exp = self.expectation(description: "suggest")

    func search(terms: [String]) {
      guard let term = terms.first else {
        exp.fulfill()
        return
      }
      repo.search(term, perFindGroupBlock: { error, finds in
        XCTAssertNil(error)
        XCTAssert(finds.count > 0)
      }) { error in
        XCTAssertNil(error)
        suggest() {
          let tail = Array(terms.dropFirst(1))
          search(terms: tail)
        }
      }
    }

    try! populate()
    search(terms:  ["apple", "automobile", "art"])

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
      let term = randomString(length: max(Int(arc4random_uniform(8)), 1))
      let op = repo.suggest(term, perFindGroupBlock: { error, finds in
        XCTAssertNil(error)
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

// MARK: Query Term Trimming

extension SearchRepositoryTests {
  
  func testTrimString() {
    func f(_ s: String) -> String {
      return SearchRepoOperation.replaceWhitespaces(in: s.lowercased(), with: " ")
    }
    let input = [
      "apple",
      "apple watch",
      "  apple  watch ",
      "  apple     Watch Kit  ",
      " ",
      ""
    ]
    let wanted = [
      "apple",
      "apple watch",
      "apple watch",
      "apple watch kit",
      "",
      ""
    ]
    for (n, it) in wanted.enumerated() {
      XCTAssertEqual(f(input[n]), it)
    }
  }
  
}
