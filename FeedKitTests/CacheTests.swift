//
//  CacheTests.swift
//  FeedKit
//
//  Created by Michael Nisi on 02.11.14.
//  Copyright (c) 2014 Michael Nisi. All rights reserved.
//

@testable import FeedKit
import Skull
import XCTest
import Foundation
import FeedKit

class CacheTests: XCTestCase {
  var cache: Cache!
  let fm = NSFileManager.defaultManager()

  override func setUp() {
    super.setUp()
    cache = freshCache(self.classForCoder)
    if let url = cache.url {
      XCTAssert(fm.fileExistsAtPath(url.path!))
    }
  }

  override func tearDown() {
    try! destroyCache(cache)
    super.tearDown()
  }
  
  func feedsFromFile(name: String = "feeds") throws -> [Feed] {
    let bundle = NSBundle(forClass: self.classForCoder)
    let feedsURL = bundle.URLForResource(name, withExtension: "json")
    return try feedsFromFileAtURL(feedsURL!)
  }
  
  func testFeedIDForURL() {
    do {
      let url = "abc"
      var found: [String]?
      let wanted = [url]
      do {
        try cache.feedIDForURL(url)
      } catch FeedKitError.FeedNotCached(let urls) {
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
      try! cache.updateFeeds(feeds)
      feed = feeds.first!
      url = feed!.url
      let found = try! cache.feedIDForURL(url!)
      let wanted = 1
      XCTAssertEqual(found, wanted)
    }
    
    do {
      try! cache.removeFeedsWithURLs([url!])
      var found: [String]?
      let wanted = [url!]
      do {
        try cache.feedIDForURL(url!)
      } catch FeedKitError.FeedNotCached(let urls) {
        found = urls
      } catch {
        XCTFail("should not throw unexpected error")
      }
      XCTAssertEqual(found!, wanted)
    }
    
    do {
      try! cache.updateFeeds([feed!])
      let found = try! cache.feedIDForURL(url!)
      let wanted = 11
      XCTAssertEqual(found, wanted)
    }
  }
  
  // MARK: Feed Caching
  
  func testUpdateFeeds() {
    let feeds = try! feedsFromFile()
    
    try! cache.updateFeeds(feeds)
  
    func testUpdate() {
      let feed = feeds.first!
      try! cache.updateFeeds([feed])
    }
    testUpdate()
    
    let urls = feeds.map { $0.url }
    let found = try! cache.feedsWithURLs(urls)
    
    let wanted = feeds
    XCTAssertEqual(found, wanted)
    for (i, wantedFeed) in wanted.enumerate() {
      let foundFeed = found[i]

      XCTAssertEqual(foundFeed.author, wantedFeed.author)
      XCTAssertEqual(foundFeed.guid, wantedFeed.guid)
      XCTAssertEqual(foundFeed.images, wantedFeed.images)
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
    let found = try! cache.feedsWithURLs(urls)
    XCTAssert(found.isEmpty, "should not be nil but empty")
  }
  
  func testUpdateEntriesOfUncachedFeeds() {
    let entries = [
      try! entryWithName("thetalkshow")
    ]
    var foundURLs: [String]? = nil
    let wantedURLs = ["http://feeds.muleradio.net/thetalkshow"]
    do {
      try cache.updateEntries(entries)
    } catch FeedKitError.FeedNotCached(let urls) {
      foundURLs = urls
    } catch {
      XCTFail("should throw expected error")
    }
    XCTAssertEqual(foundURLs!, wantedURLs)
  }
  
  func entriesFromFile() throws -> [Entry] {
    let bundle = NSBundle(forClass: self.classForCoder)
    let entriesURL = bundle.URLForResource("entries", withExtension: "json")
    return try entriesFromFileAtURL(entriesURL!)
  }

  func populate() throws -> ([Feed], [Entry]) {
    let feeds = try! feedsFromFile()
    try! cache.updateFeeds(feeds)
    
    let entries = try! entriesFromFile()
    try! cache.updateEntries(entries)
    
    return (feeds, entries)
  }
  
  func testUpdateEntries() {
    let (feeds, entries) = try! populate()
    let urls = feeds.map { $0.url }
    let intervals = urls.map { EntryInterval(url: $0) }
    let found = try! cache.entriesOfIntervals(intervals)
    let wanted = entries
    XCTAssertEqual(found, wanted)
    for (i, wantedEntry) in wanted.enumerate() {
      let foundEntry = found[i]
      XCTAssertEqual(foundEntry.author, wantedEntry.author)
      XCTAssertEqual(foundEntry.duration, wantedEntry.duration)
      XCTAssertEqual(foundEntry.enclosure, wantedEntry.enclosure)
      XCTAssertEqual(foundEntry.feed, wantedEntry.feed)
      XCTAssertEqual(foundEntry.id, wantedEntry.id)
      XCTAssertEqual(foundEntry.img, wantedEntry.img)
      XCTAssertEqual(foundEntry.link, wantedEntry.link)
      XCTAssertEqual(foundEntry.subtitle, wantedEntry.subtitle)
      XCTAssertEqual(foundEntry.summary, wantedEntry.summary)
      XCTAssertEqual(foundEntry.title, wantedEntry.title)
      XCTAssertNotNil(foundEntry.ts, "should bear timestamp")
      XCTAssertEqual(foundEntry.updated, wantedEntry.updated)
    }
  }
  
  func testRemoveFeedsWithURLs() {
    let (feeds, _) = try! populate()
    let urls = feeds.map { $0.url }
    
    urls.forEach { url in
      XCTAssertTrue(cache.hasURL(url))
    }
    
    try! cache.updateFeeds(feeds) // to provoke dopplers
    try! cache.removeFeedsWithURLs(urls)
    
    urls.forEach { url in
      XCTAssertFalse(cache.hasURL(url))
    }
    
    let intervals = urls.map { EntryInterval(url: $0) }
    let found = try! cache.entriesOfIntervals(intervals)
    XCTAssert(found.isEmpty, "should have removed entries too")
  }
  
  // MARK: Search Caching
  
  func testUpdateFeedsForTerm() {
    let feeds = try! feedsFromFile("search")
    let term = "newyorker"
    
    do {
      try cache.updateFeeds(feeds, forTerm: term)
    } catch let er {
      XCTFail("should not throw \(er)")
    }
    
    do {
      let found = try cache.feedsForTerm(term, limit: 50)
      let wanted = feeds
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
      let wanted = feeds
      XCTAssertEqual(found, wanted)
      
      for (i, wantedFeed) in wanted.enumerate() {
        let foundFeed = found[i]
        
        XCTAssertEqual(foundFeed.author, wantedFeed.author)
        XCTAssertEqual(foundFeed.guid, wantedFeed.guid)
        XCTAssertEqual(foundFeed.images, wantedFeed.images)
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
  }
  
  func testFeedsMatchingTerm() {
    let feeds = try! feedsFromFile("search")
    let term = "newyorker"
    XCTAssertNil(try! cache.feedsForTerm(term, limit: 50))
    
    try! cache.updateFeeds(feeds, forTerm: term)

    let found = try! cache.feedsMatchingTerm("new", limit: 3)
    
    var wanted = [Feed]()
    for i in 0...2 { wanted.append(feeds[i]) }
    
    XCTAssertEqual(found!, wanted)
  }
  
  func testEntriesMatchingTerm() {
    try! populate()
    let found = try! cache.entriesMatchingTerm("supercomputer", limit: 3)
    XCTAssertEqual(found!.count, 1)
    XCTAssertEqual(found!.first?.title, "Seven Deadly Sins")
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
      for (i, sug) in found.enumerate() {
        XCTAssertEqual(sug, input[i])
      }
    } else {
      XCTFail("should find suggestions")
    }
  }

  func hit (term: String, _ wanted: String, _ cache: [String:NSDate]) {
    if let (found, _) = subcached(term, dict: cache) {
      XCTAssertEqual(found, wanted)
      if term.lengthOfBytesUsingEncoding(NSUTF8StringEncoding) > 1 {
        let pre = term.endIndex.predecessor()
        self.hit(term.substringToIndex(pre), wanted, cache)
      }
    } else {
      XCTFail("\(term) should be cached")
    }
  }

  func testSubcached () {
    var cache = [String:NSDate]()
    cache["a"] = NSDate()
    hit("abc", "a", cache)
    cache["a"] = nil

    cache["abc"] = NSDate()
    XCTAssertNotNil(subcached("abcd", dict: cache)!.0)
    XCTAssertNil(subcached("ab", dict: cache)?.0)
  }
}
