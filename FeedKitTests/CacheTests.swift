//
//  CacheTests.swift
//  FeedKit
//
//  Created by Michael Nisi on 02.11.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import Skull
import XCTest
import Foundation
@testable import FeedKit

class CacheTests: XCTestCase {
  var cache: Cache!
  let fm = FileManager.default

  override func setUp() {
    super.setUp()
    cache = freshCache(self.classForCoder)
    if let url = cache.url {
      XCTAssert(fm.fileExists(atPath: url.path))
    }
  }

  override func tearDown() {
    try! destroyCache(cache)
    super.tearDown()
  }

  func feedsFromFile(_ name: String = "feeds") throws -> [Feed] {
    let bundle = Bundle(for: self.classForCoder)
    let feedsURL = bundle.url(forResource: name, withExtension: "json")!
    return try feedsFromFileAtURL(feedsURL)
  }

  func testFeedIDForURL() {
    do {
      let url = "abc"
      var found: [String]?
      let wanted = [url]
      do {
        let _ = try cache.feedIDForURL(url)
      } catch FeedKitError.feedNotCached(let urls) {
        found = urls
      } catch {
        XCTFail("should not throw unexpected error")
      }
      XCTAssertEqual(found!, wanted)
    }

    var url: String?
    var feed: Feed?

    do {
      let feeds = try! feedsFromFile()
      try! cache.update(feeds: feeds)
      feed = feeds.first!
      url = feed!.url
      let found = try! cache.feedIDForURL(url!)
      let wanted = 1
      XCTAssertEqual(found, wanted)
    }

    do {
      try! cache.remove([url!])
      var found: [String]?
      let wanted = [url!]
      do {
        let _ = try cache.feedIDForURL(url!)
      } catch FeedKitError.feedNotCached(let urls) {
        found = urls
      } catch {
        XCTFail("should not throw unexpected error")
      }
      XCTAssertEqual(found!, wanted)
    }

    do {
      try! cache.update(feeds: [feed!])
      let found = try! cache.feedIDForURL(url!)
      let wanted = 11
      XCTAssertEqual(found, wanted)
    }
  }

  // MARK: Feed Caching

  func testUpdateFeeds() {
    let feeds = try! feedsFromFile()

    try! cache.update(feeds: feeds)

    func testUpdate() {
      let feed = feeds.first!
      try! cache.update(feeds: [feed])
    }
    testUpdate()

    let urls = feeds.map { $0.url }
    let found = try! cache.feeds(urls)

    let wanted = feeds
    XCTAssertEqual(found, wanted)
    for (i, wantedFeed) in wanted.enumerated() {
      let foundFeed = found[i]

      XCTAssertEqual(foundFeed.author, wantedFeed.author)
      XCTAssertEqual(foundFeed.iTunes, wantedFeed.iTunes)
      XCTAssertEqual(foundFeed.link, wantedFeed.link)
      XCTAssertEqual(foundFeed.summary, wantedFeed.summary)
      XCTAssertEqual(foundFeed.title, wantedFeed.title)
      XCTAssertNotNil(foundFeed.ts, "should bear timestamp")
      XCTAssertEqual(foundFeed.updated, wantedFeed.updated)
      XCTAssertEqual(foundFeed.url, wantedFeed.url)

      let url = foundFeed.url
      XCTAssertTrue(cache.hasURL(url))
      let uid = try! cache.feedIDForURL(url)
      XCTAssertEqual(uid, foundFeed.uid)
    }
  }

  func testFeedsWithURLs() {
    let urls = ["", "abc.de"]
    let found = try! cache.feeds(urls)
    XCTAssert(found.isEmpty, "should not be nil but empty")
  }

