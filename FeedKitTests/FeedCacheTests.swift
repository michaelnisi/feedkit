//
//  FeedCacheTests.swift
//  FeedKit
//
//  Created by Michael Nisi on 02.11.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

import Skull
import XCTest
import Foundation
@testable import FeedKit

final class FeedCacheTests: XCTestCase {
  var cache: FeedCache!
  let fm = FileManager.default

  override func setUp() {
    super.setUp()
    cache = Common.makeCache()
    if let url = cache.url {
      XCTAssert(fm.fileExists(atPath: url.path))
    }
  }

  override func tearDown() {
    try! Common.destroyCache(cache)
    super.tearDown()
  }

  func testFeedIDForURL() {
    do {
      let url = "abc"
      var found: [String]?
      let wanted = [url]
      do {
        let _ = try cache.feedID(for: url)
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
      let feeds = try! Common.feedsFromFile()
      try! cache.update(feeds: feeds)
      feed = feeds.first!
      url = feed!.url
      let found = try! cache.feedID(for: url!)
      let wanted = Feed.ID(rowid: 1, url: url!)
      XCTAssertEqual(found, wanted)
    }

    do {
      try! cache.remove([url!])
      var found: [String]?
      let wanted = [url!]
      do {
        let _ = try cache.feedID(for: url!)
      } catch FeedKitError.feedNotCached(let urls) {
        found = urls
      } catch {
        XCTFail("should not throw unexpected error")
      }
      XCTAssertEqual(found!, wanted)
    }

    do {
      try! cache.update(feeds: [feed!])
      let found = try! cache.feedID(for: url!)
      let wanted = Feed.ID(rowid: 11, url: url!)
      XCTAssertEqual(found, wanted)
    }
  }

}

// MARK: - Feed Caching

extension FeedCacheTests {
  
  func testMissingEntriesInCache() {
    let url = "http://abc.de"
    let age = CacheTTL.forever.defaults
    
    do {
      let locators = [EntryLocator]()
      let (entries, missing) =
        try! cache.fulfill(locators, ttl: age)
      
      // TODO: Rename to: entries(in: cache, with: locators, under: age)
      
      XCTAssertTrue(entries.isEmpty)
      XCTAssertTrue(missing.isEmpty)
    }
    
    do {
      let locator = EntryLocator(url: url)
      let locators = [locator, locator]
      let (entries, missing) =
        try! cache.fulfill(locators, ttl: age)
      
      XCTAssertTrue(entries.isEmpty)
      XCTAssertEqual(missing, [locator])
    }
    
    do {
      let older = EntryLocator(url: url)
      let locators = [
        EntryLocator(url: url, since: Date()),
        older
      ]
      let (entries, missing) =
        try! cache.fulfill(locators, ttl: age)
      
      XCTAssertTrue(entries.isEmpty)
      XCTAssertEqual(missing, [older], "should merge locators")
    }
    
    do {
      let guid = "abc"
      let locator = EntryLocator(url: url, guid: guid)
      let locators = [locator, locator]
      let (entries, missing) =
        try! cache.fulfill(locators, ttl: age)
      
      XCTAssertTrue(entries.isEmpty)
      XCTAssertEqual(missing, [locator], "should be unique")
    }
  }
  
  func testLatest() {
    struct Thing: Cachable {
      let url: String
      let ts: Date?
      func equals(_ rhs: Thing) -> Bool {
        return url == rhs.url
      }
    }
    let a = Thing(url: "abc", ts: Date(timeIntervalSince1970: 0))
    let b = Thing(url: "def", ts: Date(timeIntervalSince1970: 3600))
    let c = Thing(url: "ghi", ts: Date(timeIntervalSince1970: 7200))
    let found = [
      FeedCache.latest([a, b, c]),
      FeedCache.latest([c, b, a]),
      FeedCache.latest([a, c, b]),
      FeedCache.latest([b, c, a])
    ]
    let wanted = [
      c,
      c,
      c,
      c
    ]
    for (i, b) in wanted.enumerated() {
      let a = found[i]
      XCTAssert(a.equals(b))
    }
  }
  
