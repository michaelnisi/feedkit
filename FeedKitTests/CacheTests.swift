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
    let url = cache.url!
    XCTAssert(fm.fileExistsAtPath(url.path!))
  }

  override func tearDown() {
    let url = cache.url!
    try! fm.removeItemAtURL(url)
    XCTAssertFalse(fm.fileExistsAtPath(url.path!), "should remove database file")
    cache = nil
    super.tearDown()
  }
  
  func testUpdateFeeds() {
    let bundle = NSBundle(forClass: self.classForCoder)
    
    let feedsURL = bundle.URLForResource("feeds", withExtension: "json")
    let feeds = try! feedsFromFileAtURL(feedsURL!)
    
    try! cache.updateFeeds(feeds)
  
    func testUpdate() {
      let feed = feeds.first!
      try! cache.updateFeeds([feed])
    }
    testUpdate()
    
    let urls = feeds.map { $0.url }
    let found = try! cache.feedsWithURLs(urls)
    
    let wanted = feeds
    XCTAssertEqual(found!, wanted)
    for (i, wantedFeed) in wanted.enumerate() {
      let foundFeed = found![i]

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
    XCTAssertNil(found)
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

  func populate() throws -> ([Feed], [Entry]) {
    let bundle = NSBundle(forClass: self.classForCoder)
    
    let feedsURL = bundle.URLForResource("feeds", withExtension: "json")
    let feeds = try! feedsFromFileAtURL(feedsURL!)
    
    try! cache.updateFeeds(feeds)
    
    let entriesURL = bundle.URLForResource("entries", withExtension: "json")
    let entries = try! entriesFromFileAtURL(entriesURL!)
    
    try! cache.updateEntries(entries)
    
    return (feeds, entries)
  }
  
  func testUpdateEntries() {
    let (feeds, entries) = try! populate()
    let urls = feeds.map { $0.url }
    let intervals = urls.map { EntryInterval(url: $0) }
    let found = try! cache.entriesOfIntervals(intervals)
    let wanted = entries
    XCTAssertEqual(found!, wanted)
    for (i, wantedEntry) in wanted.enumerate() {
      let foundEntry = found![i]
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
    XCTAssertNil(found, "should have removed entries too")
  }

  func testSuggestions() {
    let terms = ["apple", "apple watch", "apple pie"]
    let input = terms.map({ term in
      Suggestion(term: term, ts: nil)
    })
    try! cache.updateSuggestions(input, forTerm:"apple")
    if let sugs = try! cache.suggestionsForTerm("apple p") {
      XCTAssertEqual(sugs.count, 1)
      let found: Suggestion = sugs.last!
      XCTAssertNotNil(found.ts!)
      let wanted: Suggestion = input.last!
      XCTAssertEqual(found, wanted)
    } else {
      XCTFail("should find suggestion")
    }
  }

  func testRemoveSuggestions() {
    let terms = ["apple", "apple watch", "apple pie"]
    let input = terms.map({ term in
      Suggestion(term: term, ts: nil)
    })
    try! cache.updateSuggestions(input, forTerm:"apple")
    try! cache.updateSuggestions([], forTerm:"pie")
    if let found = try! cache.suggestionsForTerm("apple") {
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