  func testUpdateEntriesOfUncachedFeeds() {
    let entries = [
      try! entryWithName("thetalkshow")
    ]
    var foundURLs: [String]? = nil
    let wantedURLs = ["http://daringfireball.net/thetalkshow/rss"]
    do {
      try cache.updateEntries(entries)
    } catch FeedKitError.feedNotCached(let urls) {
      foundURLs = urls
    } catch {
      XCTFail("should throw expected error")
    }
    XCTAssertEqual(foundURLs!, wantedURLs)
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
  
  func checkEntries(_ found: [Entry], wanted: [Entry]) {
    for (i, wantedEntry) in wanted.enumerated() {
      let foundEntry = found[i]
      XCTAssertEqual(foundEntry.author, wantedEntry.author)
      XCTAssertEqual(foundEntry.duration, wantedEntry.duration)
      XCTAssertEqual(foundEntry.enclosure, wantedEntry.enclosure)
      XCTAssertEqual(foundEntry.feed, wantedEntry.feed)
      XCTAssertNotNil(foundEntry.guid, "should have guid (from caching)")
      XCTAssertEqual(foundEntry.image, wantedEntry.image)
      XCTAssertEqual(foundEntry.link, wantedEntry.link)
      XCTAssertEqual(foundEntry.subtitle, wantedEntry.subtitle)
      XCTAssertEqual(foundEntry.summary, wantedEntry.summary)
      XCTAssertEqual(foundEntry.title, wantedEntry.title)
      XCTAssertNotNil(foundEntry.ts, "should have timestamp (from caching)")
      XCTAssertEqual(foundEntry.updated, wantedEntry.updated)
    }
  }

  func testUpdateEntries() {
    let (feeds, entries) = try! populate()
    let urls = feeds.map { $0.url }

    if let p = cache.url?.path {
      print("** \(p)")
    }

    XCTAssertEqual(urls.count, 10)

    let locators = urls.map { EntryLocator(url: $0) }
    let found = try! cache.entries(locators)
    let wanted = entries

    XCTAssertEqual(wanted.count, 1099, "should be nine less than 1108")
    XCTAssertEqual(found.count, wanted.count)
    XCTAssertEqual(found, wanted)
    checkEntries(found, wanted: wanted)
  }

  func testEntriesWithGUIDs() {
    let (_, entries) = try! populate()
    for entry in entries {
      XCTAssertNotNil(entry.guid)
    }
    let guids = entries.map { $0.guid }
    let found = try! cache.entries(guids)
    
    let wanted = entries
    XCTAssertEqual(found, wanted)
    checkEntries(found, wanted: wanted)
    
    do {
      let guids = ["abc", "def"]
      let found = try! cache.entries(guids)
      XCTAssert(found.isEmpty)
    }
    
    guard let first = guids.first else {
      return XCTFail("not found")
    }
    
    do {
      let guids = ["abc", "def", first]
      let found = try! cache.entries(guids)
      let wanted = [entries.first!]
      XCTAssertEqual(found, wanted)
    }
  }

  func testRemoveFeedsWithURLs() {
    let (feeds, _) = try! populate()
    let urls = feeds.map { $0.url }

    urls.forEach { url in
      XCTAssertTrue(cache.hasURL(url))
    }

    try! cache.update(feeds: feeds) // to provoke dopplers
    try! cache.remove(urls)

    urls.forEach { url in
      XCTAssertFalse(cache.hasURL(url))
    }

    let locators = urls.map { EntryLocator(url: $0) }
    let found = try! cache.entries(locators)
    XCTAssert(found.isEmpty, "should have removed entries too")
  }

  // MARK: Search Caching

  func testUpdateFeedsForTerm() {
    let feeds = try! feedsFromFile("search")
    let term = "newyorker"

    do {
      try cache.updateSuggestions([], forTerm: "new")
    } catch let er {
      XCTFail("should not throw \(er)")
    }

    do {
      try cache.updateFeeds(feeds, forTerm: term)
    } catch let er {
      XCTFail("should not throw \(er)")
    }

    do {
      let found = try cache.feedsForTerm(term, limit: 50)
      let wanted = feeds.sorted {
        $0.updated!.timeIntervalSince1970 > $1.updated!.timeIntervalSince1970
      }
      XCTAssertEqual(found!, wanted)
    } catch let er {
      XCTFail("should not throw \(er)")
    }

    do {
      let found = try cache.suggestionsForTerm(term, limit: 5)
      let wanted = suggestionsFromTerms([term])
      XCTAssertEqual(found!, wanted)
    } catch let er {
      XCTFail("should not throw \(er)")
    }

    do {
      try cache.updateFeeds([], forTerm: term)
    } catch let er {
      XCTFail("should not throw \(er)")
    }

    do {
      let found = try cache.feedsForTerm(term, limit: 50)
      XCTAssert(found!.isEmpty)
    } catch let er {
      XCTFail("should not throw \(er)")
    }

    do {
      let found = try cache.suggestionsForTerm(term, limit: 5)
      XCTAssertNil(found)
    } catch let er {
      XCTFail("should not throw \(er)")
    }
  }

  func testFeedsForTerm() {
    let feeds = try! feedsFromFile("search")
    let term = "newyorker"

    XCTAssertNil(try! cache.feedsForTerm(term, limit: 50))

    for _ in 0...1 {
      try! cache.updateFeeds(feeds, forTerm: term)

      let found = try! cache.feedsForTerm(term, limit: 50)!
      let wanted = feeds.sorted {
        $0.updated!.timeIntervalSince1970 > $1.updated!.timeIntervalSince1970
      }
      XCTAssertEqual(found, wanted)

      for (i, wantedFeed) in wanted.enumerated() {
        let foundFeed = found[i]

        XCTAssertEqual(foundFeed.author, wantedFeed.author)
        XCTAssertEqual(foundFeed.iTunes, wantedFeed.iTunes)
        XCTAssertEqual(foundFeed.image, wantedFeed.image)
        XCTAssertEqual(foundFeed.link, wantedFeed.link)
        XCTAssertEqual(foundFeed.summary, wantedFeed.summary)
        XCTAssertEqual(foundFeed.title, wantedFeed.title)
        XCTAssertEqual(foundFeed.updated, wantedFeed.updated)
        XCTAssertEqual(foundFeed.url, wantedFeed.url)
        XCTAssertNotNil(foundFeed.ts, "should bear timestamp")

        let url = foundFeed.url
        XCTAssertTrue(cache.hasURL(url))
        let uid = try! cache.feedIDForURL(url)
        XCTAssertEqual(uid, foundFeed.uid)
      }
    }
  }

  func testFeedsMatchingTerm() {
    let feeds = try! feedsFromFile("search")
    let term = "newyorker"
    XCTAssertNil(try! cache.feedsForTerm(term, limit: 50))

    try! cache.updateFeeds(feeds, forTerm: term)


    var wanted = [Feed]()
    for i in 0...2 { wanted.append(feeds[i]) }

    let found = try! cache.feedsMatchingTerm("new", limit: 3)!

    XCTAssertEqual(found, wanted)

    for (i, that) in wanted.enumerated() {
      let this = found[i]
      XCTAssertEqual(this.title, that.title)
      XCTAssertEqual(this.url, that.url)
      XCTAssertEqual(this.iTunes, that.iTunes)
    }
  }

  func testEntriesMatchingTerm() {
    let _ = try! populate()
    guard let found = try! cache.entriesMatchingTerm("supercomputer", limit: 3) else {
      return XCTFail("not found")
    }
    XCTAssertEqual(found.count, 1)
    XCTAssertEqual(found.first?.title, "Seven Deadly Sins")
  }

  func testSuggestions() {
    XCTAssertNil(try! cache.suggestionsForTerm("a", limit: 5))

    let terms = ["apple", "apple watch", "apple pie"]
    let input = suggestionsFromTerms(terms)
    try! cache.updateSuggestions(input, forTerm:"apple")

    do {
      var term: String = ""
      for c in "apple ".characters {
        term.append(c)
        if let sugs = try! cache.suggestionsForTerm(term, limit: 5) {
          XCTAssertEqual(sugs.count, terms.count)
          for sug in sugs {
            XCTAssertNotNil(sug.ts)
          }
          XCTAssertEqual(sugs, input)
        } else {
          XCTFail("should suggest")
        }
      }
    }

    if let sugs = try! cache.suggestionsForTerm("apple p", limit: 5) {
      XCTAssertEqual(sugs.count, 1)
      let found: Suggestion = sugs.last!
      XCTAssertNotNil(found.ts!)
      let wanted: Suggestion = input.last!
      XCTAssertEqual(found, wanted)
    } else {
      XCTFail("should suggest")
    }

    try! cache.updateSuggestions([], forTerm:"apple")

    XCTAssertNil(try! cache.suggestionsForTerm("a", limit: 5))

    do {
      let terms = ["apple", "apple ", "apple p", "apple pi", "apple pie"]
      for term in terms {
        if let sugs = try! cache.suggestionsForTerm(term, limit: 5) {
          XCTAssert(sugs.isEmpty)
        } else {
          XCTFail("should suggest")
        }
      }
    }
  }

  func testRemoveSuggestions() {
    let terms = ["apple", "apple watch", "apple pie"]
    let input = suggestionsFromTerms(terms)

    try! cache.updateSuggestions(input, forTerm:"apple")
    try! cache.updateSuggestions([], forTerm:"pie")
    if let found = try! cache.suggestionsForTerm("apple", limit: 5) {
      XCTAssertEqual(found.count, 2)
      for (i, sug) in found.enumerated() {
        XCTAssertEqual(sug, input[i])
      }
    } else {
      XCTFail("should find suggestions")
    }
  }

  fileprivate func hit (_ term: String, _ wanted: String, _ cache: [String:Date]) {
    if let (found, _) = subcached(term, dict: cache) {
      XCTAssertEqual(found, wanted)
      if term.lengthOfBytes(using: String.Encoding.utf8) > 1 {
        let pre = term.characters.index(before: term.endIndex)
        self.hit(term.substring(to: pre), wanted, cache)
      }
    } else {
      XCTFail("\(term) should be cached")
    }
  }

  func testSubcached () {
    var cache = [String:Date]()
    cache["a"] = Date()
    hit("abc", "a", cache)
    cache["a"] = nil

    cache["abc"] = Date()
    XCTAssertNotNil(subcached("abcd", dict: cache)!.0)
    XCTAssertNil(subcached("ab", dict: cache)?.0)
  }
}