  func testKeepImages() {
    let url = "http://abc.de"
    
    let iTunes = ITunesItem(
      url: url,
      iTunesID: 123,
      img100: "a",
      img30: "b",
      img60: "c",
      img600: "d"
    )
    
    let a = Feed(author: nil, iTunes: iTunes, image: nil, link: nil,
                 originalURL: url, summary: nil, title: "Title", ts: nil,
                 uid: nil, updated: nil, url: url)
    
    try! cache.update(feeds: [a])
    
    do {
      let b = Feed(author: nil, iTunes: nil, image: nil, link: nil,
                   originalURL: url, summary: nil, title: "Title", ts: nil,
                   uid: nil, updated: nil, url: url)
      
      try! cache.update(feeds: [b])
      
      let found = try! cache.feeds([url]).first!
      XCTAssertEqual(found.iTunes, iTunes, "should not nullify iTunes images")
    }
    
    do {
      let c = Feed(author: "not null", iTunes: nil, image: nil, link: nil,
                   originalURL: url, summary: nil, title: "Title", ts: nil,
                   uid: nil, updated: nil, url: url)
      
      try! cache.update(feeds: [c])
      
      let found = try! cache.feeds([url]).first!
      XCTAssertEqual(found.iTunes, iTunes, "should not nullify iTunes images")
    }
  }

  func testUpdateFeeds() {
    let feeds = try! Common.feedsFromFile()

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
      let uid = try! cache.feedID(for: url)
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
      Common.makeEntry(name: .gruber)
    ]
    var foundURLs: [String]? = nil
    let wantedURLs = ["http://daringfireball.net/thetalkshow/rss"]
    do {
      try cache.update(entries: entries)
    } catch FeedKitError.feedNotCached(let urls) {
      foundURLs = urls
    } catch {
      XCTFail("should throw expected error")
    }
    XCTAssertEqual(foundURLs!, wantedURLs)
  }
  
  func checkEntries(_ found: [Entry], wanted: [Entry]) {
    for (i, wantedEntry) in wanted.enumerated() {
      let foundEntry = found[i]
      if wantedEntry.author != nil {
        // If the entry doesn’t provide an author, 
        // `entryFromRow(_ row: SkullRow) throws -> Entry`
        // falls back on the feed’s author.
        XCTAssertEqual(foundEntry.author, wantedEntry.author)
      }
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
    let (feeds, entries) = try! Common.populate(cache: cache)
    let urls = feeds.map { $0.url }

    if let p = cache.url?.path {
      print("** \(p)")
    }

    XCTAssertEqual(urls.count, 10)

    let locators = urls.map { EntryLocator(url: $0) }
    let found = try! cache.entries(within: locators)
    let wanted = entries

    XCTAssertEqual(wanted.count, 1099, "should be nine less than 1108")
    XCTAssertEqual(found.count, wanted.count)
    XCTAssertEqual(found, wanted)
    checkEntries(found, wanted: wanted)
  }

  func testEntriesWithGUIDs() {
    let (_, entries) = try! Common.populate(cache: cache)
    for entry in entries {
      XCTAssertNotNil(entry.guid)
    }
    let guids = entries.map { $0.guid }
  
    let found = try! cache.entries(guids).sorted { $0.guid < $1.guid }
    let wanted = entries.sorted { $0.guid < $1.guid }
    
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
    let (feeds, _) = try! Common.populate(cache: cache)
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
    let found = try! cache.entries(within: locators)
    XCTAssert(found.isEmpty, "should have removed entries too")
  }
  
}

// MARK: - Search Caching

extension FeedCacheTests {

  func testUpdateFeedsForTerm() {
    let feeds = try! Common.feedsFromFile(named: "search")
    let term = "newyorker"
    
    // Granular scoping.

    do {
      try cache.update(suggestions: [], for: "new")
    } catch {
      XCTFail("should not throw \(error)")
    }

    do {
      try cache.update(feeds: feeds, for: term)
    } catch {
      XCTFail("should not throw \(error)")
    }

    do {
      let found = try cache.feeds(for: term, limit: 50)
      let wanted = feeds.filter {
        $0.url != "http://feeds.feedburner.com/doublet"
      }
      
      XCTAssertEqual(found!, wanted)
    } catch {
      XCTFail("should not throw \(error)")
    }

    do {
      let found = try cache.suggestions(for: term, limit: 5)
      let wanted = SuggestOperation.suggestions(from: [term])
      XCTAssertEqual(found!, wanted)
    } catch {
      XCTFail("should not throw \(error)")
    }

    do {
      try cache.update(feeds: [], for: term)
    } catch {
      XCTFail("should not throw \(error)")
    }

    do {
      let found = try cache.feeds(for: term, limit: 50)
      XCTAssert(found!.isEmpty)
    } catch {
      XCTFail("should not throw \(error)")
    }

    do {
      let found = try cache.suggestions(for: term, limit: 5)
      XCTAssertNil(found)
    } catch {
      XCTFail("should not throw \(error)")
    }
  }

  func testFeedsForTerm() {
    let feeds = try! Common.feedsFromFile(named: "search")
    let term = "newyorker"
    
    XCTAssertEqual(feeds.count, 12)

    XCTAssertNil(try! cache.feeds(for: term, limit: 50))

    for _ in 0...1 {
      try! cache.update(feeds: feeds, for: term)

      let found = try! cache.feeds(for: term, limit: 50)!
      let wanted = feeds.filter {
        $0.url != "http://feeds.feedburner.com/doublet"
      }

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
        let uid = try! cache.feedID(for: url)
        XCTAssertEqual(uid, foundFeed.uid)
      }
      
      XCTAssertEqual(found, wanted)
    }
  }

  func testFeedsMatchingTerm() {
    let feeds = try! Common.feedsFromFile(named: "search")
    let term = "newyorker"
    XCTAssertNil(try! cache.feeds(for: term, limit: 50))

    try! cache.update(feeds: feeds, for: term)


    var wanted = [Feed]()
    for i in 0...2 { wanted.append(feeds[i]) }

    let found = try! cache.feeds(matching: "new", limit: 3)!

    XCTAssertEqual(found, wanted)

    for (i, that) in wanted.enumerated() {
      let this = found[i]
      XCTAssertEqual(this.title, that.title)
      XCTAssertEqual(this.url, that.url)
      XCTAssertEqual(this.iTunes, that.iTunes)
    }
  }

  func testEntriesMatchingTerm() {
    let _ = try! Common.populate(cache: cache)
    
    guard let found = try! cache.entries(matching: "Dead", limit: 3) else {
      return XCTFail("not found")
    }
    
    XCTAssertEqual(found.count, 3)
    XCTAssertEqual(found.first?.title, "#319: And the Call Was Coming from the Basement")
  }

  func testSuggestions() {
    XCTAssertNil(try! cache.suggestions(for: "a", limit: 5))

    let terms = ["apple", "apple watch", "apple pie"]
    let input = SuggestOperation.suggestions(from: terms)
    try! cache.update(suggestions: input, for: "apple")

    do {
      var term: String = ""
      for c in "apple " {
        term.append(c)
        if let sugs = try! cache.suggestions(for: term, limit: 5) {
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

    if let sugs = try! cache.suggestions(for: "apple p", limit: 5) {
      XCTAssertEqual(sugs.count, 1)
      let found: Suggestion = sugs.last!
      XCTAssertNotNil(found.ts!)
      let wanted: Suggestion = input.last!
      XCTAssertEqual(found, wanted)
    } else {
      XCTFail("should suggest")
    }

    try! cache.update(suggestions: [], for: "apple")

    XCTAssertNil(try! cache.suggestions(for: "a", limit: 5))

    do {
      let terms = ["apple", "apple ", "apple p", "apple pi", "apple pie"]
      for term in terms {
        if let sugs = try! cache.suggestions(for: term, limit: 5) {
          XCTAssert(sugs.isEmpty)
        } else {
          XCTFail("should suggest")
        }
      }
    }
  }

  func testRemoveSuggestions() {
    let terms = ["apple", "apple watch", "apple pie"]
    let input = SuggestOperation.suggestions(from: terms)

    try! cache.update(suggestions: input, for: "apple")
    try! cache.update(suggestions: [], for: "pie")
    if let found = try! cache.suggestions(for: "apple", limit: 5) {
      XCTAssertEqual(found.count, 2)
      for (i, sug) in found.enumerated() {
        XCTAssertEqual(sug, input[i])
      }
    } else {
      XCTFail("should find suggestions")
    }
  }

  fileprivate func hit(_ term: String, _ wanted: String, _ cache: [String : Date]) {
    if let (found, _) = FeedCache.subcached(term, dict: cache) {
      XCTAssertEqual(found, wanted)
      if term.lengthOfBytes(using: String.Encoding.utf8) > 1 {
        let pre = term.index(before: term.endIndex)
        self.hit(String(term[..<pre]), wanted, cache)
      }
    } else {
      XCTFail("\(term) should be cached")
    }
  }

  func testSubcached() {
    var cache = [String : Date]()
    cache["a"] = Date()
    hit("abc", "a", cache)
    cache["a"] = nil

    cache["abc"] = Date()
    XCTAssertNotNil(FeedCache.subcached("abcd", dict: cache)!.0)
    XCTAssertNil(FeedCache.subcached("ab", dict: cache)?.0)
  }
}

// MARK: - Utilities

private struct Item: Cachable {
  let url: FeedURL
  let ts: Date?
  let id: Int
}

extension Item: Equatable {
  static func ==(lhs: Item, rhs: Item) -> Bool {
    return lhs.id == rhs.id
  }
}

extension FeedCacheTests {
  
  func testSubtract() {
    do {
      let items = [Entry]()
      let ttl = TimeInterval.infinity
      let urls = [String]()
      let wanted: ([Entry], [Entry], [String]?) = {
        return ([], [], nil)
      }()
      let found = FeedCache.subtract(items, from: urls, with: ttl)
      XCTAssertEqual(found.0, wanted.0)
      XCTAssertEqual(found.1, wanted.1)
      XCTAssertNil(found.2)
    }
    
    do {
      let items = [Entry]()
      let ttl = TimeInterval.infinity
      let url = "http://abc.de"
      let urls = [url]
      let wanted: ([Entry], [Entry], [FeedURL]) = {
        return ([], [], urls)
      }()
      let found = FeedCache.subtract(items, from: urls, with: ttl)
      XCTAssertEqual(found.0, wanted.0)
      XCTAssertEqual(found.1, wanted.1)
      XCTAssertEqual(found.2!, wanted.2)
    }

    do {
      let items = [
        Item(url: "http://abc.de", ts: Date(), id: 0)
      ]
      let ttl = TimeInterval.infinity
      let url = "http://abc.de"
      let urls = [url]
      let wanted: ([Item], [Item]) = {
        return (items, [])
      }()
      let found = FeedCache.subtract(items, from: urls, with: ttl)
      XCTAssertEqual(found.0, wanted.0)
      XCTAssertEqual(found.1, wanted.1)
      XCTAssertNil(found.2)
    }
    
    do {
      let ttl = 3600.0
      let ts = Date.init(timeIntervalSinceNow: -ttl)
      let items = [
        Item(url: "http://abc.de", ts: ts, id: 0)
      ]
      let url = "http://abc.de"
      let urls = [url]
      let wanted: ([Item], [Item], [FeedURL]) = {
        return ([], items, [url])
      }()
      let found = FeedCache.subtract(items, from: urls, with: ttl)
      XCTAssertEqual(found.0, wanted.0)
      XCTAssertEqual(found.1, wanted.1)
      XCTAssertEqual(found.2!, wanted.2)
    }
    
    // This function is way more complex and needs deeper testing, of course.
    // But which function doesn’t, right?
  }
  
  func testSliceElements() {
    let fixtures = [
      (FeedCache.slice(elements: [1, 2, 3], with: 1), [[1], [2], [3]]),
      (FeedCache.slice(elements: [1, 2, 3], with: 2), [[1, 2], [3]]),
      (FeedCache.slice(elements: [1, 2, 3], with: 3), [[1, 2, 3]]),
      (FeedCache.slice(elements: [1, 2, 3], with: 4), [[1, 2, 3]])
    ]
   
    fixtures.forEach { fixture in
      let (found, wanted) = fixture
      XCTAssertEqual(found.count, wanted.count)
      found.enumerated().forEach { i, a in
        let b = wanted[i]
        XCTAssertEqual(a, b)
      }
    }
  }
  
}
